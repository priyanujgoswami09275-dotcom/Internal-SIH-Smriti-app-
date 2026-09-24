"""Shared Game Session Logging & Event Tracking.

Unified service for starting, recording actions, and completing game sessions.
Used by Match It, Daily Routine Sequencing, Number Recall, and Odd-One-Out to
log accuracy metrics, response times, and raw event history.
"""
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4
from weakref import WeakKeyDictionary
import asyncio
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from app.models.all_models import (
    GameAction,
    GameSession,
    GameTypeEnum,
)
from app.services import (
    difficulty_engine,
    odd_one_out_service,
    recall_service,
    routine_service,
)


_SESSION_LOCKS: WeakKeyDictionary[
    asyncio.AbstractEventLoop,
    tuple[asyncio.Lock, ...],
] = WeakKeyDictionary()


def _session_lock(session_id: UUID) -> asyncio.Lock:
    loop = asyncio.get_running_loop()
    locks = _SESSION_LOCKS.get(loop)
    if locks is None:
        locks = tuple(asyncio.Lock() for _ in range(64))
        _SESSION_LOCKS[loop] = locks
    return locks[session_id.int % len(locks)]


def iso_utc(value: Optional[datetime]) -> Optional[str]:
    """Serialize a (possibly naive UTC) DateTime column as ISO-8601 with Z."""
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat()


_GAME_TIMESTAMP_MAX_AGE = timedelta(days=730)
_GAME_TIMESTAMP_MAX_FUTURE = timedelta(minutes=5)


def _naive_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _normalize_game_timestamp(value: Optional[datetime]) -> Optional[datetime]:
    if value is None:
        return None
    normalized = _naive_utc(value)
    now = _naive_utc(datetime.now(timezone.utc))
    earliest = now - _GAME_TIMESTAMP_MAX_AGE
    latest = now + _GAME_TIMESTAMP_MAX_FUTURE
    return min(max(normalized, earliest), latest)


async def _start_game_session(
    db: AsyncSession,
    patient_id: UUID,
    game_type: GameTypeEnum,
    difficulty_level: int,
    content_pack_id: Optional[str] = None,
    routine_id: Optional[str] = None,
    idempotency_key: Optional[str] = None,
    started_at: Optional[datetime] = None,
    completed_at: Optional[datetime] = None,
) -> tuple[GameSession, bool]:
    normalized_started = _normalize_game_timestamp(started_at)
    if normalized_started is None:
        normalized_started = _naive_utc(datetime.now(timezone.utc))
    normalized_completed = _normalize_game_timestamp(completed_at)
    if normalized_completed is not None and normalized_completed < normalized_started:
        normalized_completed = normalized_started

    if idempotency_key:
        existing_result = await db.execute(
            select(GameSession).where(
                GameSession.patient_id == patient_id,
                GameSession.idempotency_key == idempotency_key,
            )
        )
        existing = existing_result.scalar_one_or_none()
        if existing is not None:
            return existing, True

    session = GameSession(
        patient_id=patient_id,
        game_type=game_type,
        difficulty_level=difficulty_level,
        idempotency_key=idempotency_key,
        started_at=normalized_started,
        replay_completed_at=normalized_completed,
        content_pack_id=content_pack_id,
        routine_id=routine_id,
        correct_count=0,
        incorrect_count=0,
        attempts=0,
        raw_event_log=[],
    )
    db.add(session)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        if idempotency_key:
            existing_result = await db.execute(
                select(GameSession).where(
                    GameSession.patient_id == patient_id,
                    GameSession.idempotency_key == idempotency_key,
                )
            )
            existing = existing_result.scalar_one_or_none()
            if existing is not None:
                return existing, True
        raise
    await db.refresh(session)
    return session, False


async def start_game_session(
    db: AsyncSession,
    patient_id: UUID,
    game_type: GameTypeEnum,
    difficulty_level: int,
    content_pack_id: Optional[str] = None,
    routine_id: Optional[str] = None,
    idempotency_key: Optional[str] = None,
    started_at: Optional[datetime] = None,
    completed_at: Optional[datetime] = None,
) -> GameSession:
    session, _ = await _start_game_session(
        db,
        patient_id=patient_id,
        game_type=game_type,
        difficulty_level=difficulty_level,
        content_pack_id=content_pack_id,
        routine_id=routine_id,
        idempotency_key=idempotency_key,
        started_at=started_at,
        completed_at=completed_at,
    )
    return session


async def start_game_session_with_replay(
    db: AsyncSession,
    patient_id: UUID,
    game_type: GameTypeEnum,
    difficulty_level: int,
    content_pack_id: Optional[str] = None,
    routine_id: Optional[str] = None,
    idempotency_key: Optional[str] = None,
    started_at: Optional[datetime] = None,
    completed_at: Optional[datetime] = None,
) -> tuple[GameSession, bool]:
    return await _start_game_session(
        db,
        patient_id=patient_id,
        game_type=game_type,
        difficulty_level=difficulty_level,
        content_pack_id=content_pack_id,
        routine_id=routine_id,
        idempotency_key=idempotency_key,
        started_at=started_at,
        completed_at=completed_at,
    )


class GameActionValidationError(ValueError):
    pass


class GameSessionCompletedError(RuntimeError):
    pass


class GameActionBarrierError(RuntimeError):
    pass


class GameCompletionConflictError(RuntimeError):
    pass


def _game_action_event(action: GameAction) -> Dict[str, Any]:
    event = {
        "timestamp": action.created_at.isoformat() if action.created_at else None,
        "idempotency_key": action.idempotency_key,
        "action_type": action.action_type,
        "action_data": action.action_data or {},
        "is_correct": action.is_correct,
        "response_time_ms": action.response_time_ms,
    }
    if isinstance(action.server_fields, dict):
        event.update(action.server_fields)
    return event


def _score_match_it(
    session: GameSession,
    action_data: Dict[str, Any],
) -> tuple[Dict[str, Any], Optional[bool], Dict[str, Any]]:
    board = session.board_snapshot if isinstance(session.board_snapshot, dict) else {}
    cards = board.get("cards")
    if not isinstance(cards, list) or not cards:
        raise GameActionValidationError(
            "no server board for this session; fetch board first"
        )
    card_id = action_data.get("card_id")
    if card_id is None or isinstance(card_id, bool):
        raise GameActionValidationError("flip_card requires card_id")
    card_key = str(card_id)
    cards_by_id = {
        str(card.get("card_id")): card
        for card in cards
        if isinstance(card, dict) and card.get("card_id") is not None
    }
    card = cards_by_id.get(card_key)
    if card is None:
        raise GameActionValidationError("card_id is not on the server board")

    state = dict(session.server_state or {})
    matched = {str(value) for value in state.get("matched_card_ids", [])}
    if card_key in matched:
        raise GameActionValidationError("card is already matched")

    item_id = card["item_id"]
    pending_card_id = state.get("pending_card_id")
    if pending_card_id is None:
        state["pending_card_id"] = card_key
        state["pending_item_id"] = item_id
        is_correct = None
    else:
        is_correct = state.get("pending_item_id") == item_id
        state.pop("pending_card_id", None)
        state.pop("pending_item_id", None)
        if is_correct:
            matched.update((card_key, str(pending_card_id)))
            state["matched_card_ids"] = sorted(matched)
    session.server_state = state
    scored_data = dict(action_data)
    scored_data["item_id"] = item_id
    scored_data["is_correct"] = is_correct
    return scored_data, is_correct, {}


def _score_routine(
    session: GameSession,
    action_data: Dict[str, Any],
) -> tuple[Dict[str, Any], Optional[bool], Dict[str, Any]]:
    board = session.board_snapshot if isinstance(session.board_snapshot, dict) else {}
    correct_sequence = board.get("correct_sequence")
    if not isinstance(correct_sequence, list) or not correct_sequence:
        raise GameActionValidationError(
            "no server board for this session; fetch board first"
        )
    position = action_data.get("position")
    step_id = action_data.get("step_id")
    if isinstance(position, bool) or not isinstance(position, int):
        raise GameActionValidationError("place_step requires integer position")
    if not 0 <= position < len(correct_sequence):
        raise GameActionValidationError("position is outside the server board")
    if not isinstance(step_id, str) or not step_id:
        raise GameActionValidationError("place_step requires step_id")

    state = dict(session.server_state or {})
    submitted = list(state.get("submitted_sequence") or [])
    if len(submitted) <= position:
        submitted.extend([None] * (position + 1 - len(submitted)))
    if submitted[position] is not None:
        raise GameActionValidationError("position was already submitted")
    before = routine_service.validate_routine_sequence(submitted, correct_sequence)
    submitted[position] = step_id
    validation = routine_service.validate_routine_sequence(submitted, correct_sequence)
    state["submitted_sequence"] = submitted
    session.server_state = state
    is_correct = validation["correct_count"] > before["correct_count"]
    scored_data = dict(action_data)
    scored_data["expected_step_id"] = correct_sequence[position]
    scored_data["is_correct"] = is_correct
    return scored_data, is_correct, {}


def _score_recall(
    session: GameSession,
    action_data: Dict[str, Any],
) -> tuple[Dict[str, Any], Optional[bool], Dict[str, Any]]:
    board = session.board_snapshot if isinstance(session.board_snapshot, dict) else {}
    sequence = board.get("sequence")
    if not isinstance(sequence, list) or not sequence:
        raise GameActionValidationError(
            "no server board for this session; fetch board first"
        )
    position = action_data.get("position")
    digit = action_data.get("digit")
    if isinstance(position, bool) or not isinstance(position, int):
        raise GameActionValidationError("recall_tap requires integer position")
    if not 0 <= position < len(sequence):
        raise GameActionValidationError("position is outside the server board")
    if isinstance(digit, bool) or not isinstance(digit, int) or not 0 <= digit <= 9:
        raise GameActionValidationError("recall_tap requires digit from 0 to 9")

    state = dict(session.server_state or {})
    submitted = list(state.get("submitted_sequence") or [])
    if len(submitted) <= position:
        submitted.extend([None] * (position + 1 - len(submitted)))
    if submitted[position] is not None:
        raise GameActionValidationError("position was already submitted")
    before = recall_service.score_number_recall(submitted, sequence)
    submitted[position] = digit
    validation = recall_service.score_number_recall(submitted, sequence)
    state["submitted_sequence"] = submitted
    session.server_state = state
    is_correct = validation["correct_count"] > before["correct_count"]
    scored_data = dict(action_data)
    scored_data["expected"] = sequence[position]
    scored_data["is_correct"] = is_correct
    return scored_data, is_correct, {}


def _score_odd_one_out(
    session: GameSession,
    action_data: Dict[str, Any],
) -> tuple[Dict[str, Any], Optional[bool], Dict[str, Any]]:
    state = session.server_state if isinstance(session.server_state, dict) else {}
    answer_item_id = state.get("answer_item_id")
    board = session.board_snapshot if isinstance(session.board_snapshot, dict) else {}
    item_ids = {
        item.get("item_id")
        for item in board.get("items", [])
        if isinstance(item, dict)
    }
    selected_item_id = action_data.get("selected_item_id")
    if not answer_item_id:
        raise GameActionValidationError(
            "no server board for this session; fetch board first"
        )
    if selected_item_id not in item_ids:
        raise GameActionValidationError("selected_item_id is not on the server board")
    verdict = odd_one_out_service.score_odd_one_out(
        selected_item_id,
        answer_item_id,
    )
    scored_data = dict(action_data)
    scored_data["is_correct"] = verdict["correct"]
    return scored_data, verdict["correct"], {
        "error_category": verdict["error_category"],
        "opportunity": verdict["opportunity"],
    }


def _score_game_action(
    session: GameSession,
    action_type: str,
    action_data: Dict[str, Any],
) -> tuple[Dict[str, Any], Optional[bool], Dict[str, Any]]:
    if session.game_type == GameTypeEnum.MATCH_IT and action_type == "flip_card":
        return _score_match_it(session, action_data)
    if session.game_type == GameTypeEnum.ROUTINE_SEQUENCING and action_type == "place_step":
        return _score_routine(session, action_data)
    if session.game_type == GameTypeEnum.NUMBER_RECALL and action_type == "recall_tap":
        return _score_recall(session, action_data)
    if session.game_type == GameTypeEnum.ODD_ONE_OUT and action_type == "select_odd_item":
        return _score_odd_one_out(session, action_data)
    return dict(action_data), None, {}


async def record_game_action(
    db: AsyncSession,
    session_id: UUID,
    action_type: str,
    action_data: Dict[str, Any],
    is_correct: Optional[bool] = None,
    response_time_ms: Optional[int] = None,
    idempotency_key: Optional[str] = None,
) -> tuple[Dict[str, Any], bool]:
    """Record one server-scored action with durable idempotent storage."""
    key = idempotency_key or f"legacy-{uuid4()}"
    async with _session_lock(session_id):
        result = await db.execute(
            select(GameSession)
            .where(GameSession.id == session_id)
            .with_for_update()
        )
        session = result.scalar_one_or_none()
        if not session:
            raise ValueError(f"Game session {session_id} not found")
        if session.completed_at is not None:
            raise GameSessionCompletedError("Game session is already completed")

        existing = await db.execute(
            select(GameAction).where(
                GameAction.session_id == session_id,
                GameAction.idempotency_key == key,
            )
        )
        duplicate = existing.scalar_one_or_none()
        if duplicate is not None:
            return _game_action_event(duplicate), True

        scored_data, server_verdict, server_fields = _score_game_action(
            session,
            action_type,
            action_data,
        )
        if server_verdict is not None:
            if server_verdict:
                session.correct_count += 1
            else:
                session.incorrect_count += 1
            session.attempts += 1

        now = datetime.now(timezone.utc)
        action = GameAction(
            session_id=session_id,
            idempotency_key=key,
            action_type=action_type,
            action_data=scored_data,
            is_correct=server_verdict,
            response_time_ms=response_time_ms,
            server_fields=server_fields or None,
            created_at=now.replace(tzinfo=None),
        )
        db.add(action)
        await db.flush()
        return _game_action_event(action), False


async def complete_game_session(
    db: AsyncSession,
    session_id: UUID,
    *,
    idempotency_key: Optional[str] = None,
    expected_action_ids: Optional[List[str]] = None,
    completed_at: Optional[datetime] = None,
) -> tuple[Dict[str, Any], bool]:
    """Finalize only after expected actions are durable; replay is a no-op."""
    async with _session_lock(session_id):
        result = await db.execute(
            select(GameSession)
            .where(GameSession.id == session_id)
            .with_for_update()
        )
        session = result.scalar_one_or_none()
        if not session:
            raise ValueError(f"Game session {session_id} not found")

        if session.completed_at is not None:
            if (
                idempotency_key is not None
                and session.completion_idempotency_key is not None
                and idempotency_key != session.completion_idempotency_key
            ):
                raise GameCompletionConflictError(
                    "Game session was completed with a different idempotency key"
                )
            if isinstance(session.completion_result, dict):
                return dict(session.completion_result), True

        expected = list(dict.fromkeys(expected_action_ids or []))
        if expected:
            durable = await db.execute(
                select(GameAction.idempotency_key).where(
                    GameAction.session_id == session_id,
                    GameAction.idempotency_key.in_(expected),
                )
            )
            durable_keys = set(durable.scalars().all())
            missing = sorted(set(expected) - durable_keys)
            if missing:
                raise GameActionBarrierError(
                    "expected actions are not durable: " + ", ".join(missing)
                )

        rows = await db.execute(
            select(GameAction)
            .where(GameAction.session_id == session_id)
            .order_by(GameAction.created_at.asc(), GameAction.id.asc())
        )
        actions = list(rows.scalars().all())
        legacy_events = [
            dict(event)
            for event in (session.raw_event_log or [])
            if isinstance(event, dict) and not event.get("idempotency_key")
        ]
        events = legacy_events + [_game_action_event(action) for action in actions]
        scored_events = [event for event in events if event.get("is_correct") is not None]
        total_attempts = len(scored_events)
        correct_count = sum(1 for event in scored_events if event["is_correct"])
        incorrect_count = total_attempts - correct_count
        accuracy_pct = (
            round((correct_count / total_attempts) * 100.0, 1)
            if total_attempts
            else 0.0
        )
        response_times = [
            event["response_time_ms"]
            for event in events
            if isinstance(event.get("response_time_ms"), (int, float))
        ]
        avg_response_time_ms = (
            round(sum(response_times) / len(response_times), 1)
            if response_times
            else 0.0
        )

        completion_timestamp = _normalize_game_timestamp(completed_at)
        if completion_timestamp is None:
            completion_timestamp = _normalize_game_timestamp(session.replay_completed_at)
        if completion_timestamp is None:
            completion_timestamp = _naive_utc(datetime.now(timezone.utc))
        started_timestamp = _naive_utc(session.started_at)
        if completion_timestamp < started_timestamp:
            completion_timestamp = started_timestamp
        session.completed_at = completion_timestamp
        session.attempts = total_attempts
        session.correct_count = correct_count
        session.incorrect_count = incorrect_count
        session.accuracy_pct = accuracy_pct
        session.avg_response_time_ms = avg_response_time_ms
        session.raw_event_log = events
        if idempotency_key is not None:
            session.completion_idempotency_key = idempotency_key

        await db.flush()
        difficulty = await difficulty_engine.evaluate_difficulty(
            db,
            patient_id=session.patient_id,
            game_type=session.game_type,
            current_difficulty=session.difficulty_level,
            commit=False,
        )
        recommended_level = (
            difficulty["new_difficulty"]
            if difficulty["new_difficulty"] is not None
            else session.difficulty_level
        )
        result = {
            "session_id": str(session.id),
            "patient_id": str(session.patient_id),
            "game_type": session.game_type.value,
            "difficulty_level": session.difficulty_level,
            "total_attempts": total_attempts,
            "correct_count": correct_count,
            "incorrect_count": incorrect_count,
            "accuracy_pct": accuracy_pct,
            "avg_response_time_ms": avg_response_time_ms,
            "started_at": session.started_at.isoformat(),
            "completed_at": session.completed_at.isoformat(),
            "recommended_level": recommended_level,
            "difficulty_reason": difficulty["reason"],
            "difficulty_source": difficulty.get("source"),
            "rule_triggered": difficulty.get("rule_triggered"),
            "rule_version": difficulty.get("rule_version"),
            "shadow_probability": difficulty.get("shadow_probability"),
            "shadow_model_version": difficulty.get("shadow_model_version"),
            "shadow_reason": difficulty.get("shadow_reason"),
        }
        if session.game_type == GameTypeEnum.ODD_ONE_OUT:
            result["explanation"] = odd_one_out_service.odd_one_out_explanation(
                session.server_state
            )
        session.completion_result = result
        await db.commit()
        return result, False


async def get_session_summary(db: AsyncSession, session_id: UUID) -> Dict[str, Any]:
    """Retrieve a session's final summary (without raw event log for conciseness)."""
    result = await db.execute(select(GameSession).where(GameSession.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise ValueError(f"Game session {session_id} not found")

    return {
        "session_id": session.id,
        "patient_id": session.patient_id,
        "game_type": session.game_type.value,
        "difficulty_level": session.difficulty_level,
        "correct_count": session.correct_count,
        "incorrect_count": session.incorrect_count,
        "attempts": session.attempts,
        "accuracy_pct": session.accuracy_pct,
        "avg_response_time_ms": session.avg_response_time_ms,
        "started_at": session.started_at.isoformat() if session.started_at else None,
        "completed_at": session.completed_at.isoformat() if session.completed_at else None,
    }


async def get_patient_game_history(
    db: AsyncSession,
    patient_id: UUID,
    game_type: Optional[GameTypeEnum] = None,
    limit: int = 10,
) -> List[Dict[str, Any]]:
    """Retrieve recent game sessions for a patient.

    Used by dashboard to build trend graphs (accuracy over time,
    response-time progression, etc.).
    """
    query = select(GameSession).where(GameSession.patient_id == patient_id)
    if game_type:
        query = query.where(GameSession.game_type == game_type)
    query = query.order_by(GameSession.started_at.desc()).limit(limit)

    result = await db.execute(query)
    sessions = result.scalars().all()

    return [
        {
            "session_id": s.id,
            "game_type": s.game_type.value,
            "difficulty_level": s.difficulty_level,
            "accuracy_pct": s.accuracy_pct,
            "avg_response_time_ms": s.avg_response_time_ms,
            "completed_at": s.completed_at.isoformat() if s.completed_at else None,
        }
        for s in sessions
    ]

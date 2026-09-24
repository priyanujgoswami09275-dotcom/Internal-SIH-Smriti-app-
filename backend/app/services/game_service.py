"""Shared Game Session Logging & Event Tracking.

Unified service for starting, recording actions, and completing game sessions.
Used by Match It, Daily Routine Sequencing, Number Recall, and Odd-One-Out to
log accuracy metrics, response times, and raw event history.
"""
from typing import List, Dict, Any, Optional
from datetime import datetime, timezone
from uuid import UUID
import json
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from app.models.all_models import (
    GameSession,
    GameTypeEnum,
)
from app.services import odd_one_out_service, recall_service, routine_service


def iso_utc(value: Optional[datetime]) -> Optional[str]:
    """Serialize a (possibly naive UTC) DateTime column as ISO-8601 with Z."""
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat()


async def start_game_session(
    db: AsyncSession,
    patient_id: UUID,
    game_type: GameTypeEnum,
    difficulty_level: int,
    content_pack_id: Optional[str] = None,
    routine_id: Optional[str] = None,
) -> GameSession:
    """Create a new game session.

    Args:
        patient_id: Patient playing the game.
        game_type: Match It, Routine Sequencing, etc.
        difficulty_level: 1, 2, 3 (scaled by game type).
        content_pack_id: For Match It (festivals, fruits, heritage, etc.).
        routine_id: For Routine Sequencing (custom or default).

    Returns:
        New GameSession record with started_at timestamp.
    """
    session = GameSession(
        patient_id=patient_id,
        game_type=game_type,
        difficulty_level=difficulty_level,
        started_at=datetime.now(timezone.utc),
        content_pack_id=content_pack_id,
        routine_id=routine_id,
        correct_count=0,
        incorrect_count=0,
        attempts=0,
        raw_event_log=[],
    )
    db.add(session)
    await db.flush()
    await db.refresh(session)
    return session


class GameActionValidationError(ValueError):
    pass


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
) -> Dict[str, Any]:
    """Record an action whose correctness is derived only from server state."""
    result = await db.execute(select(GameSession).where(GameSession.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise ValueError(f"Game session {session_id} not found")

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

    event = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "action_type": action_type,
        "action_data": scored_data,
        "is_correct": server_verdict,
        "response_time_ms": response_time_ms,
        **server_fields,
    }
    updated_log = list(session.raw_event_log or [])
    updated_log.append(event)
    session.raw_event_log = updated_log
    await db.flush()
    return event


async def complete_game_session(
    db: AsyncSession,
    session_id: UUID,
) -> Dict[str, Any]:
    """Mark session as complete and compute final metrics.

    Returns a summary dict with:
        - session_id
        - total_attempts
        - correct_count, incorrect_count
        - accuracy_pct
        - avg_response_time_ms (computed from raw_event_log)
        - completed_at
    """
    result = await db.execute(select(GameSession).where(GameSession.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise ValueError(f"Game session {session_id} not found")

    session.completed_at = datetime.now(timezone.utc)

    # Compute final metrics from raw_event_log
    response_times = [
        e["response_time_ms"]
        for e in (session.raw_event_log or [])
        if e.get("response_time_ms") is not None
    ]
    avg_response_time_ms = (
        round(sum(response_times) / len(response_times), 1) if response_times else 0.0
    )

    total_attempts = session.attempts or 0
    accuracy_pct = (
        round((session.correct_count / total_attempts) * 100.0, 1)
        if total_attempts > 0
        else 0.0
    )

    session.avg_response_time_ms = avg_response_time_ms
    session.accuracy_pct = accuracy_pct

    await db.commit()
    await db.refresh(session)

    result = {
        "session_id": session.id,
        "patient_id": session.patient_id,
        "game_type": session.game_type.value,
        "difficulty_level": session.difficulty_level,
        "total_attempts": total_attempts,
        "correct_count": session.correct_count,
        "incorrect_count": session.incorrect_count,
        "accuracy_pct": accuracy_pct,
        "avg_response_time_ms": avg_response_time_ms,
        "started_at": session.started_at.isoformat(),
        "completed_at": session.completed_at.isoformat(),
    }
    if session.game_type == GameTypeEnum.ODD_ONE_OUT:
        result["explanation"] = odd_one_out_service.odd_one_out_explanation(
            session.server_state
        )
    return result


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

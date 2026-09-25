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
        # Naive UTC: DateTime columns drop tzinfo; adaptive_features.timestamp()
        # treats naive values as UTC (must not be stored as server-local time).
        started_at=datetime.now(timezone.utc).replace(tzinfo=None),
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


async def record_game_action(
    db: AsyncSession,
    session_id: UUID,
    action_type: str,
    action_data: Dict[str, Any],
    is_correct: Optional[bool] = None,
    response_time_ms: Optional[int] = None,
) -> Dict[str, Any]:
    """Record a single player action within a game session.

    For Match It:
        action_type: "flip_card"
        action_data: {"card_id": 1, "item_id": "bihu"}
        is_correct: Whether the flip matched a previous flip
        response_time_ms: Time from card prompt to flip

    For Routine Sequencing:
        action_type: "place_step"
        action_data: {"position": 0, "step_id": "wake_up"}
        is_correct: Whether step is in correct position for final submission
        response_time_ms: Time from step shown to placement

    For Number Recall:
        action_type: "show_sequence" (is_correct=None marker) / "recall_tap"
        action_data: {"position": 0, "digit": 5, "expected": 5}
        is_correct: Whether the tapped digit matches the expected digit
        response_time_ms: Time from recall prompt to tap

    For Odd-One-Out:
        action_type: "select_odd_item"
        action_data: {"selected_item_id": "dhol"}
        is_correct: IGNORED — the route scores server-side from the stored
            board_snapshot answer via score_odd_one_out and persists the
            server verdict + error_category ("semantic_category") in the
            event; a NULL snapshot is rejected before this service runs.
        response_time_ms: Time from board display to selection
    """
    result = await db.execute(select(GameSession).where(GameSession.id == session_id))
    session = result.scalar_one_or_none()
    if not session:
        raise ValueError(f"Game session {session_id} not found")

    # Update running counts. Only resolved attempts (is_correct set) count
    # toward attempts/accuracy; informational events (first flips, stuck
    # telemetry) stay metric-free so they cannot deflate accuracy_pct.
    if is_correct is not None:
        if is_correct:
            session.correct_count += 1
        else:
            session.incorrect_count += 1
        session.attempts += 1

    # Build event record
    event = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "action_type": action_type,
        "action_data": action_data,
        "is_correct": is_correct,
        "response_time_ms": response_time_ms,
    }

    # Append to raw_event_log (JSONB array). Reassign — don't mutate — so
    # SQLAlchemy's change detection persists the new list on flush.
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

    session.completed_at = datetime.now(timezone.utc).replace(tzinfo=None)

    # Compute final metrics from raw_event_log
    response_times = [
        e["response_time_ms"]
        for e in (session.raw_event_log or [])
        if e.get("response_time_ms") is not None
    ]
    avg_response_time_ms = (
        round(sum(response_times) / len(response_times), 1) if response_times else 0.0
    )

    total_attempts = session.attempts or 1
    accuracy_pct = (
        round((session.correct_count / total_attempts) * 100.0, 1)
        if total_attempts > 0
        else 0.0
    )

    session.avg_response_time_ms = avg_response_time_ms
    session.accuracy_pct = accuracy_pct

    await db.commit()
    await db.refresh(session)

    return {
        "session_id": session.id,
        "patient_id": session.patient_id,
        "game_type": session.game_type.value,
        "difficulty_level": session.difficulty_level,
        "total_attempts": total_attempts,
        "correct_count": session.correct_count,
        "incorrect_count": session.incorrect_count,
        "accuracy_pct": accuracy_pct,
        "avg_response_time_ms": avg_response_time_ms,
        "started_at": iso_utc(session.started_at),
        "completed_at": iso_utc(session.completed_at),
    }


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
        "started_at": iso_utc(session.started_at),
        "completed_at": iso_utc(session.completed_at),
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
            "completed_at": iso_utc(s.completed_at),
        }
        for s in sessions
    ]

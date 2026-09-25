"""Game Engine Service — Unified Class Interface for Game Sessions & Adaptive Difficulty."""
import uuid
from typing import Tuple, Dict, Any, Optional
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.all_models import GameSession, GameTypeEnum
from app.services.game_service import start_game_session, complete_game_session, record_game_action
from app.services.difficulty_engine import evaluate_difficulty

class GameEngineService:
    @staticmethod
    async def log_game_session(
        db: AsyncSession,
        patient_id: uuid.UUID,
        game_type: GameTypeEnum,
        difficulty_level: int,
        attempts: int,
        correct_count: int,
        incorrect_count: int,
        avg_response_time_ms: float,
    ) -> GameSession:
        """Create and complete a game session with explicit outcome metrics."""
        session = await start_game_session(
            db=db,
            patient_id=patient_id,
            game_type=game_type,
            difficulty_level=difficulty_level,
        )
        session.attempts = attempts
        session.correct_count = correct_count
        session.incorrect_count = incorrect_count
        session.avg_response_time_ms = avg_response_time_ms
        session.accuracy_pct = (correct_count / attempts * 100.0) if attempts > 0 else 0.0
        session.completed_at = datetime.now(timezone.utc).replace(tzinfo=None)

        await db.commit()
        await db.refresh(session)
        return session

    @staticmethod
    async def compute_next_difficulty(
        db: AsyncSession,
        patient_id: uuid.UUID,
        game_type: GameTypeEnum,
        current_difficulty: int,
    ) -> Tuple[int, str]:
        """Compute the next adaptive difficulty level and reasoning."""
        res = await evaluate_difficulty(
            db=db,
            patient_id=patient_id,
            game_type=game_type,
            current_difficulty=current_difficulty,
        )
        new_diff = res.get("new_difficulty") or current_difficulty
        if new_diff > current_difficulty:
            reason = f"Advancing to Level {new_diff}: Sustained high accuracy performance."
        elif new_diff < current_difficulty:
            reason = f"Adjusting to Level {new_diff}: Providing support for low accuracy sessions."
        else:
            reason = "Maintaining current difficulty level."
        return new_diff, reason

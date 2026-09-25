"""Adaptive Difficulty Engine — Rule-Based Strategy Implementation.

Implements a pluggable strategy pattern for difficulty adjustments.
MVP uses rule-based thresholds; future versions can swap in ML-based strategies
without touching the game engine.
"""
from typing import List, Dict, Any, Optional
from abc import ABC, abstractmethod
from datetime import datetime, timezone, timedelta
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.services.adaptive_shadow import evaluate_shadow
from app.models.all_models import (
    GameSession,
    DifficultyAdjustmentLog,
    GameTypeEnum,
)


class DifficultyStrategy(ABC):
    """Abstract base for difficulty adjustment strategies."""

    @abstractmethod
    async def calculate_adjustment(
        self,
        db: AsyncSession,
        patient_id: UUID,
        game_type: GameTypeEnum,
        current_difficulty: int,
        recent_sessions: List[GameSession],
    ) -> Optional[int]:
        """
        Determine if difficulty should change based on recent performance.

        Args:
            db: Database session.
            patient_id: Patient being evaluated.
            game_type: The game type (Match It, Routine Sequencing, etc).
            current_difficulty: Current difficulty level (1, 2, 3).
            recent_sessions: Recent game sessions (ordered by date, newest first).

        Returns:
            New difficulty level (1-3) or None if no change.
        """
        pass


class RuleBasedDifficultyStrategy(DifficultyStrategy):
    """Rule-based difficulty adjustment using explicit thresholds."""

    # Thresholds for difficulty bumps and drops
    BUMP_THRESHOLDS = {
        "consecutive_high_accuracy": 3,  # 3 consecutive sessions > 85%
        "high_accuracy_pct": 85.0,
        "response_time_threshold_ms": 8000,  # bump if avg < 8 sec
    }

    DROP_THRESHOLDS = {
        "consecutive_low_accuracy": 2,  # 2 consecutive sessions < 50%
        "low_accuracy_pct": 50.0,
    }

    async def calculate_adjustment(
        self,
        db: AsyncSession,
        patient_id: UUID,
        game_type: GameTypeEnum,
        current_difficulty: int,
        recent_sessions: List[GameSession],
    ) -> Optional[int]:
        """Apply rule-based thresholds to determine difficulty change."""
        if not recent_sessions:
            return None

        # Rule 1: Check for difficulty bump (3 consecutive high-accuracy sessions)
        if current_difficulty < 3:  # Can only bump up to level 3
            bump_candidate = self._check_bump_rule(recent_sessions)
            if bump_candidate:
                return current_difficulty + 1

        # Rule 2: Check for difficulty drop (2 consecutive low-accuracy sessions)
        if current_difficulty > 1:  # Can only drop down to level 1
            drop_candidate = self._check_drop_rule(recent_sessions)
            if drop_candidate:
                return current_difficulty - 1

        return None

    def _check_bump_rule(self, recent_sessions: List[GameSession]) -> bool:
        """Bump difficulty if 3+ consecutive sessions all have >85% accuracy."""
        consecutive_high = 0
        for session in recent_sessions[:5]:  # Check last 5 sessions max
            if session.accuracy_pct is not None and session.accuracy_pct > self.BUMP_THRESHOLDS["high_accuracy_pct"]:
                consecutive_high += 1
                if consecutive_high >= self.BUMP_THRESHOLDS["consecutive_high_accuracy"]:
                    return True
            else:
                break  # Streak broken
        return False

    def _check_drop_rule(self, recent_sessions: List[GameSession]) -> bool:
        """Drop difficulty if 2+ consecutive sessions both have <50% accuracy."""
        consecutive_low = 0
        for session in recent_sessions[:5]:  # Check last 5 sessions max
            if session.accuracy_pct is not None and session.accuracy_pct < self.DROP_THRESHOLDS["low_accuracy_pct"]:
                consecutive_low += 1
                if consecutive_low >= self.DROP_THRESHOLDS["consecutive_low_accuracy"]:
                    return True
            else:
                break  # Streak broken
        return False


async def get_recent_sessions(
    db: AsyncSession,
    patient_id: UUID,
    game_type: GameTypeEnum,
    days_back: int = 30,
    limit: int = 20,
) -> List[GameSession]:
    """Retrieve recent completed game sessions for a patient."""
    # Naive UTC: GameSession DateTime columns are timezone-naive (UTC wall time).
    cutoff_date = (datetime.now(timezone.utc) - timedelta(days=days_back)).replace(tzinfo=None)

    query = (
        select(GameSession)
        .where(
            GameSession.patient_id == patient_id,
            GameSession.game_type == game_type,
            GameSession.completed_at.isnot(None),
            GameSession.completed_at >= cutoff_date,
        )
        .order_by(GameSession.completed_at.desc())
        .limit(limit)
    )

    result = await db.execute(query)
    sessions = result.scalars().all()
    return list(sessions)


async def evaluate_difficulty(
    db: AsyncSession,
    patient_id: UUID,
    game_type: GameTypeEnum,
    current_difficulty: int,
    strategy: Optional[DifficultyStrategy] = None,
) -> Dict[str, Any]:
    """
    Evaluate if difficulty should change for a patient's game.

    Returns a dict with:
        - new_difficulty: proposed level (or None if no change)
        - reason: explanation of the adjustment
        - rule_triggered: which rule (if any) triggered the change
    """
    # Naive UTC so evaluate_shadow history query matches DateTime columns.
    decision_time = datetime.now(timezone.utc).replace(tzinfo=None)
    if strategy is None:
        strategy = RuleBasedDifficultyStrategy()
    default_rules = type(strategy) is RuleBasedDifficultyStrategy

    recent_sessions = await get_recent_sessions(db, patient_id, game_type)

    new_difficulty = await strategy.calculate_adjustment(
        db, patient_id, game_type, current_difficulty, recent_sessions
    )

    reason = "No change"
    rule_triggered = None

    if new_difficulty and new_difficulty != current_difficulty:
        direction = "bump" if new_difficulty > current_difficulty else "drop"
        reason = f"Difficulty {direction} from {current_difficulty} to {new_difficulty}"
        rule_triggered = direction

    shadow = dict(shadow_probability=None, shadow_model_version=None, shadow_reason="custom_strategy")
    if default_rules:
        try:
            shadow = await evaluate_shadow(db, patient_id, game_type, current_difficulty, decision_time)
        except Exception:
            shadow = dict(shadow_probability=None, shadow_model_version=None, shadow_reason="inference_error")
    resulting_level = new_difficulty if new_difficulty is not None else current_difficulty
    metadata = dict(
        source="rule_fallback" if default_rules else "custom_strategy",
        rule_version="rules-85-50-v1" if default_rules else None,
        result="raise" if resulting_level > current_difficulty else "lower" if resulting_level < current_difficulty else "hold",
        **shadow,
    )
    await _log_adjustment(db, patient_id, game_type, current_difficulty, resulting_level, reason,
                          adjusted_at=decision_time, **metadata)

    return {
        **metadata,
        "new_difficulty": new_difficulty,
        "reason": reason,
        "rule_triggered": rule_triggered,
        "recent_sessions_reviewed": len(recent_sessions),
    }


async def _log_adjustment(
    db: AsyncSession,
    patient_id: UUID,
    game_type: GameTypeEnum,
    old_difficulty: int,
    new_difficulty: int,
    reason: str,
    *,
    adjusted_at=None,
    **metadata,
) -> None:
    """Log a difficulty adjustment for audit trail."""
    log = DifficultyAdjustmentLog(
        patient_id=patient_id,
        game_type=game_type,
        old_difficulty=old_difficulty,
        new_difficulty=new_difficulty,
        reason=reason,
        adjusted_at=adjusted_at or datetime.now(timezone.utc),
        **metadata,
    )
    db.add(log)
    await db.commit()

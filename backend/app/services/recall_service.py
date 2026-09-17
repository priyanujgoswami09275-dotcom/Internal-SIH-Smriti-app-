"""Number Recall game: memorize a digit sequence, repeat it in order.

Asset-free by design (no image/audio content needed): the board is a digit
sequence whose length resolves from game_level_config — no divergent
difficulty map. Sessions log through the shared game pipeline
(start/action/complete), so dashboard trends pick the game up automatically.

Action types (mirrored by mobile recall_service.dart):
  - show_sequence: memorization marker {sequence_length}; send with
    is_correct=None so it never counts as an attempt.
  - recall_tap: {position, digit, expected} with is_correct +
    response_time_ms; each tap is one scored attempt.
"""
import random
from typing import Any, Dict, List, Optional

from app.services.level_config_service import default_params

RECALL_ACTION_TYPES = ("show_sequence", "recall_tap")


def recall_config(difficulty_level: int) -> Dict[str, Any]:
    """Resolve (sequence_length, show_seconds_per_item) from level config."""
    cfg = default_params("number_recall", difficulty_level)
    return {
        "sequence_length": cfg.get("sequence_length", 3),
        "show_seconds_per_item": cfg.get("show_seconds_per_item", 2),
    }


def generate_number_recall_board(
    difficulty_level: int = 1,
    sequence_length: Optional[int] = None,
    show_seconds_per_item: Optional[int] = None,
    rng: Optional[random.Random] = None,
) -> Dict[str, Any]:
    """Generate a memorization board: unique digits shown, then recalled.

    Length resolves from game_level_config when omitted (routes pass the
    DB-resolved value). Digits are unique within a sequence for fairness.
    """
    cfg = recall_config(difficulty_level)
    if sequence_length is None:
        sequence_length = cfg["sequence_length"]
    if show_seconds_per_item is None:
        show_seconds_per_item = cfg["show_seconds_per_item"]
    dice = rng or random
    sequence = dice.sample(range(10), min(sequence_length, 10))
    return {
        "game_type": "number_recall",
        "difficulty_level": difficulty_level,
        "sequence_length": len(sequence),
        "show_seconds_per_item": show_seconds_per_item,
        "sequence": sequence,
    }


def score_number_recall(
    submitted: List[int], sequence: List[int]
) -> Dict[str, Any]:
    """Score a recalled sequence positionally (same shape as routine scoring)."""
    total = len(sequence)
    correct_positions = 0
    errors = []
    for idx, expected in enumerate(sequence):
        got = submitted[idx] if idx < len(submitted) else None
        if got == expected:
            correct_positions += 1
        else:
            errors.append({"position": idx, "expected": expected, "got": got})
    return {
        "is_perfect": total > 0 and correct_positions == total,
        "accuracy_pct": round((correct_positions / total) * 100.0, 1) if total else 0.0,
        "correct_count": correct_positions,
        "total": total,
        "errors": errors,
    }

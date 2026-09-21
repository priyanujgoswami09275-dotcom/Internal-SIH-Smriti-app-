"""Game level config — single source of truth for difficulty parameters.

Canonical values live in DEFAULT_LEVEL_CONFIG (also the seed for migration
0006 and the reference for mobile's bundled fallback). Served boards resolve
through get_level_params(): DB row wins, DEFAULT wins when no row exists, so
board generation never breaks on an unseeded database.
"""
from typing import Any, Dict
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.all_models import GameLevelConfig


# Canonical difficulty grids. match_it pairs mirror the client spec
# (L1 2x2, L2 4x2, L3 4x3); routine steps 3/4/6. Icons stay on at every
# level (accessibility aid — hard mode removes hints, not icons);
# target_seconds feed the slow-completion rules on both sides.
DEFAULT_LEVEL_CONFIG: Dict[str, Dict[int, Dict[str, Any]]] = {
    "match_it": {
        1: {"pairs": 2, "grid": "2x2", "target_seconds": 90},
        2: {"pairs": 4, "grid": "4x2", "target_seconds": 150},
        3: {"pairs": 6, "grid": "4x3", "target_seconds": 240},
    },
    "routine_sequencing": {
        1: {"steps": 3, "hints": True, "icons": True, "target_seconds": 45},
        2: {"steps": 4, "hints": True, "icons": True, "target_seconds": 70},
        3: {"steps": 6, "hints": False, "icons": True, "target_seconds": 120},
    },
    "number_recall": {
        1: {"sequence_length": 3, "show_seconds_per_item": 2, "target_seconds": 60},
        2: {"sequence_length": 4, "show_seconds_per_item": 2, "target_seconds": 90},
        3: {"sequence_length": 6, "show_seconds_per_item": 2, "target_seconds": 150},
    },
    "odd_one_out": {
        1: {"items": 3, "target_seconds": 45},
        2: {"items": 4, "target_seconds": 70},
        3: {"items": 6, "target_seconds": 120},
    },
}


def default_params(game_type: str, level: int) -> Dict[str, Any]:
    """Canonical params for (game, level); empty dict when unknown."""
    return dict(DEFAULT_LEVEL_CONFIG.get(game_type, {}).get(level, {}))


async def get_level_params(
    db: AsyncSession, game_type: str, level: int
) -> Dict[str, Any]:
    """Resolve params for (game, level): DB row wins, DEFAULT on miss."""
    res = await db.execute(
        select(GameLevelConfig).where(
            GameLevelConfig.game_type == game_type,
            GameLevelConfig.level == level,
        )
    )
    row = res.scalar_one_or_none()
    if row and isinstance(row.params, dict):
        merged = default_params(game_type, level)
        merged.update(row.params)
        return merged
    return default_params(game_type, level)


async def get_all_level_config(db: AsyncSession) -> Dict[str, Dict[str, Dict[str, Any]]]:
    """Full map for mobile sync: {game: {level: params}} (levels as strings)."""
    out: Dict[str, Dict[str, Dict[str, Any]]] = {
        game: {str(lvl): dict(p) for lvl, p in levels.items()}
        for game, levels in DEFAULT_LEVEL_CONFIG.items()
    }
    res = await db.execute(select(GameLevelConfig))
    for row in res.scalars().all():
        if row.game_type not in out:
            out[row.game_type] = {}
        base = dict(DEFAULT_LEVEL_CONFIG.get(row.game_type, {}).get(row.level, {}))
        if isinstance(row.params, dict):
            base.update(row.params)
        out[row.game_type][str(row.level)] = base
    return out

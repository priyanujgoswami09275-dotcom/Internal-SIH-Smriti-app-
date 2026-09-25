"""Odd-One-Out game: spot the item from a different semantic group.

The board holds majority members of one qualifying curated group plus one
member of a disjoint group. Groups use verbatim item IDs from
content_packs.py (never geographic category-as-semantics). Counts resolve
from game_level_config — no divergent difficulty map. Sessions log through
the shared game pipeline; the server holds the answer in board_snapshot.

Action types (Task 2 will wire the route registry):
  - select_odd_item: {selected_item_id} with is_correct + response_time_ms.
"""
import random
from typing import Any, Dict, List, Optional

from app.services.content_packs import NER_CONTENT_PACKS
from app.services.level_config_service import default_params

ODD_ONE_OUT_ACTION_TYPES = ("select_odd_item",)

# Curated taxonomy (R0 Option A): disjoint ID sets from content_packs.py.
ODD_ONE_OUT_GROUPS: Dict[str, List[str]] = {
    "festivals": [
        "bihu", "hornbill", "chapchar_kut", "nongkrem", "losar",
        "sangken", "wangala", "moatsu", "dree", "ningol_chakouba",
    ],
    "edible_fruit": ["kaji_nemu", "ou_tenga", "jolpai", "starfruit"],
    "attire": ["mekhela_sador", "puan", "naga_shawl", "gamosa"],
    "instruments": ["dhol", "pepa"],
    "animals": ["rhino", "red_panda"],
}

ODD_ONE_OUT_GROUP_LABELS: Dict[str, str] = {
    "festivals": "Festivals",
    "edible_fruit": "Edible fruit",
    "attire": "Traditional attire",
    "instruments": "Musical instruments",
    "animals": "Animals",
}

# ID -> English name from the registered content packs.
_ID_TO_NAME: Dict[str, str] = {}
for _pack in NER_CONTENT_PACKS.values():
    for _item in _pack.items:
        _ID_TO_NAME.setdefault(_item.id, _item.name_en)


def odd_one_out_config(difficulty_level: int) -> Dict[str, Any]:
    """Resolve (items, target_seconds) from level config."""
    cfg = default_params("odd_one_out", difficulty_level)
    return {
        "items": cfg.get("items", 3),
        "target_seconds": cfg.get("target_seconds", 45),
    }


def _qualifying_groups(item_count: int) -> List[str]:
    """Groups with enough distinct members to fill a majority (items - 1)."""
    need = item_count - 1
    return [
        key for key, members in ODD_ONE_OUT_GROUPS.items()
        if len(members) >= need
    ]


def generate_odd_one_out_board(
    difficulty_level: int = 1,
    items: Optional[int] = None,
    rng: Optional[random.Random] = None,
) -> Dict[str, Any]:
    """Generate a board: majority of one qualifying group + one disjoint odd.

    Count resolves from game_level_config when omitted (routes pass the
    DB-resolved value). Shuffle is seeded via ``rng`` (random.Random
    compatible) for reproducibility.
    """
    cfg = odd_one_out_config(difficulty_level)
    item_count = items if items is not None else cfg["items"]
    target_seconds = cfg["target_seconds"]
    dice = rng or random

    qualifying = _qualifying_groups(item_count)
    if not qualifying:
        raise ValueError(f"No qualifying group for item_count={item_count}")
    majority_key = dice.choice(sorted(qualifying))
    majority_ids = dice.sample(ODD_ONE_OUT_GROUPS[majority_key], item_count - 1)

    odd_choices = [k for k in ODD_ONE_OUT_GROUPS if k != majority_key]
    odd_key = dice.choice(sorted(odd_choices))
    odd_id = dice.choice(ODD_ONE_OUT_GROUPS[odd_key])

    board_ids = list(majority_ids) + [odd_id]
    dice.shuffle(board_ids)

    board_items = [
        {"item_id": item_id, "name": _ID_TO_NAME.get(item_id, item_id)}
        for item_id in board_ids
    ]
    majority_label = ODD_ONE_OUT_GROUP_LABELS[majority_key]
    odd_label = ODD_ONE_OUT_GROUP_LABELS[odd_key]
    odd_name = _ID_TO_NAME.get(odd_id, odd_id)
    return {
        "game_type": "odd_one_out",
        "difficulty_level": difficulty_level,
        "items": board_items,
        "answer_item_id": odd_id,
        "item_count": len(board_items),
        "target_seconds": target_seconds,
        "group_label": majority_label,
        "explanation": (
            f"{len(majority_ids)} are {majority_label}; "
            f"{odd_name} is {odd_label}."
        ),
    }


def public_odd_one_out_board(board: Dict[str, Any]) -> Dict[str, Any]:
    return {
        key: value
        for key, value in board.items()
        if key not in {"answer_item_id", "explanation"}
    }


def odd_one_out_server_state(board: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "answer_item_id": board["answer_item_id"],
        "explanation": board["explanation"],
    }


def odd_one_out_explanation(server_state: Optional[Dict[str, Any]]) -> Optional[str]:
    if not isinstance(server_state, dict):
        return None
    explanation = server_state.get("explanation")
    return explanation if isinstance(explanation, str) and explanation else None


def score_odd_one_out(
    selected_item_id: str, answer_item_id: str
) -> Dict[str, Any]:
    """Score a selection against the server-held answer."""
    correct = selected_item_id == answer_item_id
    return {
        "correct": correct,
        "error_category": "semantic_category",
        "opportunity": {
            "retry": not correct,
            "message": (
                "Correct identification."
                if correct
                else "Review the shared category and try again."
            ),
        },
    }

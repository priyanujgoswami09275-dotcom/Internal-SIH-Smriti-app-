"""Odd-One-Out tests: generator, scorer, config-driven counts.

Counts resolve from game_level_config (3/4/6 items); a DB override must
drive served boards (routes pass DB-resolved values explicitly).
Boards hold majority members of one qualifying semantic group plus one
member of a disjoint group; the server-held answer is the odd item.
"""
import random

import pytest

from app.models.all_models import GameLevelConfig, GameTypeEnum
from app.services import odd_one_out_service


def test_enum_value_exists_and_exactly_four_values():
    assert GameTypeEnum("odd_one_out") is GameTypeEnum.ODD_ONE_OUT
    assert len(list(GameTypeEnum)) == 4
    assert {g.value for g in GameTypeEnum} == {
        "match_it", "routine_sequencing", "number_recall", "odd_one_out",
    }


def test_generator_counts_per_level():
    for level, expected_items, expected_seconds in (
        (1, 3, 45), (2, 4, 70), (3, 6, 120),
    ):
        board = odd_one_out_service.generate_odd_one_out_board(
            level, rng=random.Random(0),
        )
        assert board["game_type"] == "odd_one_out"
        assert board["difficulty_level"] == level
        assert board["item_count"] == expected_items
        assert len(board["items"]) == expected_items
        assert board["target_seconds"] == expected_seconds
        assert board["answer_item_id"] in [i["item_id"] for i in board["items"]]
        assert isinstance(board["group_label"], str) and board["group_label"]
        assert isinstance(board["explanation"], str) and board["explanation"]


def test_generator_deterministic_same_seed():
    first = odd_one_out_service.generate_odd_one_out_board(2, rng=random.Random(42))
    second = odd_one_out_service.generate_odd_one_out_board(2, rng=random.Random(42))
    assert first == second


def test_generator_exactly_one_answer_no_dups_disjoint():
    groups = odd_one_out_service.ODD_ONE_OUT_GROUPS
    id_to_group = {}
    for group_key, members in groups.items():
        for member in members:
            id_to_group[member] = group_key
    for level in (1, 2, 3):
        for seed in range(50):
            board = odd_one_out_service.generate_odd_one_out_board(
                level, rng=random.Random(seed),
            )
            ids = [i["item_id"] for i in board["items"]]
            # No duplicated IDs.
            assert len(set(ids)) == len(ids)
            # Exactly one answer.
            assert ids.count(board["answer_item_id"]) == 1
            # Answer is disjoint from the majority group.
            majority_ids = [i for i in ids if i != board["answer_item_id"]]
            majority_groups = {id_to_group[i] for i in majority_ids}
            assert len(majority_groups) == 1
            assert id_to_group[board["answer_item_id"]] not in majority_groups
            # Names resolve from content_packs items.
            for entry in board["items"]:
                assert isinstance(entry["name"], str) and entry["name"]


def test_scorer_correct_incorrect_shape():
    good = odd_one_out_service.score_odd_one_out("dhol", "dhol")
    assert good["correct"] is True
    assert good["error_category"] == "semantic_category"
    assert isinstance(good["opportunity"], dict)

    bad = odd_one_out_service.score_odd_one_out("bihu", "dhol")
    assert bad["correct"] is False
    assert bad["error_category"] == "semantic_category"
    assert isinstance(bad["opportunity"], dict)


def test_action_registry_documents_pipeline_type():
    assert odd_one_out_service.ODD_ONE_OUT_ACTION_TYPES == ("select_odd_item",)


@pytest.mark.asyncio
async def test_db_override_drives_items(db_session):
    db_session.add(GameLevelConfig(
        game_type="odd_one_out", level=1,
        params={"items": 5, "target_seconds": 45},
    ))
    await db_session.commit()
    from app.services.level_config_service import get_level_params
    params = await get_level_params(db_session, "odd_one_out", 1)
    assert params["items"] == 5
    board = odd_one_out_service.generate_odd_one_out_board(
        1, items=params["items"], rng=random.Random(7),
    )
    assert len(board["items"]) == 5
    assert board["item_count"] == 5

"""Phase 4 number-recall tests: generator, scorer, config-driven lengths, endpoint.

Lengths resolve from game_level_config (3/4/6); a DB override must drive
served boards; sessions log through the shared pipeline so dashboard
trends ingest the game with no per-game code.
"""
import uuid

import pytest

from app.models.all_models import GameLevelConfig, GameTypeEnum
from app.services import recall_service


def test_enum_value_exists():
    assert GameTypeEnum("number_recall") is GameTypeEnum.NUMBER_RECALL


def test_generator_lengths_per_level():
    for level, expected in ((1, 3), (2, 4), (3, 6)):
        board = recall_service.generate_number_recall_board(level)
        assert board["game_type"] == "number_recall"
        assert board["sequence_length"] == expected
        assert len(board["sequence"]) == expected
        assert board["show_seconds_per_item"] == 2
        # Fair sequences: digits 0-9, unique within a board.
        assert all(0 <= d <= 9 for d in board["sequence"])
        assert len(set(board["sequence"])) == expected


def test_generator_is_random():
    first = recall_service.generate_number_recall_board(3)["sequence"]
    for _ in range(10):
        if recall_service.generate_number_recall_board(3)["sequence"] != first:
            return
    pytest.fail("generator produced the same L3 sequence 11 times")


def test_scorer_perfect_partial_empty():
    perfect = recall_service.score_number_recall([4, 1, 7], [4, 1, 7])
    assert perfect["is_perfect"] is True
    assert perfect["accuracy_pct"] == 100.0
    assert perfect["correct_count"] == 3

    partial = recall_service.score_number_recall([4, 9, 7], [4, 1, 7])
    assert partial["is_perfect"] is False
    assert partial["accuracy_pct"] == pytest.approx(66.7, abs=0.1)
    assert partial["correct_count"] == 2
    assert partial["errors"] == [{"position": 1, "expected": 1, "got": 9}]

    short = recall_service.score_number_recall([4], [4, 1, 7])
    assert short["correct_count"] == 1
    assert len(short["errors"]) == 2

    empty = recall_service.score_number_recall([], [4, 1, 7])
    assert empty["is_perfect"] is False
    assert empty["accuracy_pct"] == 0.0


def test_action_registry_documents_pipeline_types():
    assert set(recall_service.RECALL_ACTION_TYPES) == {"show_sequence", "recall_tap"}


@pytest.mark.asyncio
async def test_db_override_drives_length(db_session):
    db_session.add(GameLevelConfig(
        game_type="number_recall", level=1,
        params={"sequence_length": 5, "show_seconds_per_item": 3, "target_seconds": 60},
    ))
    await db_session.commit()
    from app.services.level_config_service import get_level_params
    params = await get_level_params(db_session, "number_recall", 1)
    assert params["sequence_length"] == 5
    board = recall_service.generate_number_recall_board(
        1, sequence_length=params["sequence_length"],
        show_seconds_per_item=params["show_seconds_per_item"],
    )
    assert len(board["sequence"]) == 5
    assert board["show_seconds_per_item"] == 3


AUTH = "/api/v1/auth"
GAMES = "/api/v1/games"


@pytest.mark.asyncio
async def test_recall_board_endpoint_and_session_flow(client):
    phone = f"+91{uuid.uuid4().int % 10**9:09d}"
    resp = await client.post(
        f"{AUTH}/register",
        json={"phone": phone, "password": "TestPass123", "role": "patient",
              "preferred_language": "english"},
    )
    assert resp.status_code == 201, resp.text
    resp = await client.post(f"{AUTH}/login", json={"phone": phone, "password": "TestPass123"})
    headers = {"Authorization": f"Bearer {resp.json()['access_token']}"}
    resp = await client.post(
        "/api/v1/patients",
        json={"name": "Recall Tester", "cognitive_baseline": "healthy",
              "region": "Assam", "district": "Kamrup"},
        headers=headers,
    )
    assert resp.status_code == 201, resp.text
    patient_id = resp.json()["id"]
    resp = await client.post(
        "/api/v1/compliance/consent",
        json={"patient_id": patient_id, "consent_type": "patient_self", "scope": "all"},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text

    # Full shared pipeline: start → fetch bound board → tap actions → complete.
    resp = await client.post(
        f"{GAMES}/sessions",
        json={"game_type": "number_recall", "difficulty_level": 2},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    session_id = resp.json()["session_id"]
    resp = await client.get(
        f"{GAMES}/recall/board",
        params={"difficulty_level": 2, "session_id": session_id},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    board = resp.json()
    assert board["sequence_length"] == 4
    assert len(board["sequence"]) == 4
    for pos, digit in enumerate(board["sequence"]):
        resp = await client.post(
            f"{GAMES}/sessions/{session_id}/actions",
            json={"action_type": "recall_tap",
                  "action_data": {"position": pos, "digit": digit, "expected": digit},
                  "is_correct": True, "response_time_ms": 1200},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
    resp = await client.post(f"{GAMES}/sessions/{session_id}/complete", headers=headers)
    assert resp.status_code == 200, resp.text
    summary = resp.json()
    assert summary["game_type"] == "number_recall"
    assert summary["accuracy_pct"] == 100.0
    assert summary["total_attempts"] == 4

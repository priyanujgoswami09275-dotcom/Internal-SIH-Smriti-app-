"""Phase 2 difficulty-matrix tests: game_level_config is the source of truth.

Boards served for every (game, level) must match the config source, a DB
override must drive served boards, and routine L3 items must carry icons
(icons-always decision: accessibility aid, hard mode removes hints only).
"""
import uuid

import pytest

from app.models.all_models import GameLevelConfig
from app.services import content_packs, routine_service
from app.services import odd_one_out_service
from app.services.level_config_service import (
    DEFAULT_LEVEL_CONFIG,
    get_all_level_config,
    get_level_params,
)

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
GAMES = "/api/v1/games"


async def _auth(client):
    phone = f"+91{uuid.uuid4().int % 10**9:09d}"
    resp = await client.post(
        f"{AUTH}/register",
        json={"phone": phone, "password": "TestPass123", "role": "patient",
              "preferred_language": "english"},
    )
    assert resp.status_code == 201, resp.text
    resp = await client.post(f"{AUTH}/login", json={"phone": phone, "password": "TestPass123"})
    assert resp.status_code == 200, resp.text
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


@pytest.mark.asyncio
async def test_match_it_matrix_matches_canonical(db_session):
    """Unseeded DB: served-equivalent boards equal DEFAULT (2/4/6 pairs)."""
    for level, expected_pairs in ((1, 2), (2, 4), (3, 6)):
        params = await get_level_params(db_session, "match_it", level)
        assert params["pairs"] == expected_pairs
        board = content_packs.generate_match_it_board(
            "festivals_ner", level, pair_count=params["pairs"]
        )
        assert board["pair_count"] == expected_pairs
        assert board["total_cards"] == expected_pairs * 2


@pytest.mark.asyncio
async def test_routine_matrix_matches_canonical_with_icons(db_session):
    """Unseeded DB: 3/4/6 steps, hints flag off only at L3, icons everywhere."""
    for level, expected_steps in ((1, 3), (2, 4), (3, 6)):
        params = await get_level_params(db_session, "routine_sequencing", level)
        assert params["steps"] == expected_steps
        assert params["icons"] is True
        board = routine_service.generate_routine_sequencing_board(
            routine_service.DEFAULT_DAILY_ROUTINE,
            level,
            step_count=params["steps"],
            include_icons=params["icons"],
            include_hints=params["hints"],
        )
        assert board["step_count"] == expected_steps
        assert board["has_icons"] is True
        assert board["has_hints"] is (level <= 2)
        # The Phase 2 fix: every item carries an icon at every level.
        assert all(item["icon"] for item in board["shuffled_items"])


@pytest.mark.asyncio
async def test_db_override_drives_boards(db_session):
    """A config row beats DEFAULT — proving the table is the source of truth."""
    db_session.add(GameLevelConfig(
        game_type="match_it", level=2,
        params={"pairs": 5, "grid": "custom", "target_seconds": 150},
    ))
    await db_session.commit()
    params = await get_level_params(db_session, "match_it", 2)
    assert params["pairs"] == 5
    board = content_packs.generate_match_it_board(
        "festivals_ner", 2, pair_count=params["pairs"]
    )
    assert board["pair_count"] == 5
    full = await get_all_level_config(db_session)
    assert full["match_it"]["2"]["pairs"] == 5
    # Untouched levels still resolve to canonical.
    assert full["match_it"]["1"] == DEFAULT_LEVEL_CONFIG["match_it"][1]


@pytest.mark.asyncio
async def test_level_config_endpoint(client, db_session):
    """GET /games/level-config serves the full map for mobile sync."""
    headers = await _auth(client)
    resp = await client.get(f"{GAMES}/level-config", headers=headers)
    assert resp.status_code == 200, resp.text
    config = resp.json()["config"]
    assert config["match_it"]["1"]["pairs"] == 2
    assert config["match_it"]["3"]["pairs"] == 6
    assert config["routine_sequencing"]["2"]["steps"] == 4
    assert config["routine_sequencing"]["3"]["icons"] is True
    assert config["odd_one_out"]["1"] == {"items": 3, "target_seconds": 45}
    assert config["odd_one_out"]["2"] == {"items": 4, "target_seconds": 70}
    assert config["odd_one_out"]["3"] == {"items": 6, "target_seconds": 120}


@pytest.mark.asyncio
async def test_odd_one_out_matrix_matches_canonical(db_session):
    """Unseeded DB: 3/4/6 items with 45/70/120s targets, served via service."""
    import random

    for level, expected_items, expected_seconds in (
        (1, 3, 45), (2, 4, 70), (3, 6, 120),
    ):
        params = await get_level_params(db_session, "odd_one_out", level)
        assert params["items"] == expected_items
        assert params["target_seconds"] == expected_seconds
        board = odd_one_out_service.generate_odd_one_out_board(
            level, items=params["items"], rng=random.Random(11))
        assert board["item_count"] == expected_items
        assert board["target_seconds"] == expected_seconds
        assert board["answer_item_id"] in [i["item_id"] for i in board["items"]]


@pytest.mark.asyncio
async def test_served_odd_board_follows_config_endpoints(client):
    """Served odd-one-out boards agree with the canonical counts per level."""
    import uuid as uuid_lib

    from app.models.all_models import GameSession

    headers = await _auth(client)
    resp = await client.post(
        PATIENTS,
        json={"name": "Odd Matrix", "cognitive_baseline": "healthy",
              "region": "Assam", "district": "Kamrup"},
        headers=headers,
    )
    assert resp.status_code == 201, resp.text
    resp = await client.post(
        "/api/v1/compliance/consent",
        json={"patient_id": resp.json()["id"], "consent_type": "patient_self",
              "scope": "all"},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    for level, items in ((1, 3), (2, 4), (3, 6)):
        resp = await client.post(
            f"{GAMES}/sessions",
            json={"game_type": "odd_one_out", "difficulty_level": level},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        session_id = resp.json()["session_id"]
        resp = await client.get(
            f"{GAMES}/odd-one-out/board",
            params={"session_id": session_id, "difficulty_level": level},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["item_count"] == items
        assert len(body["items"]) == items
        assert "answer_item_id" not in body


@pytest.mark.asyncio
async def test_served_boards_follow_config_endpoints(client):
    """Served board endpoints agree with the canonical grids per level."""
    """Served board endpoints agree with the canonical grids per level."""
    headers = await _auth(client)
    for level, pairs in ((1, 2), (2, 4), (3, 6)):
        resp = await client.get(
            f"{GAMES}/content-packs/festivals_ner/board",
            params={"difficulty_level": level}, headers=headers,
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["pair_count"] == pairs
    # Routine board needs a patient profile for the requesting account.
    resp = await client.post(
        PATIENTS,
        json={"name": "Matrix Check", "cognitive_baseline": "healthy",
              "region": "Assam", "district": "Kamrup"},
        headers=headers,
    )
    assert resp.status_code == 201, resp.text
    patient_id = resp.json()["id"]
    for level, steps in ((1, 3), (2, 4), (3, 6)):
        resp = await client.get(
            f"{GAMES}/routine/board",
            params={"patient_id": patient_id, "difficulty_level": level},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["step_count"] == steps
        assert body["has_icons"] is True

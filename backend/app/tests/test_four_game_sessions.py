"""Slice C-02': Odd-One-Out through the shared session/action/complete pipeline.

Real HTTP via the `client` fixture + `db_session`, mirroring the
test_number_recall.py auth/consent flow (patient register -> profile ->
scope-"all" consent -> sessions). Covers: board 200 with the answer withheld
+ snapshot stored server-side; correct/incorrect selection scored from the
stored answer; tampered client `is_correct` never trusted; NULL-snapshot 422;
unknown action behavior preserved; 4 games x 3 levels session flow; pooled
/patients/{id}/stats contribution per game; one-log-per-decision shadow
fallback (`unsupported`, rules sole authority); repeat complete stability.
"""
import uuid

import pytest
from sqlalchemy import select

from app.models.all_models import (
    DifficultyAdjustmentLog,
    GameSession,
    GameTypeEnum,
)
from app.tests.conftest import provision_staff_user

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
GAMES = "/api/v1/games"
COMPLIANCE = "/api/v1/compliance"

ODD_LEVELS = {1: (3, 45), 2: (4, 70), 3: (6, 120)}
FOUR_GAMES = ("match_it", "routine_sequencing", "number_recall", "odd_one_out")


async def _register_patient(client):
    """Patient account + profile + scope-"all" consent (mirrors recall flow)."""
    phone = f"+91{uuid.uuid4().int % 10**9:09d}"
    resp = await client.post(
        f"{AUTH}/register",
        json={"phone": phone, "password": "TestPass123", "role": "patient",
              "preferred_language": "english"},
    )
    assert resp.status_code == 201, resp.text
    resp = await client.post(
        f"{AUTH}/login", json={"phone": phone, "password": "TestPass123"})
    assert resp.status_code == 200, resp.text
    headers = {"Authorization": f"Bearer {resp.json()['access_token']}"}
    resp = await client.post(
        PATIENTS,
        json={"name": "Odd Tester", "cognitive_baseline": "healthy",
              "region": "Assam", "district": "Kamrup"},
        headers=headers,
    )
    assert resp.status_code == 201, resp.text
    patient_id = resp.json()["id"]
    resp = await client.post(
        f"{COMPLIANCE}/consent",
        json={"patient_id": patient_id, "consent_type": "patient_self",
              "scope": "all"},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    return headers, patient_id, resp.json()["id"]


async def _start_session(client, headers, game_type, level=1):
    resp = await client.post(
        f"{GAMES}/sessions",
        json={"game_type": game_type, "difficulty_level": level},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["session_id"]


async def _snapshot(db_session, session_id):
    return await db_session.get(GameSession, uuid.UUID(session_id))


async def _staff_headers(client):
    staff = await provision_staff_user()
    login = await client.post(
        f"{AUTH}/login",
        json={"phone": staff["phone"], "password": "Passw0rd123"})
    assert login.status_code == 200, login.text
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


@pytest.mark.asyncio
@pytest.mark.parametrize("level", [1, 2, 3])
async def test_odd_board_withholds_answer_and_stores_snapshot(
    client, db_session, level,
):
    headers, _pid, _cid = await _register_patient(client)
    session_id = await _start_session(client, headers, "odd_one_out", level)
    resp = await client.get(
        f"{GAMES}/odd-one-out/board",
        params={"session_id": session_id, "difficulty_level": level},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert set(body) == {
        "game_type", "difficulty_level", "items", "item_count",
        "target_seconds", "group_label",
    }
    expected_items, expected_seconds = ODD_LEVELS[level]
    assert body["game_type"] == "odd_one_out"
    assert body["difficulty_level"] == level
    assert body["item_count"] == expected_items
    assert body["target_seconds"] == expected_seconds
    assert len(body["items"]) == expected_items
    for entry in body["items"]:
        assert {"item_id", "name"} <= set(entry)
    assert isinstance(body["group_label"], str) and body["group_label"]
    assert "answer_item_id" not in body
    assert "explanation" not in body

    stored = await _snapshot(db_session, session_id)
    assert stored.board_snapshot is not None
    assert "answer_item_id" not in stored.board_snapshot
    assert "explanation" not in stored.board_snapshot
    answer = stored.server_state["answer_item_id"]
    assert answer in [i["item_id"] for i in body["items"]]


@pytest.mark.asyncio
async def test_odd_board_rejects_bad_level(client):
    headers, _pid, _cid = await _register_patient(client)
    session_id = await _start_session(client, headers, "odd_one_out", 1)
    resp = await client.get(
        f"{GAMES}/odd-one-out/board",
        params={"session_id": session_id, "difficulty_level": 9},
        headers=headers,
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_odd_board_requires_active_consent(client):
    headers, _pid, consent_id = await _register_patient(client)
    session_id = await _start_session(client, headers, "odd_one_out", 1)
    resp = await client.post(
        f"{COMPLIANCE}/consent/{consent_id}/revoke", headers=headers)
    assert resp.status_code == 200, resp.text
    resp = await client.get(
        f"{GAMES}/odd-one-out/board",
        params={"session_id": session_id, "difficulty_level": 1},
        headers=headers,
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_select_odd_item_scored_from_server_answer(client, db_session):
    headers, _pid, _cid = await _register_patient(client)
    session_id = await _start_session(client, headers, "odd_one_out", 1)
    resp = await client.get(
        f"{GAMES}/odd-one-out/board",
        params={"session_id": session_id, "difficulty_level": 1},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    answer = (await _snapshot(db_session, session_id)).server_state["answer_item_id"]
    wrong = next(
        i["item_id"] for i in resp.json()["items"] if i["item_id"] != answer)

    # Correct selection, no client verdict offered: server scores correct.
    resp = await client.post(
        f"{GAMES}/sessions/{session_id}/actions",
        json={"action_type": "select_odd_item",
              "action_data": {"selected_item_id": answer},
              "response_time_ms": 1100},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["event"]["is_correct"] is True

    # Tampered client verdict (wrong item, is_correct=true) still incorrect.
    resp = await client.post(
        f"{GAMES}/sessions/{session_id}/actions",
        json={"action_type": "select_odd_item",
              "action_data": {"selected_item_id": wrong},
              "is_correct": True, "response_time_ms": 900},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    event = resp.json()["event"]
    assert event["is_correct"] is False
    assert event["error_category"] == "semantic_category"

    # Inverted tamper (right item, is_correct=false) still correct.
    resp = await client.post(
        f"{GAMES}/sessions/{session_id}/actions",
        json={"action_type": "select_odd_item",
              "action_data": {"selected_item_id": answer},
              "is_correct": False, "response_time_ms": 800},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["event"]["is_correct"] is True

    resp = await client.post(
        f"{GAMES}/sessions/{session_id}/complete", headers=headers)
    assert resp.status_code == 200, resp.text
    assert resp.json()["total_attempts"] == 3
    assert resp.json()["accuracy_pct"] == pytest.approx(66.7, abs=0.1)


@pytest.mark.asyncio
async def test_select_without_board_is_422(client):
    headers, _pid, _cid = await _register_patient(client)
    session_id = await _start_session(client, headers, "odd_one_out", 1)
    resp = await client.post(
        f"{GAMES}/sessions/{session_id}/actions",
        json={"action_type": "select_odd_item",
              "action_data": {"selected_item_id": "dhol"},
              "is_correct": True},
        headers=headers,
    )
    assert resp.status_code == 422
    assert resp.json()["detail"] == "no server board for this session; fetch board first"


@pytest.mark.asyncio
async def test_unknown_action_is_informational(client):
    headers, _pid, _cid = await _register_patient(client)
    session_id = await _start_session(client, headers, "match_it", 1)
    resp = await client.post(
        f"{GAMES}/sessions/{session_id}/actions",
        json={"action_type": "mystery_move",
              "action_data": {"anything": 1},
              "is_correct": True, "response_time_ms": 500},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["event"]["is_correct"] is None
    resp = await client.post(
        f"{GAMES}/sessions/{session_id}/complete", headers=headers)
    assert resp.status_code == 200, resp.text
    assert resp.json()["total_attempts"] == 0
    assert resp.json()["accuracy_pct"] == 0.0


@pytest.mark.asyncio
@pytest.mark.parametrize("game_type", list(FOUR_GAMES))
@pytest.mark.parametrize("level", [1, 2, 3])
async def test_four_games_three_levels_session_flow(
    client, db_session, game_type, level,
):
    headers, pid, _cid = await _register_patient(client)
    session_id = await _start_session(client, headers, game_type, level)
    if game_type == "odd_one_out":
        resp = await client.get(
            f"{GAMES}/odd-one-out/board",
            params={"session_id": session_id, "difficulty_level": level},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        answer = (await _snapshot(db_session, session_id)).server_state["answer_item_id"]
        payloads = [{"action_type": "select_odd_item",
                     "action_data": {"selected_item_id": answer},
                     "response_time_ms": 1000}]
    elif game_type == "match_it":
        resp = await client.get(
            f"{GAMES}/content-packs/festivals_ner/board",
            params={"session_id": session_id, "difficulty_level": level},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        cards = resp.json()["cards"]
        first = cards[0]
        second = next(card for card in cards[1:] if card["item_id"] == first["item_id"])
        payloads = [
            {"action_type": "flip_card", "action_data": {"card_id": card["card_id"]},
             "response_time_ms": 1000}
            for card in (first, second)
        ]
    elif game_type == "routine_sequencing":
        resp = await client.get(
            f"{GAMES}/routine/board",
            params={"patient_id": pid, "session_id": session_id,
                    "difficulty_level": level},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        board = resp.json()
        payloads = [
            {"action_type": "place_step",
             "action_data": {"position": position, "step_id": step_id},
             "response_time_ms": 1000}
            for position, step_id in enumerate(board["correct_sequence"])
        ]
    else:
        resp = await client.get(
            f"{GAMES}/recall/board",
            params={"session_id": session_id, "difficulty_level": level},
            headers=headers,
        )
        assert resp.status_code == 200, resp.text
        sequence = resp.json()["sequence"]
        payloads = [
            {"action_type": "recall_tap",
             "action_data": {"position": position, "digit": digit},
             "response_time_ms": 1000}
            for position, digit in enumerate(sequence)
        ]
    for payload in payloads:
        resp = await client.post(
            f"{GAMES}/sessions/{session_id}/actions", json=payload, headers=headers)
        assert resp.status_code == 200, resp.text
    resp = await client.post(
        f"{GAMES}/sessions/{session_id}/complete", headers=headers)
    assert resp.status_code == 200, resp.text
    summary = resp.json()
    assert summary["game_type"] == game_type
    assert summary["difficulty_level"] == level
    assert summary["accuracy_pct"] == 100.0
    assert summary["total_attempts"] >= 1


@pytest.mark.asyncio
async def test_pooled_stats_contribution_proven_per_game(client, db_session):
    headers, pid, _cid = await _register_patient(client)

    async def _correct_session(game_type):
        sid = await _start_session(client, headers, game_type, 1)
        if game_type == "match_it":
            resp = await client.get(
                f"{GAMES}/content-packs/festivals_ner/board",
                params={"session_id": sid, "difficulty_level": 1},
                headers=headers,
            )
            assert resp.status_code == 200, resp.text
            cards = resp.json()["cards"]
            first = cards[0]
            second = next(card for card in cards[1:] if card["item_id"] == first["item_id"])
            payloads = [
                {"action_type": "flip_card", "action_data": {"card_id": card["card_id"]}}
                for card in (first, second)
            ]
        elif game_type == "routine_sequencing":
            resp = await client.get(
                f"{GAMES}/routine/board",
                params={"patient_id": pid, "session_id": sid, "difficulty_level": 1},
                headers=headers,
            )
            assert resp.status_code == 200, resp.text
            sequence = resp.json()["correct_sequence"]
            payloads = [
                {"action_type": "place_step",
                 "action_data": {"position": position, "step_id": step_id}}
                for position, step_id in enumerate(sequence)
            ]
        else:
            resp = await client.get(
                f"{GAMES}/recall/board",
                params={"session_id": sid, "difficulty_level": 1},
                headers=headers,
            )
            assert resp.status_code == 200, resp.text
            sequence = resp.json()["sequence"]
            payloads = [
                {"action_type": "recall_tap",
                 "action_data": {"position": position, "digit": digit}}
                for position, digit in enumerate(sequence)
            ]
        assert resp.status_code == 200, resp.text
        for payload in payloads:
            resp = await client.post(
                f"{GAMES}/sessions/{sid}/actions",
                json={**payload, "response_time_ms": 1000},
                headers=headers)
            assert resp.status_code == 200, resp.text
        resp = await client.post(
            f"{GAMES}/sessions/{sid}/complete", headers=headers)
        assert resp.status_code == 200, resp.text
        return sid

    await _correct_session("match_it")
    await _correct_session("routine_sequencing")
    await _correct_session("number_recall")
    # Odd-One-Out contributes the single imperfect fixture: 0/1.
    odd_sid = await _start_session(client, headers, "odd_one_out", 1)
    resp = await client.get(
        f"{GAMES}/odd-one-out/board",
        params={"session_id": odd_sid, "difficulty_level": 1}, headers=headers)
    assert resp.status_code == 200, resp.text
    answer = (await _snapshot(db_session, odd_sid)).server_state["answer_item_id"]
    wrong = next(
        i["item_id"] for i in resp.json()["items"] if i["item_id"] != answer)
    resp = await client.post(
        f"{GAMES}/sessions/{odd_sid}/actions",
        json={"action_type": "select_odd_item",
              "action_data": {"selected_item_id": wrong},
              "is_correct": True, "response_time_ms": 1000},
        headers=headers)
    assert resp.status_code == 200, resp.text
    resp = await client.post(
        f"{GAMES}/sessions/{odd_sid}/complete", headers=headers)
    assert resp.status_code == 200, resp.text

    staff = await _staff_headers(client)
    resp = await client.get(
        f"{GAMES}/patients/{pid}/stats", params={"days": 14}, headers=staff)
    assert resp.status_code == 200, resp.text
    assert resp.json()["overall"]["sessions"] == 4
    assert resp.json()["overall"]["accuracy_pct"] == pytest.approx(87.5)

    # Removing one game's fixture moves the pooled aggregate: proof per game.
    odd_row = await db_session.get(GameSession, uuid.UUID(odd_sid))
    await db_session.delete(odd_row)
    await db_session.commit()
    resp = await client.get(
        f"{GAMES}/patients/{pid}/stats", params={"days": 14}, headers=staff)
    assert resp.status_code == 200, resp.text
    assert resp.json()["overall"]["sessions"] == 3
    assert resp.json()["overall"]["accuracy_pct"] == 100.0


@pytest.mark.asyncio
async def test_odd_shadow_fallback_rules_authority_and_single_log(
    client, db_session,
):
    _headers, pid, _cid = await _register_patient(client)
    staff = await _staff_headers(client)
    resp = await client.post(
        f"{GAMES}/difficulty/evaluate",
        params={"patient_id": pid, "game_type": "odd_one_out",
                "current_difficulty": 1},
        headers=staff,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["source"] == "rule_fallback"
    assert "unsupported" in body["shadow_reason"]
    assert body["shadow_probability"] is None  # no fabricated learned support

    logs = (await db_session.execute(
        select(DifficultyAdjustmentLog).where(
            DifficultyAdjustmentLog.patient_id == uuid.UUID(pid),
            DifficultyAdjustmentLog.game_type == GameTypeEnum.ODD_ONE_OUT,
        )
    )).scalars().all()
    assert len(logs) == 1  # one log per decision
    assert logs[0].source == "rule_fallback"


@pytest.mark.asyncio
async def test_repeat_complete_stable(client, db_session):
    headers, _pid, _cid = await _register_patient(client)
    session_id = await _start_session(client, headers, "odd_one_out", 1)
    resp = await client.get(
        f"{GAMES}/odd-one-out/board",
        params={"session_id": session_id, "difficulty_level": 1},
        headers=headers,
    )
    answer = (await _snapshot(db_session, session_id)).server_state["answer_item_id"]
    resp = await client.post(
        f"{GAMES}/sessions/{session_id}/actions",
        json={"action_type": "select_odd_item",
              "action_data": {"selected_item_id": answer},
              "response_time_ms": 700},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    first = (await client.post(
        f"{GAMES}/sessions/{session_id}/complete", headers=headers)).json()
    second = (await client.post(
        f"{GAMES}/sessions/{session_id}/complete", headers=headers)).json()
    # completed_at refreshes; every scored field must be identical (stable).
    assert {k: v for k, v in second.items() if k != "completed_at"} == {
        k: v for k, v in first.items() if k != "completed_at"}
    assert first["accuracy_pct"] == 100.0
    assert first["total_attempts"] == 1
    stored = await _snapshot(db_session, session_id)
    assert (stored.attempts, stored.correct_count, stored.incorrect_count) == (1, 1, 0)
    assert stored.server_state["answer_item_id"] == answer

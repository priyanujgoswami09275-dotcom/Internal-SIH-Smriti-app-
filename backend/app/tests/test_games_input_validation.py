"""Wave 1 Batch A: input-validation 500s -> 4xx (games routes).

Covers brief-wave-1a exact behaviors:
- unknown game_type on start/history/evaluate -> 422 naming the bad value
- malformed session UUID on actions/complete/get -> 422, never 500
- unknown well-formed session UUID on actions/complete/get -> 404
- unfinished session in history serializes null accuracy (200, not 500)
"""
import uuid

import pytest

from app.tests.conftest import provision_staff_user

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
GAMES = "/api/v1/games"
COMPLIANCE = "/api/v1/compliance"


async def _register_patient(client):
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
        json={"name": "Validation Tester", "cognitive_baseline": "healthy",
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
    return headers, patient_id


async def _staff_headers(client):
    staff = await provision_staff_user()
    login = await client.post(
        f"{AUTH}/login",
        json={"phone": staff["phone"], "password": "Passw0rd123"})
    assert login.status_code == 200, login.text
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


@pytest.mark.asyncio
async def test_start_game_unknown_game_type_422(client):
    headers, _pid = await _register_patient(client)
    resp = await client.post(
        f"{GAMES}/sessions",
        json={"game_type": "chess", "difficulty_level": 1},
        headers=headers,
    )
    assert resp.status_code == 422, resp.text
    assert "chess" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_history_unknown_game_type_422(client):
    headers, pid = await _register_patient(client)
    staff = await _staff_headers(client)
    resp = await client.get(
        f"{GAMES}/patients/{pid}/history",
        params={"game_type": "bogus"},
        headers=staff,
    )
    assert resp.status_code == 422, resp.text
    assert "bogus" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_evaluate_unknown_game_type_422(client):
    _headers, pid = await _register_patient(client)
    staff = await _staff_headers(client)
    resp = await client.post(
        f"{GAMES}/difficulty/evaluate",
        params={"patient_id": pid, "game_type": "bogus",
                "current_difficulty": 1},
        headers=staff,
    )
    assert resp.status_code == 422, resp.text
    assert "bogus" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_actions_malformed_uuid_422(client):
    headers, _pid = await _register_patient(client)
    resp = await client.post(
        f"{GAMES}/sessions/not-a-uuid/actions",
        json={"action_type": "flip_card",
              "action_data": {"card_id": 1, "item_id": "bihu"}},
        headers=headers,
    )
    assert resp.status_code == 422, resp.text


@pytest.mark.asyncio
async def test_complete_malformed_uuid_422(client):
    headers, _pid = await _register_patient(client)
    resp = await client.post(
        f"{GAMES}/sessions/not-a-uuid/complete", headers=headers)
    assert resp.status_code == 422, resp.text


@pytest.mark.asyncio
async def test_get_session_malformed_uuid_422(client):
    headers, _pid = await _register_patient(client)
    resp = await client.get(
        f"{GAMES}/sessions/not-a-uuid", headers=headers)
    assert resp.status_code == 422, resp.text


@pytest.mark.asyncio
async def test_actions_unknown_uuid_404(client):
    headers, _pid = await _register_patient(client)
    resp = await client.post(
        f"{GAMES}/sessions/{uuid.uuid4()}/actions",
        json={"action_type": "flip_card",
              "action_data": {"card_id": 1, "item_id": "bihu"}},
        headers=headers,
    )
    assert resp.status_code == 404, resp.text
    assert "Game session not found" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_complete_unknown_uuid_404(client):
    headers, _pid = await _register_patient(client)
    resp = await client.post(
        f"{GAMES}/sessions/{uuid.uuid4()}/complete", headers=headers)
    assert resp.status_code == 404, resp.text
    assert "Game session not found" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_get_session_unknown_uuid_404(client):
    headers, _pid = await _register_patient(client)
    resp = await client.get(
        f"{GAMES}/sessions/{uuid.uuid4()}", headers=headers)
    assert resp.status_code == 404, resp.text
    assert "Game session not found" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_history_unfinished_session_null_accuracy_200(client):
    headers, pid = await _register_patient(client)
    resp = await client.post(
        f"{GAMES}/sessions",
        json={"game_type": "match_it", "difficulty_level": 1},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    staff = await _staff_headers(client)
    resp = await client.get(
        f"{GAMES}/patients/{pid}/history", headers=staff)
    assert resp.status_code == 200, resp.text
    items = resp.json()
    assert len(items) == 1
    assert items[0]["accuracy_pct"] is None
    assert items[0]["avg_response_time_ms"] is None

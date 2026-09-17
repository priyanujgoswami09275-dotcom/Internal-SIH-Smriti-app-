"""API route tests — auth refresh, patient profiles + caregiver links, sync, games flow.

These exercise the FastAPI app end-to-end through the ASGI client fixture in
conftest.py (in-memory SQLite, get_db overridden).
"""
import uuid

import pytest

from app.models.user import RoleEnum

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
GAMES = "/api/v1/games"
SYNC = "/api/v1/sync"


@pytest.mark.parametrize("role, allowed", [
    ("patient", True),
    ("family_caregiver", True),
    ("asha_worker", False),
    ("clinician", False),
    ("admin", False),
    ("unknown", False),
    ("", False),
    (None, False),
    ("PATIENT", False),
])
def test_public_registration_policy(role, allowed):
    from app.routes import auth

    assert auth.is_public_registration_role(role) is allowed


@pytest.mark.parametrize("role", ["patient", "family_caregiver"])
async def test_public_signup(client, role):
    phone = f"+91{uuid.uuid4().int % 10**10}"
    user = await _register(client, phone, role)
    assert user["role"] == role
    headers, _ = await _login(client, phone)
    me = await client.get(f"{AUTH}/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["id"] == user["id"]
    assert me.json()["role"] == role


@pytest.mark.parametrize("role", list(RoleEnum))
async def test_trusted_staff_provisioning_and_login(client, role):
    from app.tests.conftest import provision_staff_user

    if role in (RoleEnum.PATIENT, RoleEnum.FAMILY_CAREGIVER):
        with pytest.raises(ValueError):
            await provision_staff_user(role=role)
        return
    user = await provision_staff_user(role=role)
    headers, _ = await _login(client, user["phone"], password="Passw0rd123")
    me = await client.get(f"{AUTH}/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["id"] == user["id"]
    assert me.json()["role"] == role.value


async def test_staff_provisioning_requires_isolated_fixture():
    from app.tests.conftest import provision_staff_user

    with pytest.raises(RuntimeError, match="isolated client fixture"):
        await provision_staff_user()


async def _register(client, phone, role="patient"):
    resp = await client.post(
        f"{AUTH}/register",
        json={"phone": phone, "password": "TestPass123", "role": role, "preferred_language": "english"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _login(client, phone, password="TestPass123"):
    resp = await client.post(f"{AUTH}/login", json={"phone": phone, "password": password})
    assert resp.status_code == 200, resp.text
    data = resp.json()
    return {"Authorization": f"Bearer {data['access_token']}"}, data


async def _create_patient(client, headers, name, user_id=None):
    body = {"name": name, "cognitive_baseline": "healthy", "region": "Assam", "district": "Kamrup"}
    if user_id is not None:
        body["user_id"] = str(user_id)
    resp = await client.post(PATIENTS, json=body, headers=headers)
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_auth_refresh_flow(client):
    phone = f"+91{uuid.uuid4().int % 10**9:09d}"
    await _register(client, phone)
    _, tokens = await _login(client, phone)

    # /auth/refresh exchanges a refresh token for a new pair
    resp = await client.post(f"{AUTH}/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert resp.status_code == 200, resp.text
    assert "access_token" in resp.json()
    assert "refresh_token" in resp.json()

    # Invalid refresh token rejected
    resp = await client.post(f"{AUTH}/refresh", json={"refresh_token": "garbage.token.here"})
    assert resp.status_code == 401

    # /auth/logout is a stateless ack for an authenticated user
    resp = await client.post(f"{AUTH}/logout", headers={"Authorization": f"Bearer {tokens['access_token']}"})
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_game_session_flow_now_works(client):
    """Regression: games routes previously crashed with TypeError from require_role misuse."""
    phone = f"+91{uuid.uuid4().int % 10**9:09d}"
    await _register(client, phone)
    headers, _ = await _login(client, phone)

    # Sessions are keyed to the PatientProfile bound to the user account.
    profile = await _create_patient(client, headers, "Biren Sharma")
    consent = await client.post(
        "/api/v1/compliance/consent",
        json={"patient_id": profile["id"], "consent_type": "patient_self", "scope": "all"},
        headers=headers,
    )
    assert consent.status_code == 200, consent.text

    resp = await client.post(
        f"{GAMES}/sessions",
        json={"game_type": "match_it", "difficulty_level": 1},
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    session_id = resp.json()["session_id"]

    resp = await client.post(f"{GAMES}/sessions/{session_id}/complete", headers=headers)
    assert resp.status_code == 200, resp.text
    assert resp.json()["accuracy_pct"] == 0.0

    # Non-patient roles are forbidden from starting sessions
    caregiver_phone = f"+91{uuid.uuid4().int % 10**9:09d}"
    await _register(client, caregiver_phone, role="family_caregiver")
    caregiver_headers, _ = await _login(client, caregiver_phone)
    resp = await client.post(
        f"{GAMES}/sessions",
        json={"game_type": "match_it", "difficulty_level": 1},
        headers=caregiver_headers,
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_patient_profile_and_caregiver_link(client):
    caregiver_phone = f"+91{uuid.uuid4().int % 10**9:09d}"
    patient_phone = f"+91{uuid.uuid4().int % 10**9:09d}"

    await _register(client, caregiver_phone, role="family_caregiver")
    caregiver_headers, _ = await _login(client, caregiver_phone)

    patient_user = await _register(client, patient_phone)
    patient_headers, _ = await _login(client, patient_phone)

    profile = await _create_patient(client, patient_headers, "Rupali Devi", user_id=patient_user["id"])
    patient_id = profile["id"]

    # Patient self-service lookup
    resp = await client.get(f"{PATIENTS}/me", headers=patient_headers)
    assert resp.status_code == 200, resp.text
    assert resp.json()["id"] == patient_id

    resp = await client.get(f"{AUTH}/me", headers=caregiver_headers)
    caregiver_id = resp.json()["id"]

    resp = await client.post(
        f"{PATIENTS}/{patient_id}/caregivers",
        json={"caregiver_id": caregiver_id, "relationship_type": "family", "permission_tier": "basic"},
        headers=patient_headers,
    )
    assert resp.status_code == 201, resp.text

    # Caregiver with link may view the patient; patient views own profile
    resp = await client.get(f"{PATIENTS}/{patient_id}", headers=caregiver_headers)
    assert resp.status_code == 200
    resp = await client.get(f"{PATIENTS}/{patient_id}", headers=patient_headers)
    assert resp.status_code == 200

    # An unrelated caregiver has no implicit access
    other_phone = f"+91{uuid.uuid4().int % 10**9:09d}"
    await _register(client, other_phone, role="family_caregiver")
    other_headers, _ = await _login(client, other_phone)
    resp = await client.get(f"{PATIENTS}/{patient_id}", headers=other_headers)
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_phase8to10_routes_wired(client):
    """Phase 8-10 endpoints are mounted and auth-gated where required."""
    # /language/status is public and reports the active provider. Which one is
    # active depends on the configured credentials (auto chain: ai4bharat ->
    # bhashini -> mock), so assert the contract rather than a specific name.
    resp = await client.get("/api/v1/language/status")
    assert resp.status_code == 200, resp.text
    assert resp.json()["provider"] in ("mock", "bhashini", "ai4bharat")
    assert "assamese" in resp.json()["supported_languages"]

    # Companion chat requires authentication
    resp = await client.post(
        "/api/v1/companion/chat/text",
        json={"patient_id": str(uuid.uuid4()), "message": "hello", "language": "assamese"},
    )
    assert resp.status_code in (401, 403)

    # Medical-document answer endpoint requires staff authentication
    resp = await client.post(
        "/api/v1/reports/documents/answer",
        json={"patient_id": str(uuid.uuid4()), "question": "What dosage?"},
    )
    assert resp.status_code in (401, 403)

    # Companion prompt-config endpoints require admin/clinician
    resp = await client.get("/api/v1/companion/config")
    assert resp.status_code in (401, 403)


@pytest.mark.asyncio
async def test_sync_batch_endpoint(client):
    phone = f"+91{uuid.uuid4().int % 10**9:09d}"
    await _register(client, phone)
    headers, _ = await _login(client, phone)

    # Patient self-registers a profile so sync has a valid patient_id
    profile = await _create_patient(client, headers, "Deepak Nath")
    patient_id = profile["id"]

    resp = await client.post(
        f"{SYNC}",
        json={
            "patient_id": patient_id,
            "items": [
                {
                    "resource_type": "game_session",
                    "operation": "create",
                    "resource_id": str(uuid.uuid4()),
                    "payload": {"game_type": "match_it", "score": 90},
                },
                {
                    "resource_type": "reminder_event",
                    "operation": "create",
                    "resource_id": str(uuid.uuid4()),
                    "payload": {"reminder_type": "medicine", "acknowledged": True},
                },
            ],
        },
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["synced"] == 2
    assert resp.json()["errors"] == []

    # Invalid resource_type is rejected with 422
    resp = await client.post(
        f"{SYNC}",
        json={
            "patient_id": patient_id,
            "items": [{"resource_type": "not_a_resource", "operation": "create", "resource_id": str(uuid.uuid4()), "payload": {}}],
        },
        headers=headers,
    )
    assert resp.status_code == 422

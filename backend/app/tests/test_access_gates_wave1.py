"""Wave 1B gates — routine board, alert acknowledge, sync pending.

Routine board serves a patient's own routine steps plus the answer key, so it
is patient-scoped + consent-gated like start_game. Alert acknowledge mutates
state bound to a patient, so it enforces no-implicit-access. Sync pending is
staff-role-gated plus patient-access-checked (defense in depth: 404 on unknown
patients, never an unscoped dump).

Match-it / recall boards are intentionally NOT gated here: they serve generic
puzzles with no patient data (proven by test_level_config_matrix,
test_number_recall, mobile + frontend contracts calling them profile-free).
"""
import uuid

import pytest
from sqlalchemy import select

from app.models.all_models import AlertFlag

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
GAMES = "/api/v1/games"
DASHBOARD = "/api/v1/dashboard"
SYNC = "/api/v1/sync"


async def _register(client, phone, role="patient"):
    r = await client.post(f"{AUTH}/register", json={
        "phone": phone, "email": f"{uuid.uuid4().hex[:8]}@test.in",
        "password": "Passw0rd123", "role": role, "preferred_language": "english"})
    assert r.status_code == 201, r.text
    return r.json()


async def _login(client, phone):
    r = await client.post(f"{AUTH}/login", json={"phone": phone, "password": "Passw0rd123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


async def _patient(client, headers, name):
    r = await client.post(PATIENTS, json={"name": name, "region": "assam"}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()


async def _consent(client, headers, patient_id, scope="all"):
    r = await client.post("/api/v1/compliance/consent", headers=headers, json={
        "patient_id": patient_id, "consent_type": "patient_self", "scope": scope})
    assert r.status_code == 200, r.text


@pytest.mark.asyncio
async def test_routine_board_cross_patient_denied(client):
    """Another patient's routine steps + answer key must never leak across accounts."""
    p1 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    p2 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h1 = await _login(client, p1["phone"])
    h2 = await _login(client, p2["phone"])
    prof1 = await _patient(client, h1, "Aai One")
    prof2 = await _patient(client, h2, "Aai Two")
    await _consent(client, h1, prof1["id"])
    await _consent(client, h2, prof2["id"])

    r = await client.get(
        f"{GAMES}/routine/board",
        params={"patient_id": prof2["id"], "difficulty_level": 1}, headers=h1)
    assert r.status_code == 403, r.text


@pytest.mark.asyncio
async def test_routine_board_owner_allowed_with_consent(client):
    """Owner with game_data consent gets the full board including the answer key."""
    p = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h = await _login(client, p["phone"])
    own = await _patient(client, h, "Owner Two")
    await _consent(client, h, own["id"])

    r = await client.get(
        f"{GAMES}/routine/board",
        params={"patient_id": own["id"], "difficulty_level": 1}, headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["correct_sequence"], "authorized owner must receive the answer key"
    assert len(body["shuffled_items"]) == body["step_count"]


@pytest.mark.asyncio
async def test_routine_board_no_consent_denied(client):
    """Owner without game_data consent is denied (purpose limitation)."""
    p = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h = await _login(client, p["phone"])
    prof = await _patient(client, h, "No Consent")

    r = await client.get(
        f"{GAMES}/routine/board",
        params={"patient_id": prof["id"], "difficulty_level": 1}, headers=h)
    assert r.status_code == 403, r.text


@pytest.mark.asyncio
async def test_routine_board_malformed_patient_id_422(client):
    """Malformed patient_id is a 422, never a 500."""
    p = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h = await _login(client, p["phone"])

    r = await client.get(
        f"{GAMES}/routine/board",
        params={"patient_id": "not-a-uuid", "difficulty_level": 1}, headers=h)
    assert r.status_code == 422, r.text


@pytest.mark.asyncio
async def test_alert_acknowledge_cross_patient_denied(client, db_session):
    """A patient must not acknowledge another patient's alerts."""
    p1 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    p2 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h1 = await _login(client, p1["phone"])
    h2 = await _login(client, p2["phone"])
    prof1 = await _patient(client, h1, "Aai One")
    await _patient(client, h2, "Aai Two")

    alert = AlertFlag(
        patient_id=uuid.UUID(prof1["id"]),
        trigger_type="missed_reminders",
        severity="warning",
        alert_summary="Test alert",
    )
    db_session.add(alert)
    await db_session.commit()

    r = await client.post(f"{DASHBOARD}/alerts/{alert.id}/acknowledge", headers=h2)
    assert r.status_code == 403, r.text
    await db_session.refresh(alert)
    assert alert.acknowledged_at is None, "denied ack must not mutate the alert"


@pytest.mark.asyncio
async def test_alert_acknowledge_linked_caregiver_allowed(client, db_session):
    """Linked caregiver may acknowledge; state mutates exactly once."""
    pat = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    cg = await _register(client, f"+91{uuid.uuid4().int % 10**10}", role="family_caregiver")
    ph = await _login(client, pat["phone"])
    ch = await _login(client, cg["phone"])
    profile = await _patient(client, ph, "Rupali")

    me = await client.get(f"{AUTH}/me", headers=ch)
    r = await client.post(f"{PATIENTS}/{profile['id']}/caregivers", headers=ph, json={
        "caregiver_id": me.json()["id"], "relationship_type": "family"})
    assert r.status_code == 201, r.text

    alert = AlertFlag(
        patient_id=uuid.UUID(profile["id"]),
        trigger_type="activity_drop",
        severity="info",
        alert_summary="Linked ack test",
    )
    db_session.add(alert)
    await db_session.commit()

    r = await client.post(f"{DASHBOARD}/alerts/{alert.id}/acknowledge", headers=ch)
    assert r.status_code == 200, r.text
    assert r.json()["alert_id"] == str(alert.id)
    await db_session.refresh(alert)
    assert alert.acknowledged_at is not None
    assert alert.acknowledged_by is not None


@pytest.mark.asyncio
async def test_sync_pending_unknown_patient_404_and_patient_role_denied(client):
    """Staff gets 404 (not a dump, not a 500) for unknown patients; patients are role-denied."""
    from app.tests.conftest import provision_staff_user

    clinician = await provision_staff_user()
    hh = await _login(client, clinician["phone"])

    r = await client.get(f"{SYNC}/pending/{uuid.uuid4()}", headers=hh)
    assert r.status_code == 404, r.text

    p = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    ph = await _login(client, p["phone"])
    prof = await _patient(client, ph, "Sync Denied")
    r = await client.get(f"{SYNC}/pending/{prof['id']}", headers=ph)
    assert r.status_code == 403, r.text


@pytest.mark.asyncio
async def test_sync_pending_staff_sees_own_panel_list(client):
    """Staff role + existing patient returns the (possibly empty) pending list."""
    from app.tests.conftest import provision_staff_user
    from app.tests.conftest import create_consented_patient

    clinician = await provision_staff_user()
    hh = await _login(client, clinician["phone"])
    profile = await create_consented_patient(client, "Sync Listed")

    r = await client.get(f"{SYNC}/pending/{profile['id']}", headers=hh)
    assert r.status_code == 200, r.text
    assert isinstance(r.json(), list)


@pytest.mark.asyncio
async def test_generic_boards_stay_profile_free(client):
    """Match-it / recall boards serve generic puzzles: any authenticated caller, no patient."""
    p = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h = await _login(client, p["phone"])

    r = await client.get(
        f"{GAMES}/content-packs/festivals_ner/board",
        params={"difficulty_level": 1}, headers=h)
    assert r.status_code == 200, r.text

    r = await client.get(f"{GAMES}/recall/board", params={"difficulty_level": 1}, headers=h)
    assert r.status_code == 200, r.text

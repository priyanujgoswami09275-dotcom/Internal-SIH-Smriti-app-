"""Wave 5 hardening — malformed-UUID 422s, missed routine-GET gate, doc_type
and companion input caps.

- Malformed patient_id on games history/stats/routine/evaluate → 422, never 500.
- GET /games/patients/{id}/routine is patient-access-gated (missed in 1B; the
  routine is the patient's own daily schedule — no-implicit-access).
- POST /reports/documents/ingest rejects unknown doc_type → 422.
- POST /companion/chat/text rejects oversized message/history → 422.
"""
import uuid

import pytest

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
GAMES = "/api/v1/games"
REPORTS = "/api/v1/reports"
COMPANION = "/api/v1/companion"


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


@pytest.mark.asyncio
async def test_history_malformed_patient_id_422(client):
    from app.tests.conftest import provision_staff_user

    clinician = await provision_staff_user()
    h = await _login(client, clinician["phone"])
    r = await client.get(f"{GAMES}/patients/not-a-uuid/history", headers=h)
    assert r.status_code == 422, r.text
    assert "valid UUID" in r.json()["detail"]


@pytest.mark.asyncio
async def test_stats_malformed_patient_id_422(client):
    from app.tests.conftest import provision_staff_user

    clinician = await provision_staff_user()
    h = await _login(client, clinician["phone"])
    r = await client.get(f"{GAMES}/patients/not-a-uuid/stats", headers=h)
    assert r.status_code == 422, r.text


@pytest.mark.asyncio
async def test_evaluate_malformed_patient_id_422(client):
    cg = await _register(client, f"+91{uuid.uuid4().int % 10**10}", role="family_caregiver")
    h = await _login(client, cg["phone"])
    r = await client.post(
        f"{GAMES}/difficulty/evaluate",
        params={"patient_id": "not-a-uuid", "game_type": "match_it",
                "current_difficulty": 1}, headers=h)
    assert r.status_code == 422, r.text


@pytest.mark.asyncio
async def test_routine_get_and_update_malformed_patient_id_422(client):
    # Role gates resolve before the body parse, so the parse path needs a
    # caregiver/staff caller (patients get 403 first — also correct).
    cg = await _register(client, f"+91{uuid.uuid4().int % 10**10}", role="family_caregiver")
    h = await _login(client, cg["phone"])
    r = await client.get(f"{GAMES}/patients/not-a-uuid/routine", headers=h)
    assert r.status_code == 422, r.text
    r = await client.post(f"{GAMES}/patients/not-a-uuid/routine", headers=h,
                          json={"steps": []})
    assert r.status_code == 422, r.text


@pytest.mark.asyncio
async def test_routine_get_cross_patient_denied(client):
    """GET routine is patient-access-gated (missed privacy gate, Wave 5)."""
    p1 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    p2 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h1 = await _login(client, p1["phone"])
    h2 = await _login(client, p2["phone"])
    prof1 = await _patient(client, h1, "Aai One")
    await _patient(client, h2, "Aai Two")

    r = await client.get(f"{GAMES}/patients/{prof1['id']}/routine", headers=h2)
    assert r.status_code == 403, r.text
    # Owner still reads their own routine.
    r = await client.get(f"{GAMES}/patients/{prof1['id']}/routine", headers=h1)
    assert r.status_code == 200, r.text


@pytest.mark.asyncio
async def test_doc_ingest_unknown_doc_type_422(client):
    from app.tests.conftest import provision_staff_user, create_consented_patient

    clinician = await provision_staff_user()
    hh = await _login(client, clinician["phone"])
    profile = await create_consented_patient(client, "Doc Type")

    r = await client.post(f"{REPORTS}/documents/ingest", headers=hh, json={
        "patient_id": profile["id"], "file_ref": "s3://x/y.pdf",
        "doc_type": "vibeo", "extracted_text": "some text"})
    assert r.status_code == 422, r.text
    # FastAPI field-validator errors: detail is a list of error objects.
    assert any("Invalid doc_type" in str(item.get("msg", ""))
               for item in r.json()["detail"])


@pytest.mark.asyncio
async def test_chat_text_message_and_history_capped(client):
    from app.tests.conftest import create_consented_patient

    profile = await create_consented_patient(client, "Cap Test")
    p = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h = await _login(client, p["phone"])
    # Bind profile to this user so access passes; consent already granted.
    from app.models.all_models import PatientProfile  # noqa: F401 — binding via API below
    # create_consented_patient registers its own user; use /patients/{id}/caregivers
    # is not needed — instead exercise the caps via validation (pre-DB).
    big = "x" * 2001
    r = await client.post(f"{COMPANION}/chat/text", headers=h, json={
        "patient_id": profile["id"], "message": big, "language": "english"})
    assert r.status_code == 422, r.text

    huge_history = [{"role": "user", "content": "hi"}] * 51
    r = await client.post(f"{COMPANION}/chat/text", headers=h, json={
        "patient_id": profile["id"], "message": "hello", "language": "english",
        "history": huge_history})
    assert r.status_code == 422, r.text

"""P0 stabilization regression tests — proves each critical fix blocks the bad
path (not just that the happy path still works).

Covers:
1. At-rest encryption reads the configured ENCRYPTION_KEY (not a hardcoded default).
2. Weekly clinical report decrypts symptom notes (no ciphertext leak).
3. /language/* heavy endpoints require authentication.
4. Consent revoke enforces no-implicit-access on the owning patient.
5. Game session actions/complete reject a session the caller does not own (IDOR).
"""
import uuid
from uuid import UUID

import pytest

from app.config import settings
from app.models.all_models import SymptomLog, SymptomEntrySourceEnum
from app.services.compliance_service import EncryptionService
from app.services.report_service import ReportService

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
GAMES = "/api/v1/games"
COMPLIANCE = "/api/v1/compliance"
LANGUAGE = "/api/v1/language"

OLD_HARDCODED_DEFAULT = "sih26_default_secure_secret_key_32bytes!!"


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


async def _uid(client, headers):
    r = await client.get(f"{AUTH}/me", headers=headers)
    assert r.status_code == 200
    return r.json()["id"]


async def _grant_consent(client, headers, patient_id, scope="all"):
    r = await client.post(f"{COMPLIANCE}/consent", headers=headers, json={
        "patient_id": patient_id, "consent_type": "patient_self", "scope": scope})
    assert r.status_code == 200, r.text
    return r.json()


# ---------- Fix 1: encryption key from config ----------


def test_encryption_uses_configured_key_not_hardcoded_default(monkeypatch):
    monkeypatch.setattr(settings, "ENCRYPTION_KEY", "unit-test-configured-key-123456")
    svc = EncryptionService()
    token = svc.encrypt("secret note")

    # Round-trips with a service built from the SAME configured key.
    assert EncryptionService(key="unit-test-configured-key-123456").decrypt(token) == "secret note"
    # The old hardcoded default can no longer decrypt it (proves the bug is fixed).
    assert EncryptionService(key=OLD_HARDCODED_DEFAULT).decrypt(token) != "secret note"


# ---------- Fix 2: report decrypts symptom notes ----------


@pytest.mark.asyncio
async def test_weekly_report_decrypts_symptom_notes(client, db_session):
    from app.tests.conftest import provision_staff_user

    clin = await provision_staff_user()
    hh = await _login(client, clin["phone"])
    profile = await _patient(client, hh, "Biren")
    clin_id = await _uid(client, hh)

    plaintext = "Patient reports dizziness in the mornings."
    db_session.add(SymptomLog(
        patient_id=UUID(profile["id"]),
        entered_by=UUID(clin_id),
        entry_source=SymptomEntrySourceEnum.MANUAL_CAREGIVER,
        notes=EncryptionService().encrypt(plaintext),
        severity=2,
    ))
    await db_session.commit()

    report = await ReportService.generate_weekly_clinical_summary(db_session, UUID(profile["id"]))
    notes = report["symptom_observations"]
    assert plaintext in notes
    assert not any("gAAAA" in n for n in notes)  # no Fernet ciphertext leaked


# ---------- Fix 3: /language/* requires auth ----------


@pytest.mark.asyncio
async def test_language_endpoints_require_auth(client):
    # status stays public (mobile connectivity probe)
    assert (await client.get(f"{LANGUAGE}/status")).status_code == 200

    # heavy endpoints (paid Bhashini/HF proxy) reject anonymous callers
    for path, body in [
        (f"{LANGUAGE}/asr", {"audio_base64": "eA==", "source_language": "assamese"}),
        (f"{LANGUAGE}/tts", {"text": "hi", "target_language": "assamese"}),
        (f"{LANGUAGE}/translate", {"text": "hi", "source_language": "assamese", "target_language": "english"}),
    ]:
        r = await client.post(path, json=body)
        assert r.status_code in (401, 403), f"{path} should require auth, got {r.status_code}"

    # with a valid token, ASR works regardless of the active provider
    # (valid base64 so the ai4bharat path decodes it; the mock ignores it)
    u = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h = await _login(client, u["phone"])
    ok = await client.post(f"{LANGUAGE}/asr", headers=h,
                           json={"audio_base64": "eA==", "source_language": "assamese"})
    assert ok.status_code == 200, ok.text


# ---------- Fix 4: consent revoke ownership ----------


@pytest.mark.asyncio
async def test_consent_revoke_requires_ownership(client):
    p1 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    p2 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h1 = await _login(client, p1["phone"])
    h2 = await _login(client, p2["phone"])
    prof1 = await _patient(client, h1, "Aai One")
    await _patient(client, h2, "Aai Two")

    consent = await _grant_consent(client, h1, prof1["id"])

    # p2 must not be able to revoke p1's consent
    bad = await client.post(f"{COMPLIANCE}/consent/{consent['id']}/revoke", headers=h2)
    assert bad.status_code == 403, bad.text

    # owner can revoke
    good = await client.post(f"{COMPLIANCE}/consent/{consent['id']}/revoke", headers=h1)
    assert good.status_code == 200, good.text

    # unknown consent id -> 404
    missing = await client.post(f"{COMPLIANCE}/consent/{uuid.uuid4()}/revoke", headers=h1)
    assert missing.status_code == 404


# ---------- Fix 5: game session IDOR ----------


@pytest.mark.asyncio
async def test_game_session_actions_reject_foreign_owner(client):
    p1 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    p2 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h1 = await _login(client, p1["phone"])
    h2 = await _login(client, p2["phone"])
    prof1 = await _patient(client, h1, "Owner")
    await _patient(client, h2, "Attacker")
    await _grant_consent(client, h1, prof1["id"])

    start = await client.post(f"{GAMES}/sessions", headers=h1, json={
        "game_type": "match_it", "difficulty_level": 1})
    assert start.status_code == 200, start.text
    sid = start.json()["session_id"]

    # owner can record on own session
    own = await client.post(f"{GAMES}/sessions/{sid}/actions", headers=h1, json={
        "action_type": "match", "action_data": {}, "is_correct": True, "response_time_ms": 900})
    assert own.status_code == 200, own.text

    # attacker (different patient) cannot record or complete
    bad_action = await client.post(f"{GAMES}/sessions/{sid}/actions", headers=h2, json={
        "action_type": "match", "action_data": {}, "is_correct": True, "response_time_ms": 900})
    assert bad_action.status_code == 403, bad_action.text

    bad_complete = await client.post(f"{GAMES}/sessions/{sid}/complete", headers=h2)
    assert bad_complete.status_code == 403, bad_complete.text

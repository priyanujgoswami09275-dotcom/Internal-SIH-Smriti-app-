"""Consent-scope, permission-tier, export, and production-boot gates."""
import uuid

import pytest

from app.config import Settings

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
GAMES = "/api/v1/games"
REPORTS = "/api/v1/reports"
COMPANION = "/api/v1/companion"
COMPLIANCE = "/api/v1/compliance"
DASHBOARD = "/api/v1/dashboard"


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
async def test_game_session_requires_game_data_consent(client):
    user = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    headers = await _login(client, user["phone"])
    await _patient(client, headers, "No Consent Yet")

    r = await client.post(f"{GAMES}/sessions", headers=headers, json={
        "game_type": "match_it", "difficulty_level": 1})
    assert r.status_code == 403
    assert "consent" in r.json()["detail"].lower()


@pytest.mark.asyncio
async def test_game_session_succeeds_after_consent(client):
    user = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    headers = await _login(client, user["phone"])
    profile = await _patient(client, headers, "With Consent")
    g = await client.post(f"{COMPLIANCE}/consent", headers=headers, json={
        "patient_id": profile["id"], "consent_type": "patient_self", "scope": "game_data"})
    assert g.status_code == 200, g.text
    r = await client.post(f"{GAMES}/sessions", headers=headers, json={
        "game_type": "match_it", "difficulty_level": 1})
    assert r.status_code == 200, r.text


@pytest.mark.asyncio
async def test_companion_requires_voice_scope_not_just_game_data(client):
    user = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    headers = await _login(client, user["phone"])
    profile = await _patient(client, headers, "Games Only")
    await client.post(f"{COMPLIANCE}/consent", headers=headers, json={
        "patient_id": profile["id"], "consent_type": "patient_self", "scope": "game_data"})
    r = await client.post(f"{COMPANION}/chat/text", headers=headers, json={
        "patient_id": profile["id"], "message": "hello", "language": "english"})
    assert r.status_code == 403
    assert "voice_companion" in r.json()["detail"]


@pytest.mark.asyncio
async def test_family_basic_cannot_read_clinical_documents(client):
    pat = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    cg = await _register(client, f"+91{uuid.uuid4().int % 10**10}", role="family_caregiver")
    ph = await _login(client, pat["phone"])
    ch = await _login(client, cg["phone"])
    profile = await _patient(client, ph, "Rupali")
    me = await client.get(f"{AUTH}/me", headers=ch)
    linked = await client.post(f"{PATIENTS}/{profile['id']}/caregivers", headers=ph, json={
        "caregiver_id": me.json()["id"], "relationship_type": "family",
        "permission_tier": "basic"})
    assert linked.status_code == 201, linked.text
    granted = await client.post(f"{COMPLIANCE}/consent", headers=ph, json={
        "patient_id": profile["id"], "consent_type": "patient_self", "scope": "all"})
    assert granted.status_code == 200, granted.text

    r = await client.post(f"{REPORTS}/documents/ingest", headers=ch, json={
        "patient_id": profile["id"], "file_ref": "rx.pdf", "doc_type": "prescription",
        "extracted_text": "Amlodipine 5 mg"})
    assert r.status_code == 403

    hist = await client.get(f"{GAMES}/patients/{profile['id']}/history", headers=ch)
    assert hist.status_code == 403

    summary = await client.get(f"{DASHBOARD}/patients/{profile['id']}/summary", headers=ch)
    assert summary.status_code == 200
    body = summary.json()
    assert body["view"] == "basic"
    assert "accuracy_pct" not in body
    assert "games_played" in body


@pytest.mark.asyncio
async def test_family_clinical_and_export(client):
    pat = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    cg = await _register(client, f"+91{uuid.uuid4().int % 10**10}", role="family_caregiver")
    ph = await _login(client, pat["phone"])
    ch = await _login(client, cg["phone"])
    profile = await _patient(client, ph, "Biren")
    me = await client.get(f"{AUTH}/me", headers=ch)
    linked = await client.post(f"{PATIENTS}/{profile['id']}/caregivers", headers=ph, json={
        "caregiver_id": me.json()["id"], "relationship_type": "family",
        "permission_tier": "clinical"})
    assert linked.status_code == 201, linked.text
    granted = await client.post(f"{COMPLIANCE}/consent", headers=ph, json={
        "patient_id": profile["id"], "consent_type": "patient_self", "scope": "all"})
    assert granted.status_code == 200, granted.text

    r = await client.post(f"{REPORTS}/documents/ingest", headers=ch, json={
        "patient_id": profile["id"], "file_ref": "rx-clinical.pdf", "doc_type": "prescription",
        "extracted_text": "Metformin 500 mg"})
    assert r.status_code == 200, r.text

    summary = await client.get(f"{DASHBOARD}/patients/{profile['id']}/summary", headers=ch)
    assert summary.status_code == 200
    body = summary.json()
    assert body["view"] == "clinical"
    assert "daily_trends" in body
    assert len(body["daily_trends"]) == 14

    exported = await client.get(f"{COMPLIANCE}/patients/{profile['id']}/export", headers=ch)
    assert exported.status_code == 200, exported.text
    dump = exported.json()
    assert dump["patient"]["id"] == profile["id"]
    assert "consents" in dump


def test_production_refuses_placeholder_secrets():
    s = Settings()
    s.ENVIRONMENT = "production"
    s.SECRET_KEY = "your-secret-key-change-in-production"
    s.ENCRYPTION_KEY = "ok-enough-secret-here"
    s.CORS_ORIGINS = "https://app.example.org"
    with pytest.raises(RuntimeError, match="SECRET_KEY"):
        s.validate_for_environment()


def test_production_refuses_wildcard_cors():
    s = Settings()
    s.ENVIRONMENT = "production"
    s.SECRET_KEY = "a-sufficiently-long-production-secret"
    s.ENCRYPTION_KEY = "a-sufficiently-long-encryption-key"
    s.CORS_ORIGINS = "*"
    with pytest.raises(RuntimeError, match="CORS_ORIGINS"):
        s.validate_for_environment()


def test_development_allows_placeholders():
    s = Settings()
    s.ENVIRONMENT = "development"
    s.validate_for_environment()  # does not raise

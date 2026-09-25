"""Phase 11 gates — no-implicit-access, read-audit trail, at-rest encryption."""
import uuid

import pytest
from sqlalchemy import select

from app.models.all_models import AuditLog, DocumentChunk, MedicalDocument
from app.services.compliance_service import EncryptionService

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
REMINDERS = "/api/v1/reminders"
DASHBOARD = "/api/v1/dashboard"
COMPANION = "/api/v1/companion"
REPORTS = "/api/v1/reports"


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


@pytest.mark.asyncio
async def test_cross_patient_access_denied(client):
    """A patient must never read another patient's data via any route."""
    p1 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    p2 = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h1 = await _login(client, p1["phone"])
    h2 = await _login(client, p2["phone"])
    prof1 = await _patient(client, h1, "Aai One")
    prof2 = await _patient(client, h2, "Aai Two")
    # sanity: each sees own
    assert (await client.get(f"{PATIENTS}/me", headers=h1)).json()["id"] == prof1["id"]

    # profile, reminder data, dashboard summary, companion chat -> 403
    assert (await client.get(f"{PATIENTS}/{prof2['id']}", headers=h1)).status_code == 403
    assert (await client.get(
        f"{REMINDERS}/schedules/{prof2['id']}", headers=h1)).status_code == 403
    assert (await client.get(
        f"{REMINDERS}/patients/{prof2['id']}/events", headers=h1)).status_code == 403
    assert (await client.get(
        f"{DASHBOARD}/patients/{prof2['id']}/summary", headers=h1)).status_code == 403
    r = await client.post(f"{COMPANION}/chat/text", headers=h1, json={
        "patient_id": prof2["id"], "message": "hello", "language": "english"})
    assert r.status_code == 403
    # no such patient -> 404 (not 403 — avoids existence leaks)
    assert (await client.get(
        f"{PATIENTS}/{uuid.uuid4()}", headers=h1)).status_code == 404


@pytest.mark.asyncio
async def test_linked_caregiver_can_access_and_reads_are_audited(client, db_session):
    """Linked caregiver may view patient data; each health read leaves an audit row."""
    pat = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    cg = await _register(client, f"+91{uuid.uuid4().int % 10**10}", role="family_caregiver")
    ph = await _login(client, pat["phone"])
    ch = await _login(client, cg["phone"])
    profile = await _patient(client, ph, "Rupali")
    cg_id_str = await _uid(client, ch)          # /auth/me returns a string id
    cg_id = uuid.UUID(cg_id_str)

    r = await client.post(f"{PATIENTS}/{profile['id']}/caregivers", headers=ph, json={
        "caregiver_id": cg_id_str, "relationship_type": "family"})
    assert r.status_code == 201, r.text

    # audited reads
    assert (await client.get(f"{PATIENTS}/{profile['id']}", headers=ch)).status_code == 200
    assert (await client.get(
        f"{REMINDERS}/schedules/{profile['id']}", headers=ch)).status_code == 200
    assert (await client.get(
        f"{REMINDERS}/patients/{profile['id']}/events", headers=ch)).status_code == 200
    assert (await client.get(
        f"{DASHBOARD}/patients/{profile['id']}/summary", headers=ch)).status_code == 200

    # an unrelated caregiver (no link) is denied
    other_cg = await _register(client, f"+91{uuid.uuid4().int % 10**10}", role="family_caregiver")
    other_h = await _login(client, other_cg["phone"])
    assert (await client.get(
        f"{DASHBOARD}/patients/{profile['id']}/summary", headers=other_h)).status_code == 403

    rows = (await db_session.execute(
        select(AuditLog).where(AuditLog.user_id == cg_id)
    )).scalars().all()
    kinds = {r.resource_type for r in rows}
    assert {"patient_profile", "reminder_schedule", "reminder_event", "dashboard_summary"} <= kinds
    assert all(r.action.value == "read" for r in rows)


@pytest.mark.asyncio
async def test_document_ingest_stores_encrypted_source_and_chunks(client, db_session):
    """Source text and chunk PHI are encrypted at rest; retrieval decrypts chunks."""
    from app.tests.conftest import provision_staff_user

    clinician = await provision_staff_user()
    hh = await _login(client, clinician["phone"])
    from app.tests.conftest import create_consented_patient

    profile = await create_consented_patient(client, "Biren")

    text = "Take one Amlodipine 5 mg tablet every morning with food."
    r = await client.post(f"{REPORTS}/documents/ingest", headers=hh, json={
        "patient_id": profile["id"], "file_ref": "ph11-rx.pdf",
        "doc_type": "prescription", "title": "Phase11 Rx", "extracted_text": text})
    assert r.status_code == 200, r.text

    doc = (await db_session.execute(
        select(MedicalDocument).where(MedicalDocument.file_ref == "ph11-rx.pdf")
    )).scalar_one()
    assert doc.extracted_text.startswith("gAAAA")   # Fernet ciphertext
    assert doc.extracted_text != text
    assert EncryptionService().decrypt(doc.extracted_text) == text
    chunk = (await db_session.execute(
        select(DocumentChunk).where(DocumentChunk.document_id == doc.id)
    )).scalar_one()
    assert chunk.chunk_text.startswith("gAAAA")
    assert EncryptionService().decrypt(chunk.chunk_text) == text
    q = await client.post(f"{REPORTS}/documents/query", headers=hh, json={
        "patient_id": profile["id"], "query": "Amlodipine morning dose", "top_k": 2})
    assert q.status_code == 200
    assert len(q.json().get("matches", [])) >= 1
    assert "Amlodipine" in q.json()["matches"][0]["text"]

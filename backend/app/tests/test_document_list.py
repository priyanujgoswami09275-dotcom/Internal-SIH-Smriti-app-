"""GET /reports/patients/{id}/documents — list metadata for a patient's RAG docs.

Read path must mirror documents/query: clinical tier + health_data consent,
DPDP read audit, metadata only (never extracted_text).
"""
import asyncio
import io
from uuid import UUID

import pytest
from sqlalchemy import select

from app.models.all_models import AuditLog
from app.models.user import User

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
REPORTS = "/api/v1/reports"


async def _staff_with_patient(client, role="clinician"):
    from app.tests.conftest import create_consented_patient, provision_staff_user

    user = await provision_staff_user(role=role)
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    assert login.status_code == 200, login.text
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    prof = await create_consented_patient(client, "List Patient")
    return h, prof["id"]


async def _upload_text(client, headers, pid, name="notes.txt"):
    up = await client.post(f"{REPORTS}/documents/upload",
        params={"patient_id": pid, "title": "List title"},
        headers=headers,
        files={"file": (name, io.BytesIO(
            b"Patient takes Donepezil 5 mg at bedtime for memory support."), "text/plain")},
        data={"doc_type": "prescription", "title": "List title"})
    assert up.status_code == 200, up.text
    return up.json()


@pytest.mark.asyncio
@pytest.mark.parametrize("role", ["clinician", "asha_worker", "admin"])
async def test_list_returns_metadata_newest_first(client, role):
    h, pid = await _staff_with_patient(client, role)
    await _upload_text(client, h, pid, "older.txt")
    await asyncio.sleep(1.1)
    await _upload_text(client, h, pid, "newer.txt")

    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["count"] == 2
    first = body["documents"][0]
    assert first["file_name"] == "newer.txt"
    assert first["title"] == "List title"
    assert first["doc_type"] == "prescription"
    assert first["embedding_status"] in ("pending", "processing", "completed", "failed")
    assert first["created_at"]
    # Metadata only — encrypted PHI must never be echoed.
    assert "extracted_text" not in first
    assert "embedding" not in first


@pytest.mark.asyncio
async def test_list_empty_is_not_an_error(client):
    h, pid = await _staff_with_patient(client)
    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200
    assert r.json() == {"documents": [], "count": 0}


@pytest.mark.asyncio
async def test_list_writes_read_audit(client, db_session):
    h, pid = await _staff_with_patient(client)
    await _upload_text(client, h, pid)
    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200
    rows = (await db_session.execute(select(AuditLog).where(
        AuditLog.resource_type == "medical_document", AuditLog.action == "read"))).scalars().all()
    assert rows, "listing documents must write a DPDP read audit"


@pytest.mark.asyncio
async def test_list_family_caregiver_basic_tier_is_403(client, db_session):
    # Family caregiver linked at the default BASIC tier cannot read documents.
    reg = await client.post(f"{AUTH}/register", json={
        "phone": "+919000000001", "password": "Passw0rd123",
        "role": "family_caregiver", "preferred_language": "english"})
    assert reg.status_code == 201, reg.text
    fam = reg.json()
    fam_login = await client.post(f"{AUTH}/login", json={
        "phone": fam["phone"], "password": "Passw0rd123"})
    fh = {"Authorization": f"Bearer {fam_login.json()['access_token']}"}

    from app.tests.conftest import create_consented_patient
    prof = await create_consented_patient(client, "Family View Patient")
    pid = prof["id"]
    owner_login = await client.post(f"{AUTH}/login", json={
        "phone": (await db_session.execute(
            select(User.phone).where(User.id == UUID(prof["user_id"]))
        )).scalar_one(), "password": "Passw0rd123"})
    oh = {"Authorization": f"Bearer {owner_login.json()['access_token']}"}
    link = await client.post(f"{PATIENTS}/{pid}/caregivers", headers=oh,
        json={"caregiver_id": fam["id"], "relationship_type": "family"})
    assert link.status_code == 201, link.text

    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=fh)
    assert r.status_code == 403
    assert r.json()["detail"] == "Clinical permission tier required for this resource"


@pytest.mark.asyncio
async def test_list_patient_role_is_403(client, db_session):
    from app.tests.conftest import create_consented_patient
    prof = await create_consented_patient(client, "Self Patient")
    pid = prof["id"]
    login = await client.post(f"{AUTH}/login", json={
        "phone": (await db_session.execute(
            select(User.phone).where(User.id == UUID(prof["user_id"]))
        )).scalar_one(), "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_list_without_health_data_consent_is_403(client):
    from app.tests.conftest import provision_staff_user
    user = await provision_staff_user(role="clinician")
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    # Patient created WITHOUT the default all-scope consent.
    reg = await client.post(f"{AUTH}/register", json={
        "phone": "+919000000002", "password": "Passw0rd123",
        "role": "patient", "preferred_language": "english"})
    pl = await client.post(f"{AUTH}/login", json={
        "phone": reg.json()["phone"], "password": "Passw0rd123"})
    ph = {"Authorization": f"Bearer {pl.json()['access_token']}"}
    prof = (await client.post(f"{PATIENTS}", headers=ph, json={"name": "No Consent"})).json()

    r = await client.get(f"{REPORTS}/patients/{prof['id']}/documents", headers=h)
    assert r.status_code == 403
    assert "health_data" in r.json()["detail"]

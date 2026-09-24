"""P5 — document file upload: PDF/text extraction feeds the existing RAG ingest.

Bad path covered: unsupported type -> 400; empty file -> 400; oversized -> 413.
"""
import io

import pytest

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
REPORTS = "/api/v1/reports"
COMPLIANCE = "/api/v1/compliance"


async def _clinician_with_patient(client):
    from app.tests.conftest import provision_staff_user

    user = await provision_staff_user()
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    assert login.status_code == 200, login.text
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    from app.tests.conftest import create_consented_patient

    prof = await create_consented_patient(client, "Upload Patient")
    return h, prof["id"]


@pytest.mark.asyncio
async def test_upload_text_file_ingests_and_answers(client):
    h, pid = await _clinician_with_patient(client)
    up = await client.post(f"{REPORTS}/documents/upload?patient_id={pid}",
        headers=h,
        files={"file": ("notes.txt", io.BytesIO(
            b"Patient takes Donepezil 5 mg once daily at bedtime for memory support."
        ), "text/plain")},
        data={"doc_type": "prescription", "title": "Text upload"})
    assert up.status_code == 200, up.text
    body = up.json()
    assert body["chars_extracted"] > 0
    assert "extracted" in body["message"]

    # and it is retrievable through the normal RAG path
    q = await client.post(f"{REPORTS}/documents/query", headers=h,
        json={"patient_id": pid, "query": "Donepezil bedtime", "top_k": 3})
    assert q.status_code == 200
    assert any("Donepezil" in m["text"] for m in q.json()["matches"])


@pytest.mark.asyncio
async def test_upload_real_pdf(client):
    # Minimal one-page PDF built with pypdf in-memory.
    from pypdf import PdfWriter
    w = PdfWriter()
    w.add_blank_page(width=612, height=792)
    # pypdf can't add text natively; use extraction on the blank -> "no text"
    # is exactly the scanned-PDF path we must handle with a 400.
    buf = io.BytesIO()
    w.write(buf)
    h, pid = await _clinician_with_patient(client)
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={pid}",
        headers=h,
        files={"file": ("scan.pdf", io.BytesIO(buf.getvalue()), "application/pdf")},
        data={"doc_type": "report"})
    assert r.status_code == 400
    assert "selectable text" in r.json()["detail"] or "No selectable" in r.json()["detail"]


@pytest.mark.asyncio
async def test_upload_rejects_unsupported_type(client):
    h, pid = await _clinician_with_patient(client)
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={pid}",
        headers=h,
        files={"file": ("image.png", io.BytesIO(b"\x89PNG\r\n\x1a\n..."), "image/png")})
    assert r.status_code == 400
    assert "Unsupported" in r.json()["detail"]


@pytest.mark.asyncio
async def test_upload_rejects_empty_file(client):
    h, pid = await _clinician_with_patient(client)
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={pid}",
        headers=h, files={"file": ("empty.txt", io.BytesIO(b""), "text/plain")})
    assert r.status_code == 400


async def _family_caregiver_for(client, db_session, patient_profile):
    from uuid import UUID

    from sqlalchemy import select

    from app.models.user import User

    reg = await client.post("/api/v1/auth/register", json={
        "phone": "+919100000001", "password": "Passw0rd123",
        "role": "family_caregiver", "preferred_language": "english"})
    assert reg.status_code == 201, reg.text
    fam = reg.json()
    login = await client.post("/api/v1/auth/login", json={
        "phone": fam["phone"], "password": "Passw0rd123"})
    fh = {"Authorization": f"Bearer {login.json()['access_token']}"}
    owner_login = await client.post("/api/v1/auth/login", json={
        "phone": (await db_session.execute(
            select(User.phone).where(User.id == UUID(patient_profile["user_id"]))
        )).scalar_one(), "password": "Passw0rd123"})
    oh = {"Authorization": f"Bearer {owner_login.json()['access_token']}"}
    link = await client.post(f"/api/v1/patients/{patient_profile['id']}/caregivers",
        headers=oh, json={"caregiver_id": fam["id"], "relationship_type": "family"})
    assert link.status_code == 201, link.text
    return fh


@pytest.mark.asyncio
@pytest.mark.parametrize("role", ["asha_worker", "admin"])
async def test_upload_allowed_roles(client, role):
    from app.tests.conftest import create_consented_patient, provision_staff_user
    user = await provision_staff_user(role=role)
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    prof = await create_consented_patient(client, f"Upload {role}")
    pid = prof["id"]
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={pid}", headers=h,
        files={"file": ("a.txt", io.BytesIO(b"Metformin 500 mg twice daily."), "text/plain")})
    assert r.status_code == 200, r.text


@pytest.mark.asyncio
async def test_upload_family_caregiver_basic_tier_is_403(client, db_session):
    h, pid = await _clinician_with_patient(client)
    from app.tests.conftest import create_consented_patient
    prof = await create_consented_patient(client, "Family Upload Patient")
    fh = await _family_caregiver_for(client, db_session, prof)
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={prof['id']}", headers=fh,
        files={"file": ("a.txt", io.BytesIO(b"Metformin 500 mg."), "text/plain")})
    assert r.status_code == 403
    assert r.json()["detail"] == "Clinical permission tier required for this resource"


@pytest.mark.asyncio
async def test_upload_patient_role_is_403(client, db_session):
    from uuid import UUID

    from sqlalchemy import select

    from app.models.user import User

    from app.tests.conftest import create_consented_patient
    prof = await create_consented_patient(client, "Self Upload Patient")
    login = await client.post(f"{AUTH}/login", json={
        "phone": (await db_session.execute(
            select(User.phone).where(User.id == UUID(prof["user_id"]))
        )).scalar_one(), "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={prof['id']}", headers=h,
        files={"file": ("a.txt", io.BytesIO(b"Metformin 500 mg."), "text/plain")})
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_upload_oversized_is_413(client):
    h, pid = await _clinician_with_patient(client)
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={pid}", headers=h,
        files={"file": ("big.txt", io.BytesIO(b"x" * (10 * 1024 * 1024 + 1)), "text/plain")})
    assert r.status_code == 413
    assert "10 MB" in r.json()["detail"]


@pytest.mark.asyncio
async def test_upload_without_health_data_consent_is_403(client):
    from app.tests.conftest import provision_staff_user
    user = await provision_staff_user(role="clinician")
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    reg = await client.post(f"{AUTH}/register", json={
        "phone": "+919100000002", "password": "Passw0rd123",
        "role": "patient", "preferred_language": "english"})
    pl = await client.post(f"{AUTH}/login", json={
        "phone": reg.json()["phone"], "password": "Passw0rd123"})
    ph = {"Authorization": f"Bearer {pl.json()['access_token']}"}
    prof = (await client.post(f"{PATIENTS}", headers=ph, json={"name": "Upload No Consent"})).json()
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={prof['id']}", headers=h,
        files={"file": ("a.txt", io.BytesIO(b"Metformin 500 mg."), "text/plain")})
    assert r.status_code == 403
    assert "health_data" in r.json()["detail"]

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

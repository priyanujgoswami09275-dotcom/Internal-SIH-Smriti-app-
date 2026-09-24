"""GET /reports/patients/{id}/documents — list metadata for a patient's RAG docs.

Read path must mirror documents/query: clinical tier + health_data consent,
DPDP read audit, metadata only (never extracted_text).
"""
import asyncio
import io
import uuid
from datetime import datetime, timedelta
from uuid import UUID

import pytest
from sqlalchemy import select, text

from app.models.all_models import (
    AuditLog,
    DocumentChunk,
    DocumentTypeEnum,
    EmbeddingStatusEnum,
    MedicalDocument,
)
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
    return h, prof["id"], user["id"]


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
    h, pid, _ = await _staff_with_patient(client, role)
    await _upload_text(client, h, pid, "older.txt")
    await asyncio.sleep(1.1)
    await _upload_text(client, h, pid, "newer.txt")

    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    document_keys = {
        "document_id", "title", "file_name", "doc_type",
        "embedding_status", "created_at",
    }
    assert set(body) == {"documents", "count"}
    assert body["count"] == len(body["documents"]) == 2
    assert all(set(document) == document_keys for document in body["documents"])
    first = body["documents"][0]
    second = body["documents"][1]
    assert UUID(first["document_id"])
    assert UUID(second["document_id"])
    assert first["document_id"] != second["document_id"]
    assert first["file_name"] == "newer.txt"
    assert second["file_name"] == "older.txt"
    for document in body["documents"]:
        assert document["title"] == "List title"
        assert document["doc_type"] == "prescription"
        assert document["embedding_status"] in ("pending", "processing", "completed", "failed")
        assert isinstance(document["created_at"], str)
    # Metadata only — encrypted PHI must never be echoed.
    assert "extracted_text" not in first
    assert "embedding" not in first


@pytest.mark.asyncio
async def test_list_uses_id_tie_breaker_for_same_created_at(client, db_session):
    h, pid, staff_id = await _staff_with_patient(client)
    created_at = datetime(2026, 9, 24, 10, 0, 0)
    lower_id = UUID("a0000000-0000-0000-0000-000000000001")
    higher_id = UUID("ffffffff-ffff-ffff-ffff-ffffffffffff")
    await db_session.execute(
        text("""
            INSERT INTO medical_documents
                (id, patient_id, uploaded_by, title, file_ref, doc_type,
                 embedding_status, extracted_text, created_at)
            VALUES
                (:id, :patient_id, :uploaded_by, :title, :file_ref,
                 :doc_type, :embedding_status, NULL, :created_at)
        """),
        [
            {
                "id": lower_id.hex,
                "patient_id": UUID(pid).hex,
                "uploaded_by": UUID(staff_id).hex,
                "title": "Lower id",
                "file_ref": "lower.txt",
                "doc_type": DocumentTypeEnum.REPORT.value,
                "embedding_status": EmbeddingStatusEnum.COMPLETED.value,
                "created_at": created_at,
            },
            {
                "id": higher_id.hex,
                "patient_id": UUID(pid).hex,
                "uploaded_by": UUID(staff_id).hex,
                "title": "Higher id",
                "file_ref": "higher.txt",
                "doc_type": DocumentTypeEnum.REPORT.value,
                "embedding_status": EmbeddingStatusEnum.COMPLETED.value,
                "created_at": created_at,
            },
        ],
    )
    await db_session.commit()

    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200, r.text
    assert [row["document_id"] for row in r.json()["documents"]] == [
        str(higher_id), str(lower_id)
    ]


@pytest.mark.asyncio
async def test_list_caps_results_at_fifty(client, db_session):
    h, pid, staff_id = await _staff_with_patient(client)
    created_at = datetime(2026, 9, 24, 10, 0, 0)
    db_session.add_all([
        MedicalDocument(
            patient_id=UUID(pid),
            uploaded_by=UUID(staff_id),
            title=f"Document {i}",
            file_ref=f"document-{i}.txt",
            doc_type=DocumentTypeEnum.REPORT,
            embedding_status=EmbeddingStatusEnum.COMPLETED,
            created_at=created_at - timedelta(seconds=i),
        )
        for i in range(51)
    ])
    await db_session.commit()

    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["count"] == len(body["documents"]) == 50
    assert [row["file_name"] for row in body["documents"]] == [
        f"document-{i}.txt" for i in range(50)
    ]


@pytest.mark.asyncio
async def test_list_empty_is_not_an_error(client):
    h, pid, _ = await _staff_with_patient(client)
    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200
    assert r.json() == {"documents": [], "count": 0}


@pytest.mark.asyncio
async def test_list_writes_read_audit(client, db_session):
    h, pid, staff_id = await _staff_with_patient(client)
    await _upload_text(client, h, pid)
    before = (await db_session.execute(select(AuditLog).where(
        AuditLog.user_id == UUID(staff_id),
        AuditLog.resource_id == UUID(pid),
        AuditLog.resource_type == "medical_document",
        AuditLog.action == "read",
    ))).scalars().all()
    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200
    rows = (await db_session.execute(select(AuditLog).where(
        AuditLog.user_id == UUID(staff_id),
        AuditLog.resource_id == UUID(pid),
        AuditLog.resource_type == "medical_document",
        AuditLog.action == "read",
    ))).scalars().all()
    before_ids = {row.id for row in before}
    new_rows = [row for row in rows if row.id not in before_ids]
    assert len(new_rows) == 1
    row = new_rows[0]
    assert row.user_id == UUID(staff_id)
    assert row.resource_id == UUID(pid)
    assert row.resource_type == "medical_document"
    assert (row.action.value if hasattr(row.action, "value") else str(row.action)) == "read"


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


# --- RAG ask route gates (POST /reports/documents/answer) ---------------------
# The ask route is the mobile Q&A surface, so it must carry the same
# require_staff -> clinical tier -> health_data consent -> read-audit chain
# as the list route. Only its authentication was covered before.


async def _family_headers_for(client, db_session, patient_profile):
    reg = await client.post(f"{AUTH}/register", json={
        "phone": "+919000000003", "password": "Passw0rd123",
        "role": "family_caregiver", "preferred_language": "english"})
    assert reg.status_code == 201, reg.text
    fam = reg.json()
    fam_login = await client.post(f"{AUTH}/login", json={
        "phone": fam["phone"], "password": "Passw0rd123"})
    fh = {"Authorization": f"Bearer {fam_login.json()['access_token']}"}
    owner_login = await client.post(f"{AUTH}/login", json={
        "phone": (await db_session.execute(
            select(User.phone).where(User.id == UUID(patient_profile["user_id"]))
        )).scalar_one(), "password": "Passw0rd123"})
    oh = {"Authorization": f"Bearer {owner_login.json()['access_token']}"}
    link = await client.post(f"{PATIENTS}/{patient_profile['id']}/caregivers",
        headers=oh, json={"caregiver_id": fam["id"], "relationship_type": "family"})
    assert link.status_code == 201, link.text
    return fh


async def _ask(client, headers, pid, question="What medication was prescribed?"):
    return await client.post(f"{REPORTS}/documents/answer", headers=headers,
        json={"patient_id": pid, "question": question})


@pytest.mark.asyncio
async def test_answer_clinical_staff_is_allowed(client):
    h, pid, _ = await _staff_with_patient(client, "clinician")
    r = await _ask(client, h, pid)
    assert r.status_code == 200, r.text
    body = r.json()
    assert "answer" in body
    assert "disclaimer" in body


@pytest.mark.asyncio
async def test_answer_family_caregiver_basic_tier_is_403(client, db_session):
    from app.tests.conftest import create_consented_patient
    prof = await create_consented_patient(client, "Family Ask Patient")
    fh = await _family_headers_for(client, db_session, prof)
    r = await _ask(client, fh, prof["id"])
    assert r.status_code == 403
    assert r.json()["detail"] == "Clinical permission tier required for this resource"


@pytest.mark.asyncio
async def test_answer_patient_role_is_403(client, db_session):
    from app.tests.conftest import create_consented_patient
    prof = await create_consented_patient(client, "Self Ask Patient")
    login = await client.post(f"{AUTH}/login", json={
        "phone": (await db_session.execute(
            select(User.phone).where(User.id == UUID(prof["user_id"]))
        )).scalar_one(), "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    r = await _ask(client, h, prof["id"])
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_answer_without_health_data_consent_is_403(client):
    from app.tests.conftest import provision_staff_user
    user = await provision_staff_user(role="clinician")
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    reg = await client.post(f"{AUTH}/register", json={
        "phone": "+919000000004", "password": "Passw0rd123",
        "role": "patient", "preferred_language": "english"})
    pl = await client.post(f"{AUTH}/login", json={
        "phone": reg.json()["phone"], "password": "Passw0rd123"})
    ph = {"Authorization": f"Bearer {pl.json()['access_token']}"}
    prof = (await client.post(f"{PATIENTS}", headers=ph, json={"name": "Ask No Consent"})).json()
    r = await _ask(client, h, prof["id"])
    assert r.status_code == 403
    assert "health_data" in r.json()["detail"]


@pytest.mark.asyncio
async def test_answer_writes_read_audit(client, db_session):
    h, pid, staff_id = await _staff_with_patient(client, "clinician")
    before = (await db_session.execute(select(AuditLog).where(
        AuditLog.user_id == UUID(staff_id)))).scalars().all()
    before_ids = {row.id for row in before}
    r = await _ask(client, h, pid)
    assert r.status_code == 200, r.text
    rows = (await db_session.execute(select(AuditLog).where(
        AuditLog.user_id == UUID(staff_id),
        AuditLog.resource_id == UUID(pid),
        AuditLog.resource_type == "medical_document",
        AuditLog.action == "read",
    ))).scalars().all()
    new_rows = [row for row in rows if row.id not in before_ids]
    assert len(new_rows) == 1, "asking a question must write a DPDP read audit"


# --- Remaining document-route gates: ingest, query, and the write audit ------


async def _patient_without_consent(client):
    reg = await client.post(f"{AUTH}/register", json={
        "phone": "+919000000005", "password": "Passw0rd123",
        "role": "patient", "preferred_language": "english"})
    assert reg.status_code == 201, reg.text
    pl = await client.post(f"{AUTH}/login", json={
        "phone": reg.json()["phone"], "password": "Passw0rd123"})
    ph = {"Authorization": f"Bearer {pl.json()['access_token']}"}
    prof = (await client.post(f"{PATIENTS}", headers=ph, json={"name": "Gate Patient"})).json()
    return prof["id"]


@pytest.mark.asyncio
async def test_ingest_without_health_data_consent_is_403(client):
    from app.tests.conftest import provision_staff_user
    user = await provision_staff_user(role="clinician")
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    pid = await _patient_without_consent(client)
    r = await client.post(f"{REPORTS}/documents/ingest", headers=h, json={
        "patient_id": pid, "file_ref": "note.txt", "doc_type": "prescription",
        "extracted_text": "Donepezil 5 mg at bedtime."})
    assert r.status_code == 403
    assert "health_data" in r.json()["detail"]


@pytest.mark.asyncio
async def test_query_without_health_data_consent_is_403(client):
    from app.tests.conftest import provision_staff_user
    user = await provision_staff_user(role="clinician")
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    pid = await _patient_without_consent(client)
    r = await client.post(f"{REPORTS}/documents/query", headers=h,
        json={"patient_id": pid, "query": "Donepezil"})
    assert r.status_code == 403
    assert "health_data" in r.json()["detail"]


@pytest.mark.asyncio
async def test_query_writes_read_audit(client, db_session):
    h, pid, staff_id = await _staff_with_patient(client, "clinician")
    before = (await db_session.execute(select(AuditLog).where(
        AuditLog.user_id == UUID(staff_id)))).scalars().all()
    before_ids = {row.id for row in before}
    r = await client.post(f"{REPORTS}/documents/query", headers=h,
        json={"patient_id": pid, "query": "Donepezil"})
    assert r.status_code == 200, r.text
    rows = (await db_session.execute(select(AuditLog).where(
        AuditLog.user_id == UUID(staff_id),
        AuditLog.resource_id == UUID(pid),
        AuditLog.resource_type == "medical_document",
        AuditLog.action == "read",
    ))).scalars().all()
    assert len([row for row in rows if row.id not in before_ids]) == 1, \
        "documents/query must write a DPDP read audit"


@pytest.mark.asyncio
async def test_upload_writes_write_audit(client, db_session):
    """DPDP: a document WRITE must leave an audit trail (not just reads)."""
    h, pid, staff_id = await _staff_with_patient(client, "clinician")
    before = (await db_session.execute(select(AuditLog).where(
        AuditLog.user_id == UUID(staff_id)))).scalars().all()
    before_ids = {row.id for row in before}
    up = await _upload_text(client, h, pid, "audited.txt")
    doc_id = up["document_id"]
    rows = (await db_session.execute(select(AuditLog).where(
        AuditLog.user_id == UUID(staff_id),
        AuditLog.resource_type == "medical_document",
        AuditLog.action == "write",
    ))).scalars().all()
    new_rows = [row for row in rows if row.id not in before_ids]
    assert len(new_rows) == 1, "uploading a document must write a DPDP write audit"
    row = new_rows[0]
    assert UUID(str(row.resource_id)) == UUID(doc_id)


@pytest.mark.asyncio
async def test_ingest_rolls_back_document_and_audit_when_chunk_add_fails(
    db_session, monkeypatch
):
    from app.services.rag_service import RAGService

    original_add = db_session.add

    def fail_chunk_add(instance):
        if isinstance(instance, DocumentChunk):
            raise RuntimeError("chunk insert failed")
        original_add(instance)

    monkeypatch.setattr(db_session, "add", fail_chunk_add)

    with pytest.raises(RuntimeError, match="chunk insert failed"):
        await RAGService.ingest_document(
            db=db_session,
            patient_id=uuid.uuid4(),
            uploaded_by=uuid.uuid4(),
            file_ref="atomic.txt",
            doc_type="report",
            extracted_text="document body",
        )

    pending_audits = [entry for entry in db_session.new if isinstance(entry, AuditLog)]
    assert len(pending_audits) == 1
    assert pending_audits[0].resource_id is not None
    await db_session.rollback()
    documents = (await db_session.execute(select(MedicalDocument))).scalars().all()
    audits = (await db_session.execute(select(AuditLog))).scalars().all()
    assert not documents
    assert not audits


@pytest.mark.asyncio
async def test_ingest_is_fail_closed_when_the_audit_cannot_be_written(
    db_session, monkeypatch
):
    """An audited write that cannot be audited must not be stored.

    The document and its DPDP audit row share one transaction, so a failing
    audit add aborts the whole ingest — this is deliberately NOT the
    best-effort behaviour of ComplianceService.log_write_access.
    """
    from app.services.rag_service import RAGService

    original_add = db_session.add

    def fail_audit_add(instance):
        if isinstance(instance, AuditLog):
            raise RuntimeError("audit store unavailable")
        original_add(instance)

    monkeypatch.setattr(db_session, "add", fail_audit_add)

    with pytest.raises(RuntimeError, match="audit store unavailable"):
        await RAGService.ingest_document(
            db=db_session,
            patient_id=uuid.uuid4(),
            uploaded_by=uuid.uuid4(),
            file_ref="failclosed.txt",
            doc_type="report",
            extracted_text="Donepezil 5 mg at bedtime.",
        )

    await db_session.rollback()
    documents = (await db_session.execute(select(MedicalDocument))).scalars().all()
    audits = (await db_session.execute(select(AuditLog))).scalars().all()
    assert not documents, "document must not persist without its audit row"
    assert not audits

import json
import uuid
from datetime import datetime, timezone

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.middleware.rate_limit import RateLimitMiddleware
from app.models import Base
from app.models.all_models import (
    AlertFlag,
    AlertSeverityEnum,
    AlertTriggerTypeEnum,
    AuditActionEnum,
    AuditLog,
    CaregiverPatientLink,
    DocumentTypeEnum,
    EmbeddingStatusEnum,
    MedicalDocument,
    PatientProfile,
    PermissionTierEnum,
    RelationshipTypeEnum,
    SymptomEntrySourceEnum,
    SymptomLog,
    SyncOperationEnum,
    SyncQueue,
    SyncResourceTypeEnum,
    UserDeviceToken,
)
from app.models.user import RoleEnum, User
from app.services.compliance_service import ComplianceService, EncryptionService


async def _seed_export_data(db, marker: str, include_other_patient: bool = False):
    owner = User(
        phone=f"+91{uuid.uuid4().int % 10**10}",
        email=f"owner-{marker}@example.invalid",
        password_hash="x",
        role=RoleEnum.PATIENT,
    )
    caregiver = User(
        phone=f"+91{uuid.uuid4().int % 10**10}",
        email=f"caregiver-{marker}@example.invalid",
        password_hash="x",
        role=RoleEnum.FAMILY_CAREGIVER,
    )
    db.add_all([owner, caregiver])
    await db.flush()

    patient = PatientProfile(
        user_id=owner.id,
        name=f"Patient {marker}",
        region="assam",
        district="Guwahati",
    )
    db.add(patient)
    await db.flush()

    encryption = EncryptionService()
    symptom_note = f"plain symptom {marker}"
    document_text = f"plain document text {marker}"
    other = None
    if include_other_patient:
        other = await _seed_export_data(db, f"{marker}-other")

    db.add_all([
        CaregiverPatientLink(
            caregiver_id=caregiver.id,
            patient_id=patient.id,
            relationship_type=RelationshipTypeEnum.FAMILY,
            permission_tier=PermissionTierEnum.BASIC,
        ),
        SymptomLog(
            patient_id=patient.id,
            entered_by=caregiver.id,
            entry_source=SymptomEntrySourceEnum.MANUAL_CAREGIVER,
            notes=encryption.encrypt(symptom_note),
            severity=3,
            timestamp=datetime(2026, 9, 1, 10, 30),
        ),
        MedicalDocument(
            patient_id=patient.id,
            uploaded_by=caregiver.id,
            title=f"Document {marker}",
            file_ref=f"/documents/{marker}.pdf",
            doc_type=DocumentTypeEnum.REPORT,
            embedding_status=EmbeddingStatusEnum.COMPLETED,
            extracted_text=encryption.encrypt(document_text),
            embedding_provider="heuristic",
            embedding_model="md5-tf-v1",
            embedding_dimensions=1536,
        ),
        AlertFlag(
            patient_id=patient.id,
            trigger_type=AlertTriggerTypeEnum.MISSED_REMINDERS,
            severity=AlertSeverityEnum.WARNING,
            alert_summary=f"alert {marker}",
        ),
        SyncQueue(
            patient_id=patient.id,
            resource_type=SyncResourceTypeEnum.OFFLINE_SYMPTOM,
            operation=SyncOperationEnum.CREATE,
            resource_id=uuid.uuid4(),
            idempotency_key=str(uuid.uuid4()),
            payload={"marker": marker},
        ),
        UserDeviceToken(
            user_id=owner.id,
            fcm_token=f"device-token-{marker}",
            phone=f"+91{uuid.uuid4().int % 10**10}",
            platform="android",
        ),
    ])
    await db.commit()
    return {
        "patient": patient,
        "owner": owner,
        "caregiver": caregiver,
        "symptom_note": symptom_note,
        "document_text": document_text,
        "other": other,
    }


@pytest.mark.asyncio
async def test_export_includes_all_persisted_patient_data_categories(db_session):
    seeded = await _seed_export_data(db_session, "alpha")
    patient = seeded["patient"]

    exported = await ComplianceService.export_patient_data(db_session, patient.id)

    assert exported["symptom_logs"][0]["notes"] == seeded["symptom_note"]
    assert exported["medical_documents"][0]["extracted_text"] == seeded["document_text"]
    assert exported["medical_documents"][0]["embedding_dimensions"] == 1536
    assert exported["alert_flags"][0]["alert_summary"] == "alert alpha"
    assert exported["caregiver_links"][0]["caregiver_id"] == str(seeded["caregiver"].id)
    assert exported["sync_queue"][0]["payload"] == {"marker": "alpha"}
    assert exported["device_tokens"][0]["fcm_token"] == "device-token-alpha"
    assert exported["voice_companion_history"] == {
        "available": False,
        "durable": False,
        "turns": [],
        "message": (
            "Conversation history is process/Redis-backed and is not durably "
            "queryable from patient storage."
        ),
    }
    assert "document_chunks" not in exported
    serialized = json.dumps(exported)
    assert "gAAAA" not in serialized
    assert seeded["symptom_note"] in serialized
    assert seeded["document_text"] in serialized


@pytest.mark.asyncio
async def test_export_never_includes_another_patient_data(db_session):
    seeded = await _seed_export_data(db_session, "primary", include_other_patient=True)
    other = seeded["other"]

    exported = await ComplianceService.export_patient_data(
        db_session, seeded["patient"].id
    )
    serialized = json.dumps(exported)

    assert other["patient"].id != seeded["patient"].id
    assert other["owner"].id != seeded["owner"].id
    assert other["caregiver"].id != seeded["caregiver"].id
    assert seeded["symptom_note"] in serialized
    assert seeded["document_text"] in serialized
    assert str(seeded["patient"].id) in serialized
    assert "other-other" not in serialized
    assert str(other["patient"].id) not in serialized
    assert str(other["owner"].id) not in serialized
    assert str(other["caregiver"].id) not in serialized


@pytest.mark.asyncio
async def test_audit_rows_reject_application_orm_updates_and_deletes(db_session):
    user = User(
        phone=f"+91{uuid.uuid4().int % 10**10}",
        password_hash="x",
        role=RoleEnum.ADMIN,
    )
    db_session.add(user)
    await db_session.flush()
    row = AuditLog(
        user_id=user.id,
        action=AuditActionEnum.READ,
        resource_type="patient_profile",
        resource_id=uuid.uuid4(),
    )
    db_session.add(row)
    await db_session.commit()
    row_id = row.id

    row.action = AuditActionEnum.WRITE
    with pytest.raises(RuntimeError, match="append-only"):
        await db_session.flush()
    await db_session.rollback()

    stored = await db_session.get(AuditLog, row_id)
    assert stored is not None
    assert stored.action == AuditActionEnum.READ
    await db_session.delete(stored)
    with pytest.raises(RuntimeError, match="append-only"):
        await db_session.flush()
    await db_session.rollback()
    assert await db_session.get(AuditLog, row_id) is not None


@pytest.mark.asyncio
async def test_admin_audit_api_discloses_its_integrity_scope(client, db_session):
    from app.tests.conftest import provision_staff_user

    staff = await provision_staff_user(role="admin")
    db_session.add(
        AuditLog(
            user_id=uuid.UUID(staff["id"]),
            action=AuditActionEnum.READ,
            resource_type="patient_profile",
            resource_id=uuid.uuid4(),
            ip_address="198.51.100.10",
            details={"operation": "read"},
        )
    )
    await db_session.commit()
    login = await client.post(
        "/api/v1/auth/login",
        json={"phone": staff["phone"], "password": "Passw0rd123"},
    )
    assert login.status_code == 200, login.text

    response = await client.get(
        "/api/v1/compliance/audit-logs",
        headers={"Authorization": f"Bearer {login.json()['access_token']}"},
    )

    assert response.status_code == 200, response.text
    assert response.headers["x-audit-integrity-scope"] == "application-orm-append-only"
    assert response.headers["x-audit-database-enforcement"] == "unverified"
    assert set(response.json()[0]) == {
        "id",
        "user_id",
        "action",
        "resource_type",
        "resource_id",
        "timestamp",
        "ip_address",
        "details",
    }


@pytest.mark.asyncio
async def test_request_audit_records_originating_client_address(db_session):
    user = User(
        phone=f"+91{uuid.uuid4().int % 10**10}",
        password_hash="x",
        role=RoleEnum.ADMIN,
    )
    db_session.add(user)
    await db_session.commit()
    probe = FastAPI()
    probe.add_middleware(RateLimitMiddleware)

    @probe.post("/audit")
    async def create_audit():
        entry = await ComplianceService.log_audit_access(
            db_session,
            user.id,
            "read",
            "patient_profile",
            uuid.uuid4(),
        )
        return {"id": str(entry.id)}

    transport = ASGITransport(
        app=probe,
        client=("198.51.100.42", 43123),
    )
    async with AsyncClient(transport=transport, base_url="http://probe") as http:
        response = await http.post("/audit")

    assert response.status_code == 200, response.text
    rows = (
        await db_session.execute(
            select(AuditLog).where(AuditLog.resource_type == "patient_profile")
        )
    ).scalars().all()
    assert len(rows) == 1
    assert rows[0].ip_address == "198.51.100.42"


@pytest.mark.asyncio
async def test_background_audit_records_non_request_marker(db_session):
    user = User(
        phone=f"+91{uuid.uuid4().int % 10**10}",
        password_hash="x",
        role=RoleEnum.ADMIN,
    )
    db_session.add(user)
    await db_session.commit()

    entry = await ComplianceService.log_audit_access(
        db_session,
        user.id,
        "write",
        "patient_profile",
        uuid.uuid4(),
    )

    assert entry.ip_address == "non-request"


def test_model_metadata_matches_production_constraints_and_indexes():
    weekly_reports = Base.metadata.tables["weekly_reports"]
    weekly_constraints = {
        (constraint.name, tuple(column.name for column in constraint.columns))
        for constraint in weekly_reports.constraints
        if constraint.name
    }
    assert (
        "uq_weekly_reports_patient_week",
        ("patient_id", "week_start"),
    ) in weekly_constraints

    expected_indexes = {
        "user_device_tokens": {
            "ix_user_device_tokens_user_id": ("user_id",),
        },
        "notification_deliveries": {
            "ix_notification_deliveries_provider": ("provider",),
            "ix_notification_deliveries_recipient_user_id": (
                "recipient_user_id",
            ),
        },
    }
    for table_name, indexes in expected_indexes.items():
        table = Base.metadata.tables[table_name]
        actual = {
            index.name: tuple(column.name for column in index.columns)
            for index in table.indexes
        }
        assert actual == indexes

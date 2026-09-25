import json
import uuid
from datetime import datetime, timezone

import pytest

from app.models.all_models import (
    AlertFlag,
    AlertSeverityEnum,
    AlertTriggerTypeEnum,
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

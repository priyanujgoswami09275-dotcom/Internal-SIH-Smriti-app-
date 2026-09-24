import uuid

import pytest
from sqlalchemy import select

from app.deps import get_current_user
from app.main import app
from app.models.all_models import (
    AuditActionEnum,
    AuditLog,
    CaregiverPatientLink,
    PatientProfile,
    SymptomLog,
)
from app.models.user import RoleEnum, User
from app.services.sync_service import consume_sync_queue, process_sync_batch


async def _linked_family_actor(db, permission_tier):
    owner = User(password_hash="x", role=RoleEnum.PATIENT)
    actor = User(password_hash="x", role=RoleEnum.FAMILY_CAREGIVER)
    db.add_all([owner, actor])
    await db.flush()
    patient = PatientProfile(user_id=owner.id, name="Audit Export")
    db.add(patient)
    await db.flush()
    link = CaregiverPatientLink(
        caregiver_id=actor.id,
        patient_id=patient.id,
        relationship_type="family",
        permission_tier=permission_tier,
    )
    db.add(link)
    await db.commit()
    app.dependency_overrides[get_current_user] = lambda: actor
    return patient, actor


@pytest.mark.asyncio
async def test_basic_export_writes_read_audit(client, db_session):
    patient, actor = await _linked_family_actor(db_session, "basic")

    response = await client.get(
        f"/api/v1/compliance/patients/{patient.id}/export"
    )

    assert response.status_code == 200, response.text
    audit = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.user_id == actor.id,
                AuditLog.resource_type == "data_export",
            )
        )
    ).scalar_one()
    assert audit.action == AuditActionEnum.READ
    assert audit.resource_id == patient.id
    assert audit.details == {}


@pytest.mark.asyncio
@pytest.mark.parametrize("permission_tier", ["basic", "clinical"])
async def test_export_fails_closed_when_audit_cannot_be_written(
    permission_tier, client, db_session, monkeypatch
):
    patient, _ = await _linked_family_actor(db_session, permission_tier)

    async def fail_commit():
        raise RuntimeError("isolated audit persistence failure")

    monkeypatch.setattr(db_session, "commit", fail_commit)
    response = await client.get(
        f"/api/v1/compliance/patients/{patient.id}/export"
    )

    assert response.status_code == 503
    assert response.json() == {
        "detail": "Export audit unavailable; patient data withheld"
    }


@pytest.mark.asyncio
async def test_sync_materialization_writes_symptom_audit(db_session):
    owner = User(password_hash="x", role=RoleEnum.PATIENT)
    entered_by = User(password_hash="x", role=RoleEnum.ASHA_WORKER)
    db_session.add_all([owner, entered_by])
    await db_session.flush()
    patient = PatientProfile(user_id=owner.id, name="Sync Audit")
    db_session.add(patient)
    await db_session.flush()
    note = "sensitive clinical note"
    await process_sync_batch(
        db_session,
        patient.id,
        [
            {
                "resource_type": "offline_symptom",
                "operation": "create",
                "resource_id": str(uuid.uuid4()),
                "payload": {
                    "entered_by": str(entered_by.id),
                    "notes": note,
                    "source": "manual_asha",
                    "severity": 2,
                },
            }
        ],
    )

    counts = await consume_sync_queue(db_session, patient_id=patient.id)

    assert counts == {"materialized": 1, "acked": 0, "errors": 0}
    symptom = (
        await db_session.execute(
            select(SymptomLog).where(SymptomLog.patient_id == patient.id)
        )
    ).scalar_one()
    audit = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.user_id == entered_by.id,
                AuditLog.resource_type == "symptom_log",
            )
        )
    ).scalar_one()
    assert symptom.entered_by == entered_by.id
    assert audit.action == AuditActionEnum.WRITE
    assert audit.resource_id == symptom.id
    assert audit.details == {
        "resource_type": "offline_symptom",
        "operation": "sync_materialize",
    }
    assert note not in str(audit.details)


@pytest.mark.asyncio
async def test_sync_api_overwrites_spoofed_symptom_author(client, db_session):
    patient, authenticated_actor = await _linked_family_actor(db_session, "basic")
    spoofed_actor = User(password_hash="x", role=RoleEnum.ASHA_WORKER)
    db_session.add(spoofed_actor)
    await db_session.commit()

    response = await client.post(
        "/api/v1/sync",
        json={
            "patient_id": str(patient.id),
            "items": [
                {
                    "resource_type": "offline_symptom",
                    "operation": "create",
                    "resource_id": str(uuid.uuid4()),
                    "payload": {
                        "entered_by": str(spoofed_actor.id),
                        "notes": "sensitive symptom note",
                        "severity": 2,
                    },
                }
            ],
        },
    )

    assert response.status_code == 200, response.text
    counts = await consume_sync_queue(db_session, patient_id=patient.id)
    assert counts == {"materialized": 1, "acked": 0, "errors": 0}
    symptom = (
        await db_session.execute(
            select(SymptomLog).where(SymptomLog.patient_id == patient.id)
        )
    ).scalar_one()
    audits = (
        await db_session.execute(
            select(AuditLog).where(AuditLog.resource_type == "symptom_log")
        )
    ).scalars().all()

    assert len(audits) == 1
    assert audits[0].user_id == authenticated_actor.id
    assert audits[0].action == AuditActionEnum.WRITE
    assert symptom.entered_by == authenticated_actor.id
    assert all(audit.user_id != spoofed_actor.id for audit in audits)

"""Tests for sync outbox semantics + consumer materialization."""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.models.all_models import PatientProfile, SymptomLog, SyncQueue
from app.models.user import RoleEnum, User
from app.services.compliance_service import EncryptionService
from app.services.sync_service import consume_sync_queue, process_sync_batch


async def _patient_and_entered_by(db):
    patient_user = User(phone=f"+91{uuid.uuid4().int % 10**10}", password_hash="x",
                        role=RoleEnum.PATIENT)
    db.add(patient_user)
    await db.flush()
    patient = PatientProfile(user_id=patient_user.id, name="Sync", region="assam")
    db.add(patient)
    await db.flush()
    entered_by = User(phone=f"+91{uuid.uuid4().int % 10**10}", password_hash="x",
                      role=RoleEnum.ASHA_WORKER)
    db.add(entered_by)
    await db.flush()
    return patient, entered_by


@pytest.mark.asyncio
async def test_batch_accepts_into_pending_outbox(db_session):
    patient, _ = await _patient_and_entered_by(db_session)
    pid = patient.id  # snapshot: services commit and expire ORM attrs
    item = {
        "resource_type": "offline_symptom", "operation": "create",
        "resource_id": str(uuid.uuid4()),
        "payload": {"note": "felt dizzy", "severity": 2},
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    res = await process_sync_batch(db_session, pid, [item])
    assert res["synced"] == 1 and res["errors"] == []
    # Accepted but PENDING (synced_at NULL) until the consumer materializes it.
    pending = (
        await db_session.execute(
            select(SyncQueue).where(SyncQueue.patient_id == pid)
        )
    ).scalars().all()
    assert len(pending) == 1
    assert pending[0].synced_at is None


@pytest.mark.asyncio
async def test_consumer_materializes_offline_symptom_encrypted(db_session):
    patient, entered_by = await _patient_and_entered_by(db_session)
    pid, entered_id = patient.id, entered_by.id  # snapshot before commits
    note = "headache in the evening after dinner"
    item = {
        "resource_type": "offline_symptom", "operation": "create",
        "resource_id": str(uuid.uuid4()),
        "payload": {"note": note, "severity": 3, "entered_by": str(entered_id),
                    "source": "manual_asha",
                    "recorded_at": datetime.now(timezone.utc).isoformat()},
    }
    await process_sync_batch(db_session, pid, [item])

    counts = await consume_sync_queue(db_session, patient_id=pid)
    assert counts == {"materialized": 1, "acked": 0, "errors": 0}

    rows = (
        await db_session.execute(
            select(SymptomLog).where(SymptomLog.patient_id == pid)
        )
    ).scalars().all()
    assert len(rows) == 1
    symptom = rows[0]
    # AES-256 at rest: stored ciphertext, decrypts to the original note.
    assert symptom.notes.startswith("gAAAA")  # Fernet token prefix
    assert symptom.notes != note
    assert EncryptionService().decrypt(symptom.notes) == note
    assert symptom.entry_source.value == "manual_asha"
    assert symptom.severity == 3

    # Second pass is a no-op (nothing pending).
    assert await consume_sync_queue(db_session, patient_id=pid) == {
        "materialized": 0, "acked": 0, "errors": 0}


@pytest.mark.asyncio
async def test_consumer_records_error_for_invalid_payload(db_session):
    patient, _ = await _patient_and_entered_by(db_session)
    pid = patient.id  # snapshot before commits
    # Missing "entered_by" -> per-item error, queue does not wedge.
    item = {
        "resource_type": "offline_symptom", "operation": "create",
        "resource_id": str(uuid.uuid4()),
        "payload": {"note": "no entered_by here", "severity": 1},
    }
    await process_sync_batch(db_session, pid, [item])

    counts = await consume_sync_queue(db_session, patient_id=pid)
    assert counts["errors"] == 1 and counts["materialized"] == 0

    row = (
        await db_session.execute(
            select(SyncQueue).where(SyncQueue.patient_id == pid)
        )
    ).scalar_one()
    assert row.synced_at is None  # stays pending so it can be retried
    assert "entered_by" in (row.last_error or "")
    assert row.retry_count == 1

    counts = await consume_sync_queue(db_session, patient_id=pid)
    assert counts["errors"] == 1 and counts["materialized"] == 0

    row = (
        await db_session.execute(
            select(SyncQueue).where(SyncQueue.patient_id == pid)
        )
    ).scalar_one()
    assert row.synced_at is None
    assert row.retry_count == 2


@pytest.mark.asyncio
async def test_consumer_acks_other_resource_types(db_session):
    patient, _ = await _patient_and_entered_by(db_session)
    pid = patient.id  # snapshot before commits
    # A game_session outbox row is acknowledged (replayed via live endpoints).
    item = {
        "resource_type": "game_session", "operation": "create",
        "resource_id": str(uuid.uuid4()), "payload": {"score": 10},
    }
    await process_sync_batch(db_session, pid, [item])
    counts = await consume_sync_queue(db_session, patient_id=pid)
    assert counts == {"materialized": 0, "acked": 1, "errors": 0}

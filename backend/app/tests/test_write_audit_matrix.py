import uuid
from datetime import datetime, timezone
from uuid import UUID

import pytest
from sqlalchemy import select

from app.models.all_models import (
    AlertFlag,
    AlertSeverityEnum,
    AlertTriggerTypeEnum,
    AuditLog,
    ReminderEvent,
    ReminderSchedule,
    ReminderStatusEnum,
    ReminderTypeEnum,
)
from app.tests.conftest import create_consented_patient, provision_staff_user

AUTH = "/api/v1/auth"
REMINDERS = "/api/v1/reminders"
DASHBOARD = "/api/v1/dashboard"


async def _staff_and_patient(client):
    staff = await provision_staff_user(role="clinician")
    login = await client.post(f"{AUTH}/login", json={
        "phone": staff["phone"],
        "password": "Passw0rd123",
    })
    assert login.status_code == 200, login.text
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    patient = await create_consented_patient(client, "Write Audit Patient")
    return headers, UUID(staff["id"]), patient["id"]


async def _audit_ids(db_session, user_id):
    rows = (await db_session.execute(
        select(AuditLog.id).where(AuditLog.user_id == user_id)
    )).scalars().all()
    return set(rows)


async def _assert_single_write(
    db_session,
    before_ids,
    user_id,
    resource_type,
    resource_id,
    expected_details,
):
    rows = (await db_session.execute(
        select(AuditLog).where(AuditLog.user_id == user_id)
    )).scalars().all()
    new_rows = [row for row in rows if row.id not in before_ids]
    assert len(new_rows) == 1
    row = new_rows[0]
    action = row.action.value if hasattr(row.action, "value") else str(row.action)
    assert action == "write"
    assert row.resource_type == resource_type
    assert row.user_id == user_id
    assert row.resource_id == resource_id
    assert row.details == expected_details


@pytest.mark.asyncio
async def test_create_schedule_writes_audit(client, db_session):
    headers, staff_id, patient_id = await _staff_and_patient(client)
    before_ids = await _audit_ids(db_session, staff_id)

    response = await client.post(f"{REMINDERS}/schedules", headers=headers, json={
        "patient_id": patient_id,
        "reminder_type": "medicine",
        "cadence": "08:00",
    })
    assert response.status_code == 200, response.text
    schedule_id = UUID(response.json()["id"])

    await _assert_single_write(
        db_session,
        before_ids,
        staff_id,
        "reminder_schedule",
        schedule_id,
        {"patient_id": patient_id, "is_active": True},
    )


@pytest.mark.asyncio
async def test_deactivate_schedule_writes_audit(client, db_session):
    headers, staff_id, patient_id = await _staff_and_patient(client)
    schedule = ReminderSchedule(
        id=uuid.uuid4(),
        patient_id=UUID(patient_id),
        reminder_type=ReminderTypeEnum.MEDICINE,
        cadence="08:00",
        created_by=staff_id,
        is_active=True,
        created_at=datetime.now(timezone.utc),
    )
    db_session.add(schedule)
    await db_session.commit()
    before_ids = await _audit_ids(db_session, staff_id)

    response = await client.delete(
        f"{REMINDERS}/schedules/{schedule.id}", headers=headers
    )
    assert response.status_code == 200, response.text

    await _assert_single_write(
        db_session,
        before_ids,
        staff_id,
        "reminder_schedule",
        schedule.id,
        {"patient_id": patient_id, "is_active": False},
    )


@pytest.mark.asyncio
async def test_acknowledge_event_writes_audit(client, db_session):
    headers, staff_id, patient_id = await _staff_and_patient(client)
    schedule = ReminderSchedule(
        id=uuid.uuid4(),
        patient_id=UUID(patient_id),
        reminder_type=ReminderTypeEnum.MEDICINE,
        cadence="08:00",
        created_by=staff_id,
        is_active=True,
        created_at=datetime.now(timezone.utc),
    )
    event = ReminderEvent(
        id=uuid.uuid4(),
        schedule_id=schedule.id,
        patient_id=UUID(patient_id),
        scheduled_at=datetime.now(timezone.utc),
        delivered_at=datetime.now(timezone.utc),
        status=ReminderStatusEnum.PENDING,
        created_at=datetime.now(timezone.utc),
    )
    db_session.add_all([schedule, event])
    await db_session.commit()
    before_ids = await _audit_ids(db_session, staff_id)

    response = await client.post(
        f"{REMINDERS}/events/{event.id}/acknowledge",
        headers=headers,
        json={"method": "button"},
    )
    assert response.status_code == 200, response.text

    await _assert_single_write(
        db_session,
        before_ids,
        staff_id,
        "reminder_event",
        event.id,
        {"patient_id": patient_id, "status": "acknowledged"},
    )


@pytest.mark.asyncio
async def test_acknowledge_alert_writes_audit(client, db_session):
    headers, staff_id, patient_id = await _staff_and_patient(client)
    alert = AlertFlag(
        id=uuid.uuid4(),
        patient_id=UUID(patient_id),
        trigger_type=AlertTriggerTypeEnum.MISSED_REMINDERS,
        severity=AlertSeverityEnum.WARNING,
    )
    db_session.add(alert)
    await db_session.commit()
    before_ids = await _audit_ids(db_session, staff_id)

    response = await client.post(
        f"{DASHBOARD}/alerts/{alert.id}/acknowledge", headers=headers
    )
    assert response.status_code == 200, response.text

    await _assert_single_write(
        db_session,
        before_ids,
        staff_id,
        "alert",
        alert.id,
        {"patient_id": patient_id, "acknowledged": True},
    )

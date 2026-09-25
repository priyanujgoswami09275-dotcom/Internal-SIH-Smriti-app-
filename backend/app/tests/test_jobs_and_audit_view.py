"""Tests for background jobs (escalation scan) + admin audit-log endpoint."""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.jobs import escalation_scan
from app.models.all_models import (
    AlertFlag,
    CaregiverPatientLink,
    PatientProfile,
    ReminderEvent,
    ReminderSchedule,
    ReminderStatusEnum,
    ReminderTypeEnum,
)
from app.models.user import RoleEnum, User

AUTH = "/api/v1/auth"
COMPLIANCE = "/api/v1/compliance"


async def _seed_pending_patient(db, minutes_old=15):
    """Patient with an unacknowledged reminder older than 10 minutes."""
    patient_user = User(phone=f"+91{uuid.uuid4().int % 10**10}", password_hash="x",
                        role=RoleEnum.PATIENT)
    db.add(patient_user)
    await db.flush()
    patient = PatientProfile(user_id=patient_user.id, name="Escalate Me", region="assam")
    db.add(patient)
    await db.flush()

    caregiver = User(phone=f"+91{uuid.uuid4().int % 10**10}", password_hash="x",
                     role=RoleEnum.FAMILY_CAREGIVER)
    db.add(caregiver)
    await db.flush()
    db.add(CaregiverPatientLink(caregiver_id=caregiver.id, patient_id=patient.id,
                                relationship_type="family", is_active=True))

    schedule = ReminderSchedule(patient_id=patient.id, reminder_type=ReminderTypeEnum.MEDICINE,
                                cadence="08:00", created_by=caregiver.id)
    db.add(schedule)
    await db.flush()
    db.add(ReminderEvent(patient_id=patient.id, schedule_id=schedule.id,
                         scheduled_at=datetime.now(timezone.utc) - timedelta(minutes=minutes_old),
                         status=ReminderStatusEnum.PENDING))
    await db.flush()
    return patient, caregiver


@pytest.mark.asyncio
async def test_escalation_scan_escalates_stale_pending(db_session):
    patient, _ = await _seed_pending_patient(db_session)
    result = await escalation_scan(db_session)
    assert result["patients_scanned"] >= 1
    assert result["escalated"] >= 1

    events = (await db_session.execute(
        select(ReminderEvent).where(ReminderEvent.patient_id == patient.id)
    )).scalars().all()
    assert events and all(e.status == ReminderStatusEnum.ESCALATED for e in events)


@pytest.mark.asyncio
async def test_escalation_scan_noop_when_nothing_stale(db_session):
    patient, _ = await _seed_pending_patient(db_session, minutes_old=1)
    result = await escalation_scan(db_session)
    assert result["patients_scanned"] == 0
    events = (await db_session.execute(
        select(ReminderEvent).where(ReminderEvent.patient_id == patient.id)
    )).scalars().all()
    assert events[0].status == ReminderStatusEnum.PENDING


@pytest.mark.asyncio
async def test_escalation_scan_raises_alert_after_three_misses(db_session):
    """3 unresolved reminders of one type in 7 days -> AlertFlag + notification."""
    patient, caregiver = await _seed_pending_patient(db_session)
    from sqlalchemy import func

    # Fabricate two more escalated events within 7 days so the scan sees 3.
    sched = (await db_session.execute(
        select(ReminderSchedule).where(ReminderSchedule.patient_id == patient.id)
    )).scalar_one()
    for mins in (50, 100):
        db_session.add(ReminderEvent(patient_id=patient.id, schedule_id=sched.id,
                                     scheduled_at=datetime.now(timezone.utc)
                                     - timedelta(minutes=mins),
                                     status=ReminderStatusEnum.ESCALATED))
    await db_session.flush()

    result = await escalation_scan(db_session)
    assert result["alerts_created"] >= 1
    assert result["recipients_resolved"] >= 1
    assert result["notified"] == 0
    assert result["delivery_state"] == "not_configured"
    flags = (await db_session.execute(
        select(AlertFlag).where(AlertFlag.patient_id == patient.id)
    )).scalars().all()
    assert len(flags) >= 1
    assert caregiver.id is not None


async def _register_and_login(client, phone, role="patient"):
    await client.post(f"{AUTH}/register", json={
        "phone": phone, "email": f"{uuid.uuid4().hex[:8]}@x.in",
        "password": "Passw0rd123", "role": role})
    r = await client.post(f"{AUTH}/login", json={"phone": phone, "password": "Passw0rd123"})
    assert r.status_code == 200
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.mark.asyncio
async def test_admin_audit_log_listing(client, db_session):
    """Only admins may list the audit trail; rows are returned newest-first."""
    # Produce an audited read first.
    pat = await _register_and_login(client, f"+91{uuid.uuid4().int % 10**10}")
    ph = await _register_and_login(client, f"+91{uuid.uuid4().int % 10**10}")
    profile = (await client.post("/api/v1/patients", headers=pat,
                                 json={"name": "Audited", "region": "assam"})).json()
    await client.get(f"/api/v1/patients/{profile['id']}", headers=ph)  # 403 -> no audit? actually patient cross-read audit only logs on success
    # allowed read that logs: the owner reads own profile
    await client.get(f"/api/v1/patients/{profile['id']}", headers=pat)
    del ph

    # non-admin cannot list
    resp = await client.get(f"{COMPLIANCE}/audit-logs", headers=pat)
    assert resp.status_code == 403

    from app.tests.conftest import provision_staff_user

    user = await provision_staff_user(role="admin")
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    assert login.status_code == 200, login.text
    admin = {"Authorization": f"Bearer {login.json()['access_token']}"}
    resp = await client.get(f"{COMPLIANCE}/audit-logs?limit=50", headers=admin)
    assert resp.status_code == 200, resp.text
    rows = resp.json()
    assert len(rows) >= 1
    assert rows[0]["resource_type"] == "patient_profile"
    assert rows[0]["action"] == "read"
    # filter by resource_type
    resp2 = await client.get(
        f"{COMPLIANCE}/audit-logs?resource_type=patient_profile", headers=admin)
    assert all(r["resource_type"] == "patient_profile" for r in resp2.json())

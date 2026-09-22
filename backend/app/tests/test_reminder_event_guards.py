"""Wave 3C guards — reminder event schedule cross-check + list limit cap.

POST /reminders/events must reject unknown schedules (404) and schedules
belonging to a different patient (422) instead of storing orphan rows.
GET /reminders/patients/{id}/events caps `limit` at 500 like the compliance
audit endpoint (backend/app/routes/compliance.py:102).
"""
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import select

from app.models.all_models import ReminderEvent

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
REMINDERS = "/api/v1/reminders"


async def _register(client, phone, role="patient"):
    r = await client.post(f"{AUTH}/register", json={
        "phone": phone, "email": f"{uuid.uuid4().hex[:8]}@test.in",
        "password": "Passw0rd123", "role": role, "preferred_language": "english"})
    assert r.status_code == 201, r.text
    return r.json()


async def _login(client, phone):
    r = await client.post(f"{AUTH}/login", json={"phone": phone, "password": "Passw0rd123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


async def _patient(client, headers, name):
    r = await client.post(PATIENTS, json={"name": name, "region": "assam"}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()


async def _uid(client, headers):
    r = await client.get(f"{AUTH}/me", headers=headers)
    assert r.status_code == 200
    return r.json()["id"]


async def _link_caregiver(client, patient_headers, patient_id, caregiver_uid):
    r = await client.post(f"{PATIENTS}/{patient_id}/caregivers", headers=patient_headers, json={
        "caregiver_id": caregiver_uid, "relationship_type": "family"})
    assert r.status_code == 201, r.text


def _event_body(schedule_id, patient_id):
    return {
        "schedule_id": str(schedule_id),
        "patient_id": str(patient_id),
        "scheduled_at": "2026-09-20T08:00:00+05:30",
    }


@pytest.mark.asyncio
async def test_record_event_unknown_schedule_404(client, db_session):
    """Unknown schedule_id is a 404 and stores nothing."""
    p = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h = await _login(client, p["phone"])
    prof = await _patient(client, h, "Orphan Check")

    r = await client.post(f"{REMINDERS}/events", headers=h,
                          json=_event_body(uuid.uuid4(), prof["id"]))
    assert r.status_code == 404, r.text
    assert "Schedule not found" in r.json()["detail"]
    rows = (await db_session.execute(
        select(ReminderEvent).where(ReminderEvent.patient_id == uuid.UUID(prof["id"]))
    )).scalars().all()
    assert rows == []


@pytest.mark.asyncio
async def test_record_event_cross_patient_schedule_422(client, db_session):
    """A schedule owned by patient B cannot be recorded against patient A."""
    pa = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    pb = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    cg = await _register(client, f"+91{uuid.uuid4().int % 10**10}", role="family_caregiver")
    ha = await _login(client, pa["phone"])
    hb = await _login(client, pb["phone"])
    hc = await _login(client, cg["phone"])
    prof_a = await _patient(client, ha, "Patient A")
    prof_b = await _patient(client, hb, "Patient B")
    cg_uid = await _uid(client, hc)
    # Caregiver linked to B only: may create schedules for B, not A.
    await _link_caregiver(client, hb, prof_b["id"], cg_uid)

    r = await client.post(f"{REMINDERS}/schedules", headers=hc, json={
        "patient_id": prof_b["id"], "reminder_type": "medicine", "cadence": "08:00"})
    assert r.status_code == 200, r.text
    sched_b = r.json()

    # Owner of A (has access to A) posts B's schedule under A's id.
    r = await client.post(f"{REMINDERS}/events", headers=ha,
                          json=_event_body(sched_b["id"], prof_a["id"]))
    assert r.status_code == 422, r.text
    assert "does not belong" in r.json()["detail"]
    rows = (await db_session.execute(
        select(ReminderEvent).where(ReminderEvent.patient_id == uuid.UUID(prof_a["id"]))
    )).scalars().all()
    assert rows == []


@pytest.mark.asyncio
async def test_record_event_happy_path_still_works(client, db_session):
    """Linked caregiver creates a schedule; owner records an event against it."""
    p = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    cg = await _register(client, f"+91{uuid.uuid4().int % 10**10}", role="family_caregiver")
    hp, hc = await _login(client, p["phone"]), await _login(client, cg["phone"])
    prof = await _patient(client, hp, "Happy Path")
    await _link_caregiver(client, hp, prof["id"], await _uid(client, hc))

    r = await client.post(f"{REMINDERS}/schedules", headers=hc, json={
        "patient_id": prof["id"], "reminder_type": "water", "cadence": "08:00"})
    assert r.status_code == 200, r.text
    sched = r.json()

    r = await client.post(f"{REMINDERS}/events", headers=hp,
                          json=_event_body(sched["id"], prof["id"]))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["schedule_id"] == sched["id"]
    assert body["patient_id"] == prof["id"]
    assert body["status"] == "pending"


@pytest.mark.asyncio
async def test_patient_events_limit_capped_at_500(client, db_session):
    """limit=99999999 is clamped to 500 (compliance endpoint precedent)."""
    p = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    h = await _login(client, p["phone"])
    prof = await _patient(client, h, "Cap Check")
    pid = uuid.UUID(prof["id"])
    now = datetime.now(timezone.utc)
    db_session.add_all(
        ReminderEvent(
            id=uuid.uuid4(),
            schedule_id=uuid.uuid4(),
            patient_id=pid,
            scheduled_at=now,
            delivered_at=now,
            status="pending",
            created_at=now,
        )
        for _ in range(505)
    )
    await db_session.commit()

    r = await client.get(f"{REMINDERS}/patients/{prof['id']}/events",
                         params={"limit": 99999999}, headers=h)
    assert r.status_code == 200, r.text
    assert len(r.json()) == 500

    r = await client.get(f"{REMINDERS}/patients/{prof['id']}/events",
                         params={"limit": 0}, headers=h)
    assert r.status_code == 200, r.text
    assert len(r.json()) == 1

"""Reliability regressions for reminder generation, cadence, and notifications."""
import asyncio
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Any

import pytest
from sqlalchemy import select

from app.models.all_models import (
    AlertFlag,
    AlertSeverityEnum,
    AlertTriggerTypeEnum,
    CaregiverPatientLink,
    NotificationDelivery,
    NotificationDeliveryStatusEnum,
    PatientProfile,
    RelationshipTypeEnum,
    ReminderEvent,
    ReminderSchedule,
    ReminderStatusEnum,
    ReminderTypeEnum,
)
from app.models.user import RoleEnum, User
from app.services.alert_engine import AlertEngine
from app.services.notification_service import notify_escalation_results
from app.services.reminder_service import ReminderService
from app.tests.conftest import create_consented_patient, provision_staff_user

AUTH = "/api/v1/auth"
REMINDERS = "/api/v1/reminders"


class _CoordinatedSession:
    def __init__(
        self,
        session,
        barrier: asyncio.Barrier,
        statement_fragment: str,
        transaction_lock: asyncio.Lock,
    ):
        self._session = session
        self._barrier = barrier
        self._statement_fragment = statement_fragment
        self._transaction_lock = transaction_lock
        self._coordinated = False

    def __getattr__(self, name):
        return getattr(self._session, name)

    async def execute(self, statement, *args, **kwargs):
        result = await self._session.execute(statement, *args, **kwargs)
        if not self._coordinated and self._statement_fragment in str(statement):
            self._coordinated = True
            await self._barrier.wait()
        return result

    async def commit(self):
        async with self._transaction_lock:
            await self._session.commit()

    @asynccontextmanager
    async def begin_nested(self):
        async with self._transaction_lock:
            async with self._session.begin_nested():
                yield


async def _make_patient(db, name: str) -> tuple[PatientProfile, User]:
    user = User(
        phone=f"+91{uuid.uuid4().int % 10**10}",
        password_hash="x",
        role=RoleEnum.PATIENT,
    )
    db.add(user)
    await db.flush()
    patient = PatientProfile(user_id=user.id, name=name, region="assam")
    db.add(patient)
    await db.flush()
    return patient, user


async def _staff_headers(client) -> dict[str, str]:
    staff = await provision_staff_user(role="clinician")
    response = await client.post(
        f"{AUTH}/login",
        json={"phone": staff["phone"], "password": "Passw0rd123"},
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


@pytest.mark.asyncio
async def test_concurrent_generation_creates_one_event_for_occurrence(db_session):
    patient, user = await _make_patient(db_session, "Concurrent Reminder")
    db_session.add(
        ReminderSchedule(
            patient_id=patient.id,
            reminder_type=ReminderTypeEnum.MEDICINE,
            cadence="daily@08:00",
            created_by=user.id,
            is_active=True,
        )
    )
    await db_session.commit()

    now = datetime(2026, 1, 15, 12, 0, tzinfo=timezone.utc)
    barrier = asyncio.Barrier(2)
    transaction_lock = asyncio.Lock()
    first = _CoordinatedSession(
        db_session, barrier, "FROM reminder_events", transaction_lock
    )
    second = _CoordinatedSession(
        db_session, barrier, "FROM reminder_events", transaction_lock
    )

    await asyncio.gather(
        ReminderService.generate_due_events_for_all(first, now=now),
        ReminderService.generate_due_events_for_all(second, now=now),
    )

    rows = (
        await db_session.execute(
            select(ReminderEvent).where(ReminderEvent.patient_id == patient.id)
        )
    ).scalars().all()
    assert len(rows) == 1
    assert rows[0].scheduled_at.minute == 30
    assert rows[0].scheduled_at.hour == 2


@pytest.mark.asyncio
async def test_concurrent_duplicate_alert_condition_creates_one_alert(db_session):
    patient, _ = await _make_patient(db_session, "Concurrent Alert")
    await db_session.commit()
    now = datetime(2026, 1, 15, 12, 0, tzinfo=timezone.utc)
    barrier = asyncio.Barrier(2)
    transaction_lock = asyncio.Lock()
    first = _CoordinatedSession(
        db_session, barrier, "FROM alert_flags", transaction_lock
    )
    second = _CoordinatedSession(
        db_session, barrier, "FROM alert_flags", transaction_lock
    )

    async def raise_alert(session) -> AlertFlag | None:
        return await AlertEngine._raise_alert(
            session,
            patient.id,
            AlertTriggerTypeEnum.COGNITIVE_SCORE_DIP,
            AlertSeverityEnum.WARNING,
            "Accuracy dropped",
            {"drop_pct": 25},
            now,
        )

    alerts = await asyncio.gather(raise_alert(first), raise_alert(second))
    await db_session.commit()

    rows = (
        await db_session.execute(
            select(AlertFlag).where(AlertFlag.patient_id == patient.id)
        )
    ).scalars().all()
    assert sum(alert is not None for alert in alerts) == 1
    assert len(rows) == 1


@pytest.mark.asyncio
async def test_invalid_cadence_is_rejected_with_grammar(client):
    headers = await _staff_headers(client)
    patient = await create_consented_patient(client, "Invalid Cadence")

    response = await client.post(
        f"{REMINDERS}/schedules",
        headers=headers,
        json={
            "patient_id": patient["id"],
            "reminder_type": "medicine",
            "cadence": "every morning after breakfast",
        },
    )

    assert response.status_code == 422, response.text
    detail = str(response.json()["detail"])
    assert "Invalid cadence" in detail
    assert "daily|everyday|every day" in detail
    assert "HH:MM" in detail
    assert "AM|PM Daily" in detail


@pytest.mark.asyncio
async def test_valid_cadence_grammar_still_generates(client, db_session):
    headers = await _staff_headers(client)
    patient = await create_consented_patient(client, "Valid Cadence")
    cadences = [
        "DAILY@08:00",
        "08:00,20:00;08:00",
        "everyday:08:00",
        "every day at 08:00",
        "08:00 AM Daily",
    ]

    for cadence in cadences:
        response = await client.post(
            f"{REMINDERS}/schedules",
            headers=headers,
            json={
                "patient_id": patient["id"],
                "reminder_type": "water",
                "cadence": cadence,
            },
        )
        assert response.status_code == 200, (cadence, response.text)

    now = datetime(2026, 1, 15, 12, 0, tzinfo=timezone.utc)
    result = await ReminderService.generate_due_events_for_all(db_session, now=now)

    assert result["events_created"] == len(cadences)
    rows = (
        await db_session.execute(
            select(ReminderEvent).where(
                ReminderEvent.patient_id == uuid.UUID(patient["id"])
            )
        )
    ).scalars().all()
    assert len(rows) == len(cadences)
    assert {row.scheduled_at.hour for row in rows} == {2}
    assert {row.scheduled_at.minute for row in rows} == {30}


@pytest.mark.asyncio
@pytest.mark.parametrize("provider_name", ["console", "fcm"])
async def test_no_real_transport_reports_logged_only(
    client, db_session, monkeypatch, provider_name
):
    from app.config import settings

    monkeypatch.setattr(settings, "NOTIFICATION_PROVIDER", provider_name)
    headers = await _staff_headers(client)
    patient_payload = await create_consented_patient(client, f"No Transport {provider_name}")
    patient_id = uuid.UUID(patient_payload["id"])
    patient = await db_session.get(PatientProfile, patient_id)
    schedule = ReminderSchedule(
        patient_id=patient.id,
        reminder_type=ReminderTypeEnum.MEDICINE,
        cadence="08:00",
        created_by=uuid.UUID(headers.get("x-test-user-id", str(uuid.uuid4()))),
        is_active=True,
    )
    staff = (
        await db_session.execute(
            select(User).where(User.role == RoleEnum.CLINICIAN)
        )
    ).scalars().first()
    schedule.created_by = staff.id
    db_session.add(schedule)
    caregiver = User(
        phone=f"+91{uuid.uuid4().int % 10**10}",
        password_hash="x",
        role=RoleEnum.FAMILY_CAREGIVER,
    )
    db_session.add(caregiver)
    await db_session.flush()
    db_session.add(
        CaregiverPatientLink(
            caregiver_id=caregiver.id,
            patient_id=patient.id,
            relationship_type=RelationshipTypeEnum.FAMILY,
            is_active=True,
        )
    )
    now = datetime.now(timezone.utc)
    for minutes in (180, 240, 300):
        db_session.add(
            ReminderEvent(
                patient_id=patient.id,
                schedule_id=schedule.id,
                scheduled_at=now - timedelta(minutes=minutes),
                status=ReminderStatusEnum.MISSED,
            )
        )
    await db_session.commit()

    response = await client.post(
        f"{REMINDERS}/patients/{patient.id}/evaluate-escalations", headers=headers
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["delivery_state"] == "not_configured"
    assert "not configured" in body["delivery_message"].lower()
    assert "logged only" in body["delivery_message"].lower()
    assert body["recipients_resolved"] == 1
    assert body["confirmed_deliveries"] == 0
    assert body["notified_recipients"] == 0


@pytest.mark.asyncio
async def test_manual_escalation_uses_job_reprompt_dispatch_with_session(
    client, db_session, monkeypatch
):
    import app.routes.reminders as reminder_routes

    headers = await _staff_headers(client)
    patient_payload = await create_consented_patient(client, "Manual Reprompt")
    patient_id = uuid.UUID(patient_payload["id"])
    staff = (
        await db_session.execute(
            select(User).where(User.role == RoleEnum.CLINICIAN)
        )
    ).scalars().first()
    schedule = ReminderSchedule(
        patient_id=patient_id,
        reminder_type=ReminderTypeEnum.MEDICINE,
        cadence="08:00",
        created_by=staff.id,
        is_active=True,
    )
    db_session.add(schedule)
    await db_session.flush()
    db_session.add(
        ReminderEvent(
            patient_id=patient_id,
            schedule_id=schedule.id,
            scheduled_at=datetime.now(timezone.utc) - timedelta(minutes=15),
            status=ReminderStatusEnum.PENDING,
        )
    )
    await db_session.commit()
    observed: list[dict[str, Any]] = []

    async def fake_reprompts(db, patient_id_arg, result, provider=None):
        observed.append(
            {
                "same_session": db is db_session,
                "patient_id": patient_id_arg,
                "events": result["reprompt_events"],
                "has_provider": provider is not None,
            }
        )
        return {
            "delivery_state": "not_configured",
            "delivery_message": "Notification transport is not configured; logged only.",
            "recipients_resolved": 1,
            "confirmed_deliveries": 0,
        }

    monkeypatch.setattr(reminder_routes, "notify_reprompts", fake_reprompts, raising=False)

    response = await client.post(
        f"{REMINDERS}/patients/{patient_id}/evaluate-escalations", headers=headers
    )

    assert response.status_code == 200, response.text
    assert len(observed) == 1
    assert observed[0]["same_session"] is True
    assert observed[0]["patient_id"] == patient_id
    assert len(observed[0]["events"]) == 1
    assert observed[0]["has_provider"] is True
    body = response.json()
    assert body["reprompt_delivery_state"] == "not_configured"
    assert body["reprompt_confirmed_deliveries"] == 0


@pytest.mark.asyncio
async def test_provider_with_db_session_writes_delivery_audit(
    db_session, monkeypatch
):
    from app.config import settings

    monkeypatch.setattr(settings, "NOTIFICATION_PROVIDER", "fcm")
    patient, _ = await _make_patient(db_session, "Audit Delivery")
    caregiver = User(
        phone=f"+91{uuid.uuid4().int % 10**10}",
        password_hash="x",
        role=RoleEnum.FAMILY_CAREGIVER,
    )
    db_session.add(caregiver)
    await db_session.flush()
    db_session.add(
        CaregiverPatientLink(
            caregiver_id=caregiver.id,
            patient_id=patient.id,
            relationship_type=RelationshipTypeEnum.FAMILY,
            is_active=True,
        )
    )
    alert = AlertFlag(
        patient_id=patient.id,
        trigger_type=AlertTriggerTypeEnum.MISSED_REMINDERS,
        severity=AlertSeverityEnum.CRITICAL,
        alert_summary="Three medicine reminders missed",
    )
    db_session.add(alert)
    await db_session.commit()

    result = await notify_escalation_results(
        db_session, patient.id, {"alerts": [alert]}
    )

    assert result["delivery_state"] == "not_configured"
    assert result["confirmed_deliveries"] == 0
    rows = (await db_session.execute(select(NotificationDelivery))).scalars().all()
    assert len(rows) == 1
    assert rows[0].recipient_user_id == caregiver.id
    assert rows[0].status == NotificationDeliveryStatusEnum.FAILED

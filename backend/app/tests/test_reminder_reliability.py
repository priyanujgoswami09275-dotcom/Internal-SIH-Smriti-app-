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

"""P1 reminder engine — cadence parsing, due-event generation, MISSED
transition, and the 10-minute reprompt fan-out."""
import uuid
from datetime import datetime, time as dtime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.config import settings
from app.models.all_models import (
    PatientProfile, ReminderEvent, ReminderSchedule,
    ReminderStatusEnum, ReminderTypeEnum,
)
from app.models.user import RoleEnum, User
from app.services.reminder_service import ReminderService
from app.services.notification_service import notify_reprompts, ConsoleNotificationProvider


# ---------- cadence parsing ----------


def test_parse_cadence_variants():
    assert ReminderService.parse_cadence("08:00") == [dtime(8, 0)]
    assert ReminderService.parse_cadence("daily@08:00") == [dtime(8, 0)]
    assert ReminderService.parse_cadence("08:00,20:00") == [dtime(8, 0), dtime(20, 0)]
    assert ReminderService.parse_cadence("daily@20:00,08:00") == [dtime(8, 0), dtime(20, 0)]
    assert ReminderService.parse_cadence("08:00 AM Daily") == [dtime(8, 0)]
    with pytest.raises(ValueError, match="Invalid cadence"):
        ReminderService.parse_cadence("every morning after breakfast")
    with pytest.raises(ValueError, match="Invalid cadence"):
        ReminderService.parse_cadence("")
    with pytest.raises(ValueError, match="Invalid cadence"):
        ReminderService.parse_cadence("25:99,09:30")
    with pytest.raises(ValueError, match="Invalid cadence"):
        ReminderService.parse_cadence("08:00 Daily")
    with pytest.raises(ValueError, match="Invalid cadence"):
        ReminderService.parse_cadence("08:00 AM")


# ---------- generation ----------


async def _make_patient(db) -> PatientProfile:
    u = User(phone=f"+91{uuid.uuid4().int % 10**10}", password_hash="x", role=RoleEnum.PATIENT)
    db.add(u)
    await db.flush()
    p = PatientProfile(user_id=u.id, name="Gen Patient", region="assam")
    db.add(p)
    await db.flush()
    return p, u


@pytest.mark.asyncio
async def test_generation_creates_due_events_and_is_idempotent(db_session):
    patient, user = await _make_patient(db_session)
    # A cadence of 00:01 is always already "due" earlier today (any tz).
    db_session.add(ReminderSchedule(
        patient_id=patient.id, reminder_type=ReminderTypeEnum.MEDICINE,
        cadence="00:01", created_by=user.id, is_active=True))
    await db_session.commit()

    first = await ReminderService.generate_due_events_for_all(db_session)
    assert first["events_created"] == 1

    events = (await db_session.execute(
        select(ReminderEvent).where(ReminderEvent.patient_id == patient.id)
    )).scalars().all()
    assert len(events) == 1
    assert events[0].status == ReminderStatusEnum.PENDING

    # Second run same day -> no duplicates.
    second = await ReminderService.generate_due_events_for_all(db_session)
    assert second["events_created"] == 0
    events = (await db_session.execute(
        select(ReminderEvent).where(ReminderEvent.patient_id == patient.id)
    )).scalars().all()
    assert len(events) == 1


@pytest.mark.asyncio
async def test_generation_skips_future_and_freetext(db_session):
    patient, user = await _make_patient(db_session)
    # 23:59 is (almost always) still in the future today -> not generated.
    db_session.add(ReminderSchedule(
        patient_id=patient.id, reminder_type=ReminderTypeEnum.WATER,
        cadence="23:59", created_by=user.id, is_active=True))
    # free-text cadence -> never generates
    db_session.add(ReminderSchedule(
        patient_id=patient.id, reminder_type=ReminderTypeEnum.FOOD,
        cadence="after lunch", created_by=user.id, is_active=True))
    await db_session.commit()

    # Pin "now" to 12:00 UTC so 23:59 is unambiguously in the future.
    noon = datetime.now(timezone.utc).replace(hour=12, minute=0, second=0, microsecond=0)
    res = await ReminderService.generate_due_events_for_all(db_session, now=noon)
    assert res["events_created"] == 0


# ---------- MISSED transition + reprompt ----------


@pytest.mark.asyncio
async def test_escalate_then_missed_and_reprompt(db_session):
    patient, user = await _make_patient(db_session)
    sched = ReminderSchedule(
        patient_id=patient.id, reminder_type=ReminderTypeEnum.MEDICINE,
        cadence="08:00", created_by=user.id, is_active=True)
    db_session.add(sched)
    await db_session.flush()

    now = datetime.now(timezone.utc)
    # (a) 15-min-old PENDING -> should ESCALATE and yield a reprompt
    db_session.add(ReminderEvent(
        patient_id=patient.id, schedule_id=sched.id,
        scheduled_at=now - timedelta(minutes=15), status=ReminderStatusEnum.PENDING))
    # (b) already-ESCALATED 90-min-old, unacked -> should become MISSED
    db_session.add(ReminderEvent(
        patient_id=patient.id, schedule_id=sched.id,
        scheduled_at=now - timedelta(minutes=90), status=ReminderStatusEnum.ESCALATED))
    await db_session.commit()

    result = await ReminderService.evaluate_escalations(db_session, patient.id)

    assert result["escalated_events"] == 1
    assert result["missed_events"] == 1
    assert len(result["reprompt_events"]) == 1
    assert result["reprompt_events"][0]["reminder_type"] == "medicine"

    statuses = sorted(
        (e.status.value for e in (await db_session.execute(
            select(ReminderEvent).where(ReminderEvent.patient_id == patient.id)
        )).scalars().all())
    )
    assert statuses == ["escalated", "missed"]

    # reprompt fan-out uses the notification provider (console mock here)
    provider = ConsoleNotificationProvider()
    sent = await notify_reprompts(patient.id, result, provider=provider)
    assert sent == 1
    assert provider.deliveries[0]["kind"] == "reprompt"
    assert provider.deliveries[0]["reminder_type"] == "medicine"


@pytest.mark.asyncio
async def test_acknowledged_escalated_not_marked_missed(db_session):
    """An ESCALATED event that was later acknowledged must not flip to MISSED."""
    patient, user = await _make_patient(db_session)
    sched = ReminderSchedule(
        patient_id=patient.id, reminder_type=ReminderTypeEnum.MEDICINE,
        cadence="08:00", created_by=user.id, is_active=True)
    db_session.add(sched)
    await db_session.flush()
    now = datetime.now(timezone.utc)
    db_session.add(ReminderEvent(
        patient_id=patient.id, schedule_id=sched.id,
        scheduled_at=now - timedelta(minutes=120),
        acknowledged_at=now - timedelta(minutes=100),
        status=ReminderStatusEnum.ESCALATED))
    await db_session.commit()

    result = await ReminderService.evaluate_escalations(db_session, patient.id)
    assert result["missed_events"] == 0

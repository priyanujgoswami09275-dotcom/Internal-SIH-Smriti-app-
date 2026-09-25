"""Reminder Service — Schedules, Events, Acknowledgments, and Escalation Rules.

Cadence grammar:
    [daily|everyday|every day][@|at|:]? HH:MM[,HH:MM;HH:MM]...
Legacy ``HH:MM AM|PM Daily`` is also accepted. Matching is case-insensitive,
times are 24-hour wall-clock values in settings.REMINDER_TIMEZONE, and duplicate
times collapse to one daily occurrence.

Lifecycle (generation job + escalation scan):
    (generation)  -> PENDING
    unacked 10m   -> ESCALATED  + secondary notification (reprompt)
    unacked 60m   -> MISSED
    3 unresolved of one type in 7 days -> AlertFlag for family/ASHA.
"""
import re
import uuid
from datetime import datetime, timedelta, timezone, time as dtime
from zoneinfo import ZoneInfo
from typing import List, Optional, Dict, Any
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.config import settings
from app.models.all_models import (
    AlertFlag, PatientProfile, ReminderEvent, ReminderSchedule,
    ReminderTypeEnum, ReminderStatusEnum, AcknowledgmentMethodEnum,
    AlertTriggerTypeEnum, AlertSeverityEnum,
)

CADENCE_GRAMMAR = (
    "Accepted grammar: [daily|everyday|every day][@|at|:]? "
    "HH:MM[,HH:MM;HH:MM]... (case-insensitive, 24-hour); "
    "legacy HH:MM AM|PM Daily is accepted."
)
CADENCE_ERROR = f"Invalid cadence. {CADENCE_GRAMMAR}"
_CADENCE_PREFIX = re.compile(r"^(?:(?:daily|everyday|every\s+day)\s*)?(?:@|at|:)?\s*", re.IGNORECASE)
_TIME_TOKEN = re.compile(
    r"^(?P<hour>\d{1,2}):(?P<minute>\d{2})"
    r"(?:\s*(?P<meridiem>am|pm))?"
    r"(?:\s+(?P<daily>daily))?$",
    re.IGNORECASE,
)


def _occurrence_key(scheduled_at: datetime) -> str:
    utc_value = (
        scheduled_at.replace(tzinfo=timezone.utc)
        if scheduled_at.tzinfo is None
        else scheduled_at.astimezone(timezone.utc)
    )
    return utc_value.strftime("%Y%m%dT%H%M")


def alert_dedup_key(now: datetime) -> str:
    utc_value = (
        now.replace(tzinfo=timezone.utc)
        if now.tzinfo is None
        else now.astimezone(timezone.utc)
    )
    return utc_value.strftime("%Y%m%d")


def is_unique_violation(exc: IntegrityError) -> bool:
    original = exc.orig
    if getattr(original, "sqlstate", None) == "23505":
        return True
    if getattr(original, "sqlite_errorcode", None) in {1555, 2067}:
        return True
    message = str(original).lower()
    return "unique constraint failed" in message or "duplicate key value" in message


class ReminderService:
    @staticmethod
    def parse_cadence(cadence: str) -> List[dtime]:
        """Parse one complete cadence expression into unique daily times."""
        if not cadence or not cadence.strip():
            raise ValueError(CADENCE_ERROR)
        raw = _CADENCE_PREFIX.sub("", cadence.strip())
        if not raw:
            raise ValueError(CADENCE_ERROR)
        times: List[dtime] = []
        for part in re.split(r"[,;]+", raw):
            match = _TIME_TOKEN.fullmatch(part.strip())
            if not match:
                raise ValueError(CADENCE_ERROR)
            hour = int(match.group("hour"))
            minute = int(match.group("minute"))
            meridiem = match.group("meridiem")
            daily_suffix = match.group("daily")
            if bool(daily_suffix) != bool(meridiem):
                raise ValueError(CADENCE_ERROR)
            if meridiem:
                if not 1 <= hour <= 12 or not 0 <= minute < 60:
                    raise ValueError(CADENCE_ERROR)
                if meridiem.lower() == "am" and hour == 12:
                    hour = 0
                elif meridiem.lower() == "pm" and hour != 12:
                    hour += 12
            elif not 0 <= hour < 24 or not 0 <= minute < 60:
                raise ValueError(CADENCE_ERROR)
            value = dtime(hour=hour, minute=minute)
            if value not in times:
                times.append(value)
        if not times:
            raise ValueError(CADENCE_ERROR)
        return sorted(times)

    @staticmethod
    async def lock_patient(db: AsyncSession, patient_id: uuid.UUID) -> None:
        await db.execute(
            select(PatientProfile.id)
            .where(PatientProfile.id == patient_id)
            .with_for_update()
        )

    @staticmethod
    async def generate_due_events_for_all(
        db: AsyncSession, now: Optional[datetime] = None
    ) -> Dict[str, Any]:
        """Materialize a PENDING ReminderEvent for each active schedule's due
        times that have passed today and are not already recorded.

        Idempotent: a second run on the same day creates nothing new (dedupes on
        schedule_id + the exact due minute). Offline-created events (same
        scheduled_at) also dedupe, so replayed acknowledgments are preserved.
        """
        now = now or datetime.now(timezone.utc)
        tz = ZoneInfo(settings.REMINDER_TIMEZONE)
        local_now = now.astimezone(tz)

        scheds = (
            await db.execute(
                select(ReminderSchedule).where(ReminderSchedule.is_active == True)  # noqa: E712
            )
        ).scalars().all()

        created = 0
        for sched in scheds:
            try:
                cadence_times = ReminderService.parse_cadence(sched.cadence)
            except ValueError:
                cadence_times = []
            for t in cadence_times:
                local_due = local_now.replace(
                    hour=t.hour, minute=t.minute, second=0, microsecond=0
                )
                due_utc = local_due.astimezone(timezone.utc)
                if due_utc > now:
                    continue
                occurrence_key = _occurrence_key(due_utc)
                exists = (
                    await db.execute(
                        select(ReminderEvent.id).where(
                            ReminderEvent.patient_id == sched.patient_id,
                            ReminderEvent.schedule_id == sched.id,
                            ReminderEvent.occurrence_key == occurrence_key,
                        )
                    )
                ).first()
                if not exists:
                    exists = (
                        await db.execute(
                            select(ReminderEvent.id).where(
                                ReminderEvent.schedule_id == sched.id,
                                ReminderEvent.scheduled_at >= due_utc,
                                ReminderEvent.scheduled_at < due_utc + timedelta(minutes=1),
                            )
                        )
                    ).first()
                if exists:
                    continue
                event = ReminderEvent(
                    id=uuid.uuid4(),
                    schedule_id=sched.id,
                    patient_id=sched.patient_id,
                    scheduled_at=due_utc,
                    occurrence_key=occurrence_key,
                    delivered_at=now,
                    status=ReminderStatusEnum.PENDING,
                    created_at=now,
                )
                try:
                    async with db.begin_nested():
                        db.add(event)
                        await db.flush()
                except IntegrityError as exc:
                    if not is_unique_violation(exc):
                        raise
                    continue
                created += 1
        if created:
            await db.commit()
        return {"schedules": len(scheds), "events_created": created}

    @staticmethod
    async def create_schedule(
        db: AsyncSession,
        patient_id: uuid.UUID,
        reminder_type: ReminderTypeEnum,
        cadence: str,
        created_by: uuid.UUID,
    ) -> ReminderSchedule:
        ReminderService.parse_cadence(cadence)
        schedule = ReminderSchedule(
            id=uuid.uuid4(),
            patient_id=patient_id,
            reminder_type=reminder_type,
            cadence=cadence,
            created_by=created_by,
            is_active=True,
            created_at=datetime.now(timezone.utc),
        )
        db.add(schedule)
        await db.commit()
        await db.refresh(schedule)
        return schedule

    @staticmethod
    async def get_patient_schedules(
        db: AsyncSession, patient_id: uuid.UUID
    ) -> List[ReminderSchedule]:
        stmt = select(ReminderSchedule).where(
            ReminderSchedule.patient_id == patient_id,
            ReminderSchedule.is_active == True,
        )
        result = await db.execute(stmt)
        return list(result.scalars().all())

    @staticmethod
    async def get_schedule(
        db: AsyncSession, schedule_id: uuid.UUID
    ) -> Optional[ReminderSchedule]:
        stmt = select(ReminderSchedule).where(ReminderSchedule.id == schedule_id)
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    @staticmethod
    async def deactivate_schedule(
        db: AsyncSession, schedule_id: uuid.UUID
    ) -> bool:
        schedule = await ReminderService.get_schedule(db, schedule_id)
        if not schedule:
            return False
        schedule.is_active = False
        await db.commit()
        return True

    @staticmethod
    async def record_reminder_event(
        db: AsyncSession,
        schedule_id: uuid.UUID,
        patient_id: uuid.UUID,
        scheduled_at: datetime,
        delivered_at: Optional[datetime] = None,
        event_id: Optional[uuid.UUID] = None,
    ) -> ReminderEvent:
        occurrence_key = _occurrence_key(scheduled_at)
        existing = (
            await db.execute(
                select(ReminderEvent).where(
                    ReminderEvent.patient_id == patient_id,
                    ReminderEvent.schedule_id == schedule_id,
                    ReminderEvent.occurrence_key == occurrence_key,
                )
            )
        ).scalars().first()
        if not existing:
            minute_start = scheduled_at.replace(second=0, microsecond=0)
            existing = (
                await db.execute(
                    select(ReminderEvent).where(
                        ReminderEvent.schedule_id == schedule_id,
                        ReminderEvent.scheduled_at >= minute_start,
                        ReminderEvent.scheduled_at < minute_start + timedelta(minutes=1),
                    )
                )
            ).scalars().first()
        if existing:
            return existing

        event = ReminderEvent(
            id=event_id or uuid.uuid4(),
            schedule_id=schedule_id,
            patient_id=patient_id,
            scheduled_at=scheduled_at,
            occurrence_key=occurrence_key,
            delivered_at=delivered_at or datetime.now(timezone.utc),
            status=ReminderStatusEnum.PENDING,
            synced_at=datetime.now(timezone.utc),
            created_at=datetime.now(timezone.utc),
        )
        try:
            async with db.begin_nested():
                db.add(event)
                await db.flush()
        except IntegrityError as exc:
            if not is_unique_violation(exc):
                raise
            existing = (
                await db.execute(
                    select(ReminderEvent).where(
                        ReminderEvent.patient_id == patient_id,
                        ReminderEvent.schedule_id == schedule_id,
                        ReminderEvent.occurrence_key == occurrence_key,
                    )
                )
            ).scalars().first()
            if not existing:
                raise
            return existing
        await db.commit()
        await db.refresh(event)
        return event

    @staticmethod
    async def acknowledge_reminder(
        db: AsyncSession,
        event_id: uuid.UUID,
        method: AcknowledgmentMethodEnum = AcknowledgmentMethodEnum.BUTTON,
    ) -> Optional[ReminderEvent]:
        stmt = select(ReminderEvent).where(ReminderEvent.id == event_id)
        result = await db.execute(stmt)
        event = result.scalar_one_or_none()
        if not event:
            return None

        event.status = ReminderStatusEnum.ACKNOWLEDGED
        event.acknowledged_at = datetime.now(timezone.utc)
        event.acknowledgment_method = method
        await db.commit()
        await db.refresh(event)
        return event

    @staticmethod
    async def get_patient_reminder_events(
        db: AsyncSession,
        patient_id: uuid.UUID,
        status: Optional[ReminderStatusEnum] = None,
        limit: int = 50,
    ) -> List[ReminderEvent]:
        stmt = select(ReminderEvent).where(ReminderEvent.patient_id == patient_id)
        if status:
            stmt = stmt.where(ReminderEvent.status == status)
        stmt = stmt.order_by(ReminderEvent.scheduled_at.desc()).limit(limit)
        result = await db.execute(stmt)
        return list(result.scalars().all())

    @staticmethod
    async def evaluate_escalations(
        db: AsyncSession, patient_id: uuid.UUID
    ) -> Dict[str, Any]:
        """
        Escalation Rules:
        1. 10 minutes unacknowledged -> Escalate to secondary notification.
        2. 3 missed reminders of same type in 7 days -> Trigger AlertFlag for Caregivers/ASHA.
        """
        now = datetime.now(timezone.utc)
        escalate_cutoff = now - timedelta(minutes=settings.REMINDER_ESCALATE_MINUTES)
        missed_cutoff = now - timedelta(minutes=settings.REMINDER_MISSED_MINUTES)
        seven_days_ago = now - timedelta(days=7)

        # 1. Pending events older than the escalate window -> ESCALATED.
        pending_stmt = select(ReminderEvent).where(
            ReminderEvent.patient_id == patient_id,
            ReminderEvent.status == ReminderStatusEnum.PENDING,
            ReminderEvent.scheduled_at <= escalate_cutoff,
        )
        pending_res = await db.execute(pending_stmt)
        pending_events = pending_res.scalars().all()

        # Map schedule_id -> reminder_type so reprompts can name the reminder.
        sched_ids = {ev.schedule_id for ev in pending_events}
        type_by_sched: Dict[Any, Any] = {}
        if sched_ids:
            trows = await db.execute(
                select(ReminderSchedule.id, ReminderSchedule.reminder_type).where(
                    ReminderSchedule.id.in_(sched_ids)
                )
            )
            type_by_sched = {sid: rtype for sid, rtype in trows.all()}

        escalated_count = 0
        reprompt_events: List[Dict[str, Any]] = []
        for ev in pending_events:
            ev.status = ReminderStatusEnum.ESCALATED
            escalated_count += 1
            rtype = type_by_sched.get(ev.schedule_id)
            reprompt_events.append({
                "event_id": ev.id,
                "reminder_type": rtype.value if hasattr(rtype, "value") else str(rtype),
            })
        # Persist the status change before the unresolved-count query below so
        # the 3-missed rule is deterministic regardless of the session's
        # autoflush setting.
        await db.flush()

        # 1b. Events escalated in a PRIOR pass and still unacknowledged past the
        # missed window -> MISSED (the terminal unresolved state).
        missed_stmt = select(ReminderEvent).where(
            ReminderEvent.patient_id == patient_id,
            ReminderEvent.status == ReminderStatusEnum.ESCALATED,
            ReminderEvent.acknowledged_at.is_(None),
            ReminderEvent.scheduled_at <= missed_cutoff,
        )
        missed_events = (await db.execute(missed_stmt)).scalars().all()
        missed_count = 0
        for ev in missed_events:
            ev.status = ReminderStatusEnum.MISSED
            missed_count += 1
        if missed_count:
            await db.flush()

        # 2. Missed/escalated events in last 7 days grouped by reminder type
        query = (
            select(ReminderSchedule.reminder_type, func.count(ReminderEvent.id))
            .join(ReminderEvent, ReminderEvent.schedule_id == ReminderSchedule.id)
            .where(
                ReminderEvent.patient_id == patient_id,
                ReminderEvent.scheduled_at >= seven_days_ago,
                ReminderEvent.status.in_([ReminderStatusEnum.MISSED, ReminderStatusEnum.ESCALATED]),
            )
            .group_by(ReminderSchedule.reminder_type)
        )
        unresolved_res = await db.execute(query)
        recent_unresolved = unresolved_res.all()

        alerts_generated = []
        alert_summaries = []
        for rem_type, count in recent_unresolved:
            if count >= 3:
                await ReminderService.lock_patient(db, patient_id)
                existing_alert_stmt = (
                    select(AlertFlag)
                    .where(
                        AlertFlag.patient_id == patient_id,
                        AlertFlag.trigger_type == AlertTriggerTypeEnum.MISSED_REMINDERS,
                        AlertFlag.created_at >= now - timedelta(hours=24),
                    )
                    .limit(1)
                )
                existing_alert = (
                    await db.execute(existing_alert_stmt)
                ).scalars().first()
                if not existing_alert:
                    type_str = rem_type.value if hasattr(rem_type, 'value') else str(rem_type)
                    summary_msg = f"Patient missed {count} {type_str} reminders in the past 7 days."
                    alert = AlertFlag(
                        id=uuid.uuid4(),
                        patient_id=patient_id,
                        trigger_type=AlertTriggerTypeEnum.MISSED_REMINDERS,
                        dedup_key=alert_dedup_key(now),
                        severity=AlertSeverityEnum.CRITICAL if rem_type == ReminderTypeEnum.MEDICINE else AlertSeverityEnum.WARNING,
                        alert_summary=summary_msg,
                        threshold_detail={"reminder_type": type_str, "missed_count": count, "window_days": 7},
                        created_at=now,
                    )
                    try:
                        async with db.begin_nested():
                            db.add(alert)
                            await db.flush()
                    except IntegrityError as exc:
                        if not is_unique_violation(exc):
                            raise
                        continue
                    alerts_generated.append(alert)
                    alert_summaries.append(summary_msg)

        summary_text = (
            f"Evaluated escalations for patient {patient_id}. Raised {len(alerts_generated)} alerts. "
            + "; ".join(alert_summaries)
        )
        await db.commit()
        return {
            "escalated_events": escalated_count,
            "missed_events": missed_count,
            "alerts_created": len(alerts_generated),
            "raised_alerts": len(alerts_generated),
            "reprompt_events": reprompt_events,
            "summary": summary_text,
            "alerts": alerts_generated,
        }

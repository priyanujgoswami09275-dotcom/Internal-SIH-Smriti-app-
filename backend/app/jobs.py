"""Background jobs — reminder escalation, sync consumption, retention.

Implements the "scheduled job" behavior from CLAUDE.md Phase 6 without an
external scheduler dependency: an asyncio loop that runs while the process is
up, or a cron/CI line that calls the one-shot functions.

Cadence (configurable via env):
- REMINDER_GENERATION_SECONDS (default 60)   materialize due reminder events
- ESCALATION_SCAN_SECONDS   (default 60)   escalate + reprompt + mark missed + fan-out
- SYNC_CONSUME_SECONDS      (default 300)  materialize the sync outbox
- RETENTION_RUN_HOURS       (default 24)   DPDP retention + grace deletion

Run:
    python -m app.jobs                     # forever (asyncio loop)
    python -m app.jobs --once generate     # single reminder-generation pass, exit
    python -m app.jobs --once escalation   # single escalation scan, exit

Each scan is resilient: a failing patient/session never aborts the loop.
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import and_, distinct, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import async_session_maker
from app.models.all_models import ReminderEvent, ReminderStatusEnum
from app.services.alert_engine import AlertEngine
from app.services.notification_service import (
    get_notification_provider,
    notify_escalation_results,
    notify_reprompts,
)
from app.services.reminder_service import ReminderService
from app.services.retention_service import RetentionService
from app.services.sync_service import consume_sync_queue

logger = logging.getLogger("app.jobs")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


async def generate_events(db: AsyncSession) -> dict:
    """Materialize due ReminderEvents from active schedule cadences."""
    return await ReminderService.generate_due_events_for_all(db)


async def alert_engine_pass(db: AsyncSession) -> dict:
    """P6 alert engine: cognitive-drop + medicine-miss rules -> AlertFlags."""
    return await AlertEngine.run_hourly_pass(db)


async def weekly_reports_pass(db: AsyncSession) -> dict:
    """P7: persist a weekly clinical summary for every patient."""
    from app.services.report_service import ReportService

    return await ReportService.generate_reports_for_all_patients(db)


def _next_sunday_midnight(now: datetime) -> datetime:
    """Next Sunday 00:00 UTC strictly after `now` (cron-style anchor)."""
    days_ahead = (6 - now.weekday()) % 7  # Sunday == 6
    target = (now + timedelta(days=days_ahead)).replace(
        hour=0, minute=0, second=0, microsecond=0)
    if target <= now:
        target += timedelta(days=7)
    return target


async def escalation_scan(db: AsyncSession) -> dict:
    """Escalate unacknowledged reminders, send reprompts, mark misses, raise alerts.

    Scans patients that have either a PENDING event past the escalate window or
    an unacknowledged ESCALATED event past the missed window, evaluates the
    rules for each, sends the 10-minute reprompt, and fans alerts out to
    family/ASHA. Returns aggregate counters.
    """
    now = datetime.now(timezone.utc)
    escalate_cutoff = now - timedelta(minutes=settings.REMINDER_ESCALATE_MINUTES)
    missed_cutoff = now - timedelta(minutes=settings.REMINDER_MISSED_MINUTES)
    stmt = (
        select(distinct(ReminderEvent.patient_id)).where(
            or_(
                and_(
                    ReminderEvent.status == ReminderStatusEnum.PENDING,
                    ReminderEvent.scheduled_at <= escalate_cutoff,
                ),
                and_(
                    ReminderEvent.status == ReminderStatusEnum.ESCALATED,
                    ReminderEvent.acknowledged_at.is_(None),
                    ReminderEvent.scheduled_at <= missed_cutoff,
                ),
            )
        )
    )
    patient_ids = (await db.execute(stmt)).scalars().all()

    escalated = 0
    missed = 0
    alerts = 0
    recipients_resolved = 0
    confirmed_deliveries = 0
    reprompt_recipients_resolved = 0
    reprompt_confirmed_deliveries = 0
    delivery_states = []
    reprompt_delivery_states = []
    for pid in patient_ids:
        try:
            result = await ReminderService.evaluate_escalations(db, pid)
            escalated += result.get("escalated_events", 0)
            missed += result.get("missed_events", 0)
            alerts += result.get("alerts_created", 0)
            provider = get_notification_provider(db=db)
            alert_delivery = await notify_escalation_results(
                db, pid, result, provider=provider
            )
            reprompt_delivery = await notify_reprompts(
                db, pid, result, provider=provider
            )
            recipients_resolved += alert_delivery["recipients_resolved"]
            confirmed_deliveries += alert_delivery["confirmed_deliveries"]
            reprompt_recipients_resolved += reprompt_delivery["recipients_resolved"]
            reprompt_confirmed_deliveries += reprompt_delivery["confirmed_deliveries"]
            delivery_states.append(alert_delivery["delivery_state"])
            reprompt_delivery_states.append(reprompt_delivery["delivery_state"])
        except Exception:  # noqa: BLE001 — one patient must not break the scan
            logger.exception("Escalation scan failed for patient %s", pid)
    unique_delivery_states = set(delivery_states)
    unique_reprompt_states = set(reprompt_delivery_states)
    delivery_state = (
        unique_delivery_states.pop()
        if len(unique_delivery_states) == 1
        else "mixed"
    ) if unique_delivery_states else "not_applicable"
    reprompt_delivery_state = (
        unique_reprompt_states.pop()
        if len(unique_reprompt_states) == 1
        else "mixed"
    ) if unique_reprompt_states else "not_applicable"
    return {
        "patients_scanned": len(patient_ids),
        "escalated": escalated,
        "missed": missed,
        "alerts_created": alerts,
        "recipients_resolved": recipients_resolved,
        "confirmed_deliveries": confirmed_deliveries,
        "delivery_state": delivery_state,
        "notified": confirmed_deliveries,
        "reprompt_recipients_resolved": reprompt_recipients_resolved,
        "reprompt_confirmed_deliveries": reprompt_confirmed_deliveries,
        "reprompt_delivery_state": reprompt_delivery_state,
        "reprompts": reprompt_confirmed_deliveries,
    }


async def maintenance_once(db: AsyncSession) -> dict:
    """Consume the sync outbox and run retention in one maintenance pass."""
    consumed = await consume_sync_queue(db)
    retained = await RetentionService.run_maintenance(db)
    return {"consumed": consumed, "retained": retained}


async def _periodic_loop(escalation_s: int, consume_s: int, retention_h: int,
                         generation_s: int, alerts_s: int = 3600) -> None:
    """Run each job on its own cadence; failures never abort the loop."""
    logger.info("Background jobs started (generation=%ss escalation=%ss consume=%ss "
                "alerts=%ss retention=%sh)",
                generation_s, escalation_s, consume_s, alerts_s, retention_h)
    now = datetime.now(timezone.utc)
    next_generation = now
    next_escalation = now
    next_consume = now
    next_alerts = now
    next_weekly = _next_sunday_midnight(now)
    next_retention = now + timedelta(hours=retention_h)

    while True:
        now = datetime.now(timezone.utc)

        if now >= next_generation:
            try:
                async with async_session_maker() as db:
                    gen = await generate_events(db)
                    if gen.get("events_created"):
                        logger.info("Reminder generation: %s", gen)
            except Exception:  # noqa: BLE001
                logger.exception("Reminder generation pass failed")
            next_generation = now + timedelta(seconds=generation_s)

        if now >= next_escalation:
            try:
                async with async_session_maker() as db:
                    scan = await escalation_scan(db)
                    if scan["patients_scanned"]:
                        logger.info("Escalation scan: %s", scan)
            except Exception:  # noqa: BLE001
                logger.exception("Escalation scan pass failed")
            next_escalation = now + timedelta(seconds=escalation_s)

        if now >= next_consume:
            try:
                async with async_session_maker() as db:
                    consumed = await consume_sync_queue(db)
                    if consumed.get("materialized"):
                        logger.info("Sync consumer: %s", consumed)
            except Exception:  # noqa: BLE001
                logger.exception("Sync consume pass failed")
            next_consume = now + timedelta(seconds=consume_s)

        if now >= next_retention:
            try:
                async with async_session_maker() as db:
                    m = await maintenance_once(db)
                    logger.info("Maintenance pass: %s", m)
            except Exception:  # noqa: BLE001
                logger.exception("Retention pass failed")
            next_retention = now + timedelta(hours=retention_h)

        if now >= next_alerts:
            try:
                async with async_session_maker() as db:
                    a = await alert_engine_pass(db)
                    if a.get("alerts_created") or a.get("patients_evaluated"):
                        logger.info("Alert engine pass: %s", a)
            except Exception:  # noqa: BLE001
                logger.exception("Alert engine pass failed")
            next_alerts = now + timedelta(seconds=alerts_s)

        if now >= next_weekly:
            try:
                async with async_session_maker() as db:
                    w = await weekly_reports_pass(db)
                    if w.get("created") or w.get("updated"):
                        logger.info("Weekly reports: %s", w)
            except Exception:  # noqa: BLE001
                logger.exception("Weekly reports pass failed")
            next_weekly = _next_sunday_midnight(now)

        await asyncio.sleep(min(generation_s, escalation_s, consume_s, alerts_s))


async def run_once(kind: str) -> None:
    async with async_session_maker() as db:
        if kind == "generate":
            print(await generate_events(db))
        elif kind == "escalation":
            print(await escalation_scan(db))
        elif kind == "consume":
            print(await consume_sync_queue(db))
        elif kind == "alerts":
            print(await alert_engine_pass(db))
        elif kind == "weekly-reports":
            print(await weekly_reports_pass(db))
        elif kind == "retention":
            print(await RetentionService.run_maintenance(db))
        else:
            raise SystemExit(f"Unknown job kind: {kind}")


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


def start_in_background() -> asyncio.Task:
    """Launch the periodic loop as a task on the running event loop (API lifespan)."""
    return asyncio.create_task(
        _periodic_loop(
            escalation_s=_env_int("ESCALATION_SCAN_SECONDS", 60),
            consume_s=_env_int("SYNC_CONSUME_SECONDS", 300),
            retention_h=_env_int("RETENTION_RUN_HOURS", 24),
            generation_s=_env_int("REMINDER_GENERATION_SECONDS", settings.REMINDER_GENERATION_SECONDS),
            alerts_s=_env_int("ALERT_ENGINE_SECONDS", 3600),
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Elder-care background jobs")
    parser.add_argument("--once", choices=["generate", "escalation", "consume", "alerts", "weekly-reports", "retention"],
                        help="run a single pass and exit")
    args = parser.parse_args()
    if args.once:
        asyncio.run(run_once(args.once))
        return
    asyncio.run(_periodic_loop(
        escalation_s=_env_int("ESCALATION_SCAN_SECONDS", 60),
        consume_s=_env_int("SYNC_CONSUME_SECONDS", 300),
        retention_h=_env_int("RETENTION_RUN_HOURS", 24),
        generation_s=_env_int("REMINDER_GENERATION_SECONDS", settings.REMINDER_GENERATION_SECONDS),
        alerts_s=_env_int("ALERT_ENGINE_SECONDS", 3600),
    ))


if __name__ == "__main__":
    main()

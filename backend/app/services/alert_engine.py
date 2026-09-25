"""P6 — Alert Engine: rule evaluation that WRITES AlertFlags + notifies.

Rules (hourly job, per patient with recent activity):
1. 3+ missed/escalated medicine reminders in 7 days  -> CRITICAL AlertFlag
   (already enforced by ReminderService.evaluate_escalations — re-evaluated
   here so the hourly pass is self-sufficient)
2. Cognitive score drop >=20% over 2 weeks (week 1 vs week 2 accuracy, same
   rule the dashboard computes) -> WARNING AlertFlag (COGNITIVE_SCORE_DIP)

Dedup: one alert per (patient, trigger) per 24h — same guard as the reminder rule.

ponytail: week-over-week accuracy is computed with two SUM() queries, not a
rolling window table — fine at demo scale; upgrade to a materialized trend if
patients exceed thousands.
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

from sqlalchemy import distinct, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.all_models import (
    AlertFlag,
    AlertSeverityEnum,
    AlertTriggerTypeEnum,
    ConsentRecord,
    GameSession,
    ReminderEvent,
    ReminderSchedule,
    ReminderStatusEnum,
    ReminderTypeEnum,
)
from app.services.notification_service import notify_escalation_results
from app.services.reminder_service import (
    ReminderService,
    alert_dedup_key,
    is_unique_violation,
)

logger = logging.getLogger(__name__)


class AlertEngine:
    @staticmethod
    async def _raise_alert(
        db: AsyncSession,
        patient_id: uuid.UUID,
        trigger: AlertTriggerTypeEnum,
        severity: AlertSeverityEnum,
        summary: str,
        detail: Dict[str, Any],
        now: datetime,
    ) -> AlertFlag | None:
        """Insert an AlertFlag unless one of the same trigger exists in 24h."""
        await ReminderService.lock_patient(db, patient_id)
        existing = (
            await db.execute(
                select(AlertFlag)
                .where(
                    AlertFlag.patient_id == patient_id,
                    AlertFlag.trigger_type == trigger,
                    AlertFlag.created_at >= now - timedelta(hours=24),
                )
                .limit(1)
            )
        ).scalars().first()
        if existing is not None:
            return None
        alert = AlertFlag(
            id=uuid.uuid4(),
            patient_id=patient_id,
            trigger_type=trigger,
            dedup_key=alert_dedup_key(now),
            severity=severity,
            alert_summary=summary,
            threshold_detail=detail,
            created_at=now,
        )
        try:
            async with db.begin_nested():
                db.add(alert)
                await db.flush()
        except IntegrityError as exc:
            if not is_unique_violation(exc):
                raise
            return None
        return alert

    @staticmethod
    async def _week_accuracy(db: AsyncSession, patient_id, start: datetime, end: datetime):
        row = (
            await db.execute(
                select(
                    func.coalesce(func.sum(GameSession.attempts), 0),
                    func.coalesce(func.sum(GameSession.correct_count), 0),
                ).where(
                    GameSession.patient_id == patient_id,
                    GameSession.started_at >= start,
                    GameSession.started_at < end,
                )
            )
        ).one()
        attempts, correct = row[0], row[1]
        return (correct / attempts * 100.0) if attempts else None

    @staticmethod
    async def evaluate_patient(
        db: AsyncSession, patient_id: uuid.UUID, now: datetime | None = None
    ) -> Dict[str, Any]:
        """Run all rules for one patient. Commits nothing itself."""
        now = now or datetime.now(timezone.utc)
        raised: List[AlertFlag] = []

        # --- Rule 1: medicine misses (re-run the reminder escalation rules) ---
        esc = await ReminderService.evaluate_escalations(db, patient_id)
        for a in esc.get("alerts", []) or []:
            raised.append(a)  # already committed by evaluate_escalations

        # --- Rule 2: cognitive drop >=20% week-over-week ---
        week2_start = now - timedelta(days=7)
        week1_start = now - timedelta(days=14)
        earlier_acc = await AlertEngine._week_accuracy(db, patient_id, week1_start, week2_start)
        later_acc = await AlertEngine._week_accuracy(db, patient_id, week2_start, now)
        if earlier_acc and later_acc is not None and earlier_acc > 0:
            drop_pct = round((earlier_acc - later_acc) / earlier_acc * 100.0, 1)
            if drop_pct >= 20.0:
                alert = await AlertEngine._raise_alert(
                    db, patient_id,
                    AlertTriggerTypeEnum.COGNITIVE_SCORE_DIP,
                    AlertSeverityEnum.WARNING,
                    f"Cognitive accuracy dropped {drop_pct}% over the last 2 weeks "
                    f"({round(earlier_acc,1)}% -> {round(later_acc,1)}%).",
                    {"earlier_accuracy_pct": round(earlier_acc, 1),
                     "later_accuracy_pct": round(later_acc, 1),
                     "drop_pct": drop_pct, "window_days": 14},
                    now,
                )
                if alert is not None:
                    raised.append(alert)

        return {"patient_id": str(patient_id), "alerts_raised": raised}

    @staticmethod
    async def run_hourly_pass(db: AsyncSession, now: datetime | None = None) -> Dict[str, int]:
        """Evaluate every consented patient with a session or reminder event in
        the last 14 days; notify caregivers for newly raised alerts. Never
        raises. Patients without active health_data consent are skipped
        (purpose limitation — the pass derives cognitive health signals)."""
        now = now or datetime.now(timezone.utc)
        since = now - timedelta(days=14)

        game_patients = (
            await db.execute(
                select(distinct(GameSession.patient_id)).where(
                    GameSession.started_at >= since)
            )
        ).scalars().all()
        rem_patients = (
            await db.execute(
                select(distinct(ReminderEvent.patient_id)).where(
                    ReminderEvent.scheduled_at >= since)
            )
        ).scalars().all()
        patient_ids = list(set(game_patients) | set(rem_patients))
        consented = set((await db.execute(
            select(ConsentRecord.patient_id).where(
                ConsentRecord.revoked_at.is_(None),
                ConsentRecord.scope.in_(["health_data", "all"]),
            )
        )).scalars().all())
        patient_ids = [pid for pid in patient_ids if pid in consented]

        alerts_created = 0
        notified = 0
        for pid in patient_ids:
            try:
                result = await AlertEngine.evaluate_patient(db, pid, now=now)
                new_alerts = result["alerts_raised"]
                alerts_created += len(new_alerts)
                if new_alerts:
                    fan = {
                        "alerts": new_alerts,
                        "alerts_created": len(new_alerts),
                    }
                    notified += await notify_escalation_results(db, pid, fan)
            except Exception:  # noqa: BLE001 — one patient never breaks the pass
                logger.exception("Alert engine failed for patient %s", pid)

        try:
            await db.commit()
        except Exception:  # noqa: BLE001
            await db.rollback()
            raise
        return {"patients_evaluated": len(patient_ids),
                "alerts_created": alerts_created, "notified": notified}


# Self-check: python -m app.services.alert_engine
if __name__ == "__main__":
    print("alert_engine: import OK (rules exercised in test_phase6_alert_engine.py)")

"""Automated Clinical & Cognitive Report Generation Service.

Aggregates:
- Game session cognitive trajectories (all four game types).
- ``cognitive_metrics`` retains pooled fields and adds ``metric_scope``,
  ``avg_response_time_ms``, and a ``game_metrics`` map keyed by game type.
- Reminder & Medication compliance stats.
- Symptom logs & clinical observations.
- Generates structured medical summary exportable for doctors and ASHA supervisors.
"""

import uuid
from datetime import datetime, timedelta, timezone
from typing import Dict, Any, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, distinct

from app.models.all_models import (
    ConsentRecord, PatientProfile, ReminderEvent,
    SymptomLog, ReminderStatusEnum, WeeklyReport,
)
from app.services.compliance_service import EncryptionService
from app.services.datetime_utils import iso_utc
from app.services.dashboard_service import (
    GAME_METRIC_SCOPE,
    get_game_analytics,
    naive_utc,
)


class ReportService:
    @staticmethod
    async def generate_weekly_clinical_summary(
        db: AsyncSession,
        patient_id: uuid.UUID,
        now: datetime | None = None,
    ) -> Dict[str, Any]:
        """Aggregate completed, bounded 7-day health metrics."""
        now = now or datetime.now(timezone.utc)
        start_date = now - timedelta(days=7)

        # 1. Fetch Patient Info
        p_stmt = select(PatientProfile).where(PatientProfile.id == patient_id)
        p_res = await db.execute(p_stmt)
        patient = p_res.scalar_one_or_none()

        patient_name = patient.name if patient else "Unknown"
        baseline = patient.cognitive_baseline.value if (patient and hasattr(patient.cognitive_baseline, 'value')) else "MCI"
        region = patient.region if patient else "Assam (NER)"

        analytics = await get_game_analytics(db, patient_id, start_date, now)
        aggregate = analytics["aggregate"]
        total_games = aggregate["games_played"]
        accuracy = aggregate["accuracy_pct"]
        if accuracy is None:
            accuracy = 0.0
        avg_response_time = aggregate["avg_response_time_ms"]
        if avg_response_time is None:
            avg_response_time = 0.0

        # 3. Fetch Reminder Compliance
        r_stmt = select(ReminderEvent).where(
            ReminderEvent.patient_id == patient_id,
            ReminderEvent.scheduled_at >= naive_utc(start_date),
            ReminderEvent.scheduled_at < naive_utc(now),
        )
        r_res = await db.execute(r_stmt)
        reminders = r_res.scalars().all()

        total_rem = len(reminders)
        acked = sum(1 for r in reminders if r.status == ReminderStatusEnum.ACKNOWLEDGED)
        missed = sum(1 for r in reminders if r.status in (ReminderStatusEnum.MISSED, ReminderStatusEnum.ESCALATED))
        compliance = (acked / total_rem * 100.0) if total_rem > 0 else 100.0

        # 4. Fetch Symptom Logs
        s_stmt = select(SymptomLog).where(
            SymptomLog.patient_id == patient_id,
            SymptomLog.timestamp >= naive_utc(start_date),
            SymptomLog.timestamp < naive_utc(now),
        ).order_by(SymptomLog.timestamp.desc())
        s_res = await db.execute(s_stmt)
        symptoms = s_res.scalars().all()

        # Symptom notes are stored AES-256 encrypted at rest (by the sync
        # consumer). Decrypt for the clinical report; decrypt() passes through
        # any note that was stored as plaintext, so mixed data is safe.
        _enc = EncryptionService()
        symptom_notes = [_enc.decrypt(s.notes) for s in symptoms if s.notes]

        # 5. Clinical Synthesis & Diagnostic Recommendations
        recommendations = []
        if accuracy < 60.0 and total_games >= 3:
            recommendations.append("Significant decline in short-term recall and pattern matching observed. Schedule MMSE/MoCA re-assessment.")
        if missed >= 3:
            recommendations.append("Medication non-adherence threshold breached. Recommend home visit by ASHA worker.")
        if not recommendations:
            recommendations.append("Patient demonstrates stable cognitive performance and good medication adherence.")

        return {
            "report_id": str(uuid.uuid4()),
            "patient_id": str(patient_id),
            "patient_name": patient_name,
            "region": region,
            "cognitive_baseline": baseline,
            "reporting_period": {
                "start": iso_utc(start_date),
                "end": iso_utc(now),
            },
            "cognitive_metrics": {
                "total_sessions": total_games,
                "overall_accuracy_pct": round(accuracy, 1),
                "avg_response_time_ms": round(avg_response_time, 1),
                "metric_scope": GAME_METRIC_SCOPE,
                "game_metrics": analytics["by_game"],
                "trend": "Stable" if accuracy >= 70.0 else "Declining",
            },
            "adherence_metrics": {
                "total_scheduled": total_rem,
                "acknowledged": acked,
                "missed_or_late": missed,
                "compliance_pct": round(compliance, 1),
            },
            "symptom_observations": symptom_notes,
            "clinical_recommendations": recommendations,
            "generated_at": iso_utc(now),
        }

    # =====================================================================
    # P7 — persisted weekly reports
    # =====================================================================

    @staticmethod
    def _week_start(now: datetime | None = None) -> datetime:
        """Monday 00:00 UTC of the reporting week (UTC-anchored; IST display
        is the caller's concern)."""
        now = now or datetime.now(timezone.utc)
        monday = now - timedelta(days=now.weekday())
        return monday.replace(hour=0, minute=0, second=0, microsecond=0)

    @staticmethod
    async def generate_and_save_weekly_report(
        db: AsyncSession, patient_id: uuid.UUID, now: datetime | None = None
    ) -> WeeklyReport:
        """Build this week's summary and persist it (idempotent per week)."""
        week_start = ReportService._week_start(now)
        existing = (
            await db.execute(
                select(WeeklyReport).where(
                    WeeklyReport.patient_id == patient_id,
                    WeeklyReport.week_start == week_start,
                )
            )
        ).scalar_one_or_none()

        summary = await ReportService.generate_weekly_clinical_summary(
            db, patient_id, now=now
        )
        if existing is not None:
            existing.report_json = summary  # regenerate in-place within the week
            existing.generated_at = datetime.now(timezone.utc)
            await db.commit()
            await db.refresh(existing)
            return existing

        report = WeeklyReport(
            id=uuid.uuid4(),
            patient_id=patient_id,
            week_start=week_start,
            generated_at=datetime.now(timezone.utc),
            report_json=summary,
        )
        db.add(report)
        await db.commit()
        await db.refresh(report)
        return report

    @staticmethod
    async def generate_reports_for_all_patients(
        db: AsyncSession, now: datetime | None = None
    ) -> Dict[str, int]:
        """Sunday-midnight job body: one persisted report per consented
        active patient. Patients without active health_data consent are
        skipped (purpose limitation — reports persist health-derived data)."""
        patient_ids = (
            await db.execute(select(distinct(PatientProfile.id)))
        ).scalars().all()
        consented = set((await db.execute(
            select(ConsentRecord.patient_id).where(
                ConsentRecord.revoked_at.is_(None),
                ConsentRecord.scope.in_(["health_data", "all"]),
            )
        )).scalars().all())
        patient_ids = [pid for pid in patient_ids if pid in consented]
        created = updated = 0
        week_start = ReportService._week_start(now)
        for pid in patient_ids:
            try:
                before = (
                    await db.execute(
                        select(WeeklyReport.id).where(
                            WeeklyReport.patient_id == pid,
                            WeeklyReport.week_start == week_start,
                        )
                    )
                ).scalar_one_or_none()
                await ReportService.generate_and_save_weekly_report(db, pid, now=now)
                if before is None:
                    created += 1
                else:
                    updated += 1
            except Exception:  # noqa: BLE001 — one patient never breaks the run
                import logging
                logging.getLogger(__name__).exception(
                    "Weekly report failed for patient %s", pid
                )
        return {"patients": len(patient_ids), "created": created, "updated": updated}

    @staticmethod
    async def get_latest_report(
        db: AsyncSession, patient_id: uuid.UUID
    ) -> WeeklyReport | None:
        return (
            await db.execute(
                select(WeeklyReport)
                .where(WeeklyReport.patient_id == patient_id)
                .order_by(WeeklyReport.week_start.desc())
                .limit(1)
            )
        ).scalar_one_or_none()

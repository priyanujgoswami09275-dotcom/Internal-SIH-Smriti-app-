"""Caregiver & Clinician Dashboard Analytics Service.

Provides:
- Multi-patient overview for ASHA workers & Family Caregivers.
- Cognitive performance trends (accuracy, avg response times over 7d/30d).
- Reminder compliance metrics (% acknowledged, missed, escalated).
- Active AlertFlags / Risk notifications.
"""
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Any, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_
from app.models.all_models import (
    PatientProfile, CaregiverPatientLink, GameSession,
    ReminderEvent, ReminderSchedule, AlertFlag,
    GameTypeEnum, ReminderStatusEnum, PermissionTierEnum
)


class DashboardService:
    @staticmethod
    async def get_caregiver_patients(
        db: AsyncSession,
        caregiver_user_id: uuid.UUID,
        role: str = "family_caregiver",
    ) -> List[Dict[str, Any]]:
        """Return the roster allowed by the caller's server-side role scope."""
        role_name = role.value if hasattr(role, "value") else str(role)
        if role_name in ("clinician", "admin"):
            res = await db.execute(
                select(PatientProfile)
                .order_by(PatientProfile.created_at.desc(), PatientProfile.id)
            )
            rows = [(patient, None) for patient in res.scalars().all()]
        else:
            res = await db.execute(
                select(PatientProfile, CaregiverPatientLink)
                .join(
                    CaregiverPatientLink,
                    CaregiverPatientLink.patient_id == PatientProfile.id,
                )
                .where(
                    CaregiverPatientLink.caregiver_id == caregiver_user_id,
                    CaregiverPatientLink.is_active == True,
                )
                .order_by(PatientProfile.created_at.desc(), PatientProfile.id)
            )
            rows = res.all()

        patients_data = []
        for patient, link in rows:
            if link is None:
                relationship_type = "staff"
                permission_tier = "clinical"
            else:
                relationship_type = (
                    link.relationship_type.value
                    if hasattr(link.relationship_type, "value")
                    else str(link.relationship_type)
                )
                permission_tier = (
                    link.permission_tier.value
                    if hasattr(link.permission_tier, "value")
                    else str(link.permission_tier)
                )
            patients_data.append({
                "patient_id": str(patient.id),
                "name": patient.name,
                "cognitive_baseline": patient.cognitive_baseline.value if hasattr(patient.cognitive_baseline, 'value') else str(patient.cognitive_baseline),
                "region": patient.region,
                "district": patient.district,
                "relationship_type": relationship_type,
                "permission_tier": permission_tier,
            })
        return patients_data

    @staticmethod
    async def get_patient_summary(
        db: AsyncSession, patient_id: uuid.UUID
    ) -> Dict[str, Any]:
        """Aggregate patient engagement, cognitive trends, compliance, and active alerts."""
        now = datetime.now(timezone.utc)
        seven_days_ago = now - timedelta(days=7)
        fourteen_days_ago = now - timedelta(days=14)

        # 1. Game sessions in last 14 days (7d metrics + daily trend series)
        game_stmt = select(GameSession).where(
            GameSession.patient_id == patient_id,
            GameSession.started_at >= fourteen_days_ago,
        )
        game_res = await db.execute(game_stmt)
        sessions_14d = game_res.scalars().all()

        def _aware(dt):
            if dt is None:
                return None
            if dt.tzinfo is None:
                return dt.replace(tzinfo=timezone.utc)
            return dt

        sessions_7d = [
            s for s in sessions_14d
            if _aware(s.started_at) is not None and _aware(s.started_at) >= seven_days_ago
        ]

        total_games_7d = len(sessions_7d)
        total_correct = sum(s.correct_count for s in sessions_7d)
        total_attempts = sum(s.attempts for s in sessions_7d)
        accuracy_7d = (total_correct / total_attempts * 100.0) if total_attempts > 0 else 0.0

        valid_times = [s.avg_response_time_ms for s in sessions_7d if s.avg_response_time_ms is not None]
        avg_response_time = (sum(valid_times) / len(valid_times)) if valid_times else 0.0

        # 2. Reminder compliance in last 7 days
        rem_stmt = select(ReminderEvent).where(
            ReminderEvent.patient_id == patient_id,
            ReminderEvent.scheduled_at >= seven_days_ago,
        )
        rem_res = await db.execute(rem_stmt)
        reminders_7d = rem_res.scalars().all()

        rem_total = len(reminders_7d)
        rem_acknowledged = sum(1 for r in reminders_7d if r.status == ReminderStatusEnum.ACKNOWLEDGED)
        rem_missed = sum(1 for r in reminders_7d if r.status in (ReminderStatusEnum.MISSED, ReminderStatusEnum.ESCALATED))
        compliance_pct = (rem_acknowledged / rem_total * 100.0) if rem_total > 0 else 100.0

        # 3. Active Alert Flags
        alerts_stmt = select(AlertFlag).where(
            AlertFlag.patient_id == patient_id,
            AlertFlag.acknowledged_at == None,
        ).order_by(AlertFlag.created_at.desc())
        alerts_res = await db.execute(alerts_stmt)
        active_alerts = alerts_res.scalars().all()

        alerts_list = []
        for a in active_alerts:
            alerts_list.append({
                "id": str(a.id),
                "trigger_type": a.trigger_type.value if hasattr(a.trigger_type, 'value') else str(a.trigger_type),
                "severity": a.severity.value if hasattr(a.severity, 'value') else str(a.severity),
                "summary": a.alert_summary,
                "created_at": a.created_at.isoformat() if a.created_at else None,
                "threshold_detail": a.threshold_detail,
            })

        # 4. Daily series + computed 14-day accuracy drop (clinically meaningful signal)
        by_day: Dict[str, list] = defaultdict(list)
        for s in sessions_14d:
            if s.started_at is None:
                continue
            started = s.started_at
            if started.tzinfo is None:
                started = started.replace(tzinfo=timezone.utc)
            by_day[started.date().isoformat()].append(s)

        daily_trends = []
        for i in range(13, -1, -1):
            day = (now - timedelta(days=i)).date().isoformat()
            day_sessions = by_day.get(day, [])
            attempts = sum(s.attempts or 0 for s in day_sessions)
            correct = sum(s.correct_count or 0 for s in day_sessions)
            times = [s.avg_response_time_ms for s in day_sessions if s.avg_response_time_ms is not None]
            daily_trends.append({
                "date": day,
                "games": len(day_sessions),
                "accuracy_pct": round((correct / attempts * 100.0), 1) if attempts else None,
                "avg_response_time_ms": round(sum(times) / len(times), 1) if times else None,
            })

        earlier = [
            s for s in sessions_14d
            if _aware(s.started_at) is not None and _aware(s.started_at) < seven_days_ago
        ]
        later = sessions_7d

        def _acc(rows):
            att = sum(s.attempts or 0 for s in rows)
            cor = sum(s.correct_count or 0 for s in rows)
            return (cor / att * 100.0) if att else None

        earlier_acc = _acc(earlier)
        later_acc = _acc(later)
        accuracy_drop_pct = None
        drop_20pct = False
        if earlier_acc and later_acc is not None and earlier_acc > 0:
            accuracy_drop_pct = round((earlier_acc - later_acc) / earlier_acc * 100.0, 1)
            drop_20pct = accuracy_drop_pct >= 20.0

        cognitive_drop_alert = False
        if total_games_7d >= 3 and accuracy_7d < 60.0:
            cognitive_drop_alert = True
        if drop_20pct:
            cognitive_drop_alert = True

        return {
            "patient_id": str(patient_id),
            "period": "last_7_days",
            "games_played": total_games_7d,
            "accuracy_pct": round(accuracy_7d, 1),
            "avg_response_time_ms": round(avg_response_time, 1),
            "reminders_total": rem_total,
            "reminders_acknowledged": rem_acknowledged,
            "reminders_missed": rem_missed,
            "compliance_pct": round(compliance_pct, 1),
            "active_alerts": alerts_list,
            "daily_trends": daily_trends,
            "accuracy_drop_pct": accuracy_drop_pct,
            "clinical_flags": {
                "cognitive_drop_detected": cognitive_drop_alert,
                "accuracy_dropped_20pct_over_2_weeks": drop_20pct,
                "high_missed_reminders": rem_missed >= 3,
            }
        }

"""Caregiver & Clinician Dashboard Analytics Service.

Provides:
- Multi-patient overview for ASHA workers & Family Caregivers.
- Cognitive performance trends (accuracy, avg response times over 7d/30d).
- Clinical summaries retain pooled ``accuracy_pct``, ``games_played``, and
  ``avg_response_time_ms`` keys and add ``metric_scope`` plus ``game_metrics``
  keyed by all four game types; each daily trend entry has the same detail.
- Reminder compliance metrics (% acknowledged, missed, escalated).
- Active AlertFlags / Risk notifications.
"""
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Any, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.models.all_models import (
    PatientProfile, CaregiverPatientLink, GameSession,
    ReminderEvent, ReminderSchedule, AlertFlag,
    GameTypeEnum, ReminderStatusEnum, PermissionTierEnum
)
from app.services.datetime_utils import iso_utc


GAME_METRIC_SCOPE = "all_completed_game_types"


def _utc_aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def naive_utc(value: datetime) -> datetime:
    return _utc_aware(value).replace(tzinfo=None)


def _game_type_value(game_type: Any) -> str:
    return game_type.value if hasattr(game_type, "value") else str(game_type)


def aggregate_sessions(sessions: List[GameSession]) -> Dict[str, Any]:
    attempts = sum(session.attempts or 0 for session in sessions)
    correct = sum(session.correct_count or 0 for session in sessions)
    response_times = [
        session.avg_response_time_ms
        for session in sessions
        if session.avg_response_time_ms is not None
    ]
    return {
        "games_played": len(sessions),
        "total_attempts": attempts,
        "correct_count": correct,
        "accuracy_pct": round(correct / attempts * 100.0, 1) if attempts else None,
        "avg_response_time_ms": (
            round(sum(response_times) / len(response_times), 1)
            if response_times
            else None
        ),
    }


def aggregate_by_game(sessions: List[GameSession]) -> Dict[str, Dict[str, Any]]:
    grouped: Dict[str, List[GameSession]] = {
        game_type.value: [] for game_type in GameTypeEnum
    }
    for session in sessions:
        grouped.setdefault(_game_type_value(session.game_type), []).append(session)
    return {
        game_type: aggregate_sessions(grouped[game_type])
        for game_type in grouped
    }


async def get_game_analytics(
    db: AsyncSession,
    patient_id: uuid.UUID,
    start: datetime,
    end: datetime,
) -> Dict[str, Any]:
    start_utc = naive_utc(start)
    end_utc = naive_utc(end)
    sessions: List[GameSession] = []
    if end_utc > start_utc:
        result = await db.execute(
            select(GameSession)
            .where(
                GameSession.patient_id == patient_id,
                GameSession.completed_at.is_not(None),
                GameSession.started_at >= start_utc,
                GameSession.started_at < end_utc,
                GameSession.completed_at < end_utc,
            )
            .order_by(GameSession.started_at.asc())
        )
        sessions = list(result.scalars().all())
    return {
        "sessions": sessions,
        "aggregate": aggregate_sessions(sessions),
        "by_game": aggregate_by_game(sessions),
    }


def build_daily_trends(
    sessions: List[GameSession],
    now: datetime,
    days: int,
    *,
    include_empty: bool = True,
    include_deltas: bool = False,
) -> List[Dict[str, Any]]:
    by_day: Dict[str, List[GameSession]] = defaultdict(list)
    for session in sessions:
        if session.started_at is None:
            continue
        by_day[_utc_aware(session.started_at).date().isoformat()].append(session)

    now_utc = _utc_aware(now)
    if include_empty:
        dates = [
            (now_utc.date() - timedelta(days=offset)).isoformat()
            for offset in range(days - 1, -1, -1)
        ]
    else:
        dates = sorted(by_day)

    trend: List[Dict[str, Any]] = []
    previous_accuracy: Optional[float] = None
    for date in dates:
        day_sessions = by_day.get(date, [])
        metrics = aggregate_sessions(day_sessions)
        entry: Dict[str, Any] = {
            "date": date,
            "games": metrics["games_played"],
            "accuracy_pct": metrics["accuracy_pct"],
            "avg_response_time_ms": metrics["avg_response_time_ms"],
            "game_metrics": aggregate_by_game(day_sessions),
        }
        if include_deltas and metrics["accuracy_pct"] is not None:
            if previous_accuracy is not None:
                entry["accuracy_delta_pct"] = round(
                    metrics["accuracy_pct"] - previous_accuracy, 1
                )
            previous_accuracy = metrics["accuracy_pct"]
        trend.append(entry)
    return trend


def accuracy_drop(
    earlier_accuracy: Optional[float], later_accuracy: Optional[float]
) -> tuple[Optional[float], bool]:
    if (
        earlier_accuracy is None
        or later_accuracy is None
        or earlier_accuracy <= 0
    ):
        return None, False
    drop_pct = round(
        (earlier_accuracy - later_accuracy) / earlier_accuracy * 100.0, 1
    )
    return drop_pct, drop_pct >= 20.0


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
        db: AsyncSession,
        patient_id: uuid.UUID,
        now: datetime | None = None,
    ) -> Dict[str, Any]:
        """Aggregate completed, bounded game metrics and caregiver activity."""
        now = _utc_aware(now or datetime.now(timezone.utc))
        seven_days_ago = now - timedelta(days=7)
        fourteen_days_ago = now - timedelta(days=14)
        analytics = await get_game_analytics(
            db, patient_id, fourteen_days_ago, now
        )
        sessions_14d = analytics["sessions"]
        sessions_7d = [
            session
            for session in sessions_14d
            if _utc_aware(session.started_at) >= seven_days_ago
        ]
        metrics_7d = aggregate_sessions(sessions_7d)
        total_games_7d = metrics_7d["games_played"]
        accuracy_7d = metrics_7d["accuracy_pct"]
        avg_response_time = metrics_7d["avg_response_time_ms"]

        rem_stmt = select(ReminderEvent).where(
            ReminderEvent.patient_id == patient_id,
            ReminderEvent.scheduled_at >= naive_utc(seven_days_ago),
            ReminderEvent.scheduled_at < naive_utc(now),
        )
        rem_res = await db.execute(rem_stmt)
        reminders_7d = rem_res.scalars().all()

        rem_total = len(reminders_7d)
        rem_acknowledged = sum(
            1
            for reminder in reminders_7d
            if reminder.status == ReminderStatusEnum.ACKNOWLEDGED
        )
        rem_missed = sum(
            1
            for reminder in reminders_7d
            if reminder.status
            in (ReminderStatusEnum.MISSED, ReminderStatusEnum.ESCALATED)
        )
        compliance_pct = (
            (rem_acknowledged / rem_total * 100.0) if rem_total > 0 else 100.0
        )

        alerts_stmt = select(AlertFlag).where(
            AlertFlag.patient_id == patient_id,
            AlertFlag.acknowledged_at == None,
        ).order_by(AlertFlag.created_at.desc())
        alerts_res = await db.execute(alerts_stmt)
        active_alerts = alerts_res.scalars().all()

        alerts_list = []
        for alert in active_alerts:
            alerts_list.append(
                {
                    "id": str(alert.id),
                    "trigger_type": (
                        alert.trigger_type.value
                        if hasattr(alert.trigger_type, "value")
                        else str(alert.trigger_type)
                    ),
                    "severity": (
                        alert.severity.value
                        if hasattr(alert.severity, "value")
                        else str(alert.severity)
                    ),
                    "summary": alert.alert_summary,
                    "created_at": iso_utc(alert.created_at),
                    "threshold_detail": alert.threshold_detail,
                }
            )

        daily_trends = build_daily_trends(sessions_14d, now, 14)
        earlier = [
            session
            for session in sessions_14d
            if _utc_aware(session.started_at) < seven_days_ago
        ]
        earlier_accuracy = aggregate_sessions(earlier)["accuracy_pct"]
        later_accuracy = metrics_7d["accuracy_pct"]
        accuracy_drop_pct, drop_20pct = accuracy_drop(
            earlier_accuracy, later_accuracy
        )

        cognitive_drop_alert = (
            total_games_7d >= 3
            and accuracy_7d is not None
            and accuracy_7d < 60.0
        ) or drop_20pct

        return {
            "patient_id": str(patient_id),
            "period": "last_7_days",
            "games_played": total_games_7d,
            "accuracy_pct": round(accuracy_7d, 1) if accuracy_7d is not None else 0.0,
            "avg_response_time_ms": (
                round(avg_response_time, 1)
                if avg_response_time is not None
                else 0.0
            ),
            "metric_scope": GAME_METRIC_SCOPE,
            "game_metrics": aggregate_by_game(sessions_7d),
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
            },
        }

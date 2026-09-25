"""Analytics correctness regressions for completed, bounded game sessions."""

import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.models.all_models import (
    ConsentRecord,
    ConsentTypeEnum,
    GameSession,
    GameTypeEnum,
    PatientProfile,
)
from app.models.user import RoleEnum, User
from app.services.alert_engine import AlertEngine
from app.services.dashboard_service import DashboardService
from app.services.report_service import ReportService


async def _make_patient(db_session, name="Analytics Patient"):
    owner = User(
        phone=f"+91{uuid.uuid4().int % 10**10}",
        password_hash="x",
        role=RoleEnum.PATIENT,
    )
    db_session.add(owner)
    await db_session.flush()
    patient = PatientProfile(user_id=owner.id, name=name, region="assam")
    db_session.add(patient)
    await db_session.flush()
    return patient, owner


def _session(
    patient,
    game_type,
    started_at,
    attempts,
    correct_count,
    avg_response_time_ms,
    completed_at=None,
):
    return GameSession(
        patient_id=patient.id,
        game_type=game_type,
        difficulty_level=1,
        attempts=attempts,
        correct_count=correct_count,
        incorrect_count=attempts - correct_count,
        avg_response_time_ms=avg_response_time_ms,
        started_at=started_at,
        completed_at=completed_at,
    )


async def _grant_game_consent(db_session, patient, owner):
    db_session.add(
        ConsentRecord(
            patient_id=patient.id,
            scope="game_data",
            consent_type=ConsentTypeEnum.PATIENT_SELF,
            grantor_id=owner.id,
        )
    )
    await db_session.flush()


async def _make_clinician(db_session):
    clinician = User(
        phone=f"+91{uuid.uuid4().int % 10**10}",
        password_hash="x",
        role=RoleEnum.CLINICIAN,
    )
    db_session.add(clinician)
    await db_session.flush()
    return clinician


@pytest.mark.asyncio
async def test_abandoned_session_does_not_affect_analytics(db_session):
    patient, _ = await _make_patient(db_session)
    now = datetime.now(timezone.utc)
    db_session.add_all(
        [
            _session(
                patient,
                GameTypeEnum.MATCH_IT,
                now - timedelta(hours=2),
                4,
                3,
                1000.0,
                now - timedelta(hours=1, minutes=50),
            ),
            _session(
                patient,
                GameTypeEnum.NUMBER_RECALL,
                now - timedelta(hours=1),
                100,
                0,
                999999.0,
            ),
        ]
    )
    await db_session.flush()

    summary = await DashboardService.get_patient_summary(db_session, patient.id)
    report = await ReportService.generate_weekly_clinical_summary(
        db_session, patient.id
    )
    alert_accuracy = await AlertEngine._week_accuracy(
        db_session, patient.id, now - timedelta(days=7), now
    )

    assert summary["games_played"] == 1
    assert summary["accuracy_pct"] == 75.0
    assert summary["avg_response_time_ms"] == 1000.0
    assert report["cognitive_metrics"]["total_sessions"] == 1
    assert report["cognitive_metrics"]["overall_accuracy_pct"] == 75.0
    assert report["cognitive_metrics"]["avg_response_time_ms"] == 1000.0
    assert alert_accuracy == 75.0


@pytest.mark.asyncio
async def test_per_game_metrics_and_legacy_aggregate_use_real_denominators(
    db_session,
):
    patient, owner = await _make_patient(db_session)
    now = datetime.now(timezone.utc)
    db_session.add_all(
        [
            _session(
                patient,
                GameTypeEnum.MATCH_IT,
                now - timedelta(hours=5),
                10,
                9,
                100.0,
                now - timedelta(hours=4, minutes=59),
            ),
            _session(
                patient,
                GameTypeEnum.MATCH_IT,
                now - timedelta(hours=4),
                2,
                1,
                300.0,
                now - timedelta(hours=3, minutes=59),
            ),
            _session(
                patient,
                GameTypeEnum.ROUTINE_SEQUENCING,
                now - timedelta(hours=3),
                4,
                3,
                500.0,
                now - timedelta(hours=2, minutes=59),
            ),
            _session(
                patient,
                GameTypeEnum.NUMBER_RECALL,
                now - timedelta(hours=2),
                1,
                0,
                900.0,
                now - timedelta(hours=1, minutes=59),
            ),
            _session(
                patient,
                GameTypeEnum.ODD_ONE_OUT,
                now - timedelta(hours=1),
                2,
                2,
                700.0,
                now - timedelta(minutes=59),
            ),
        ]
    )
    await _grant_game_consent(db_session, patient, owner)
    clinician = await _make_clinician(db_session)
    await db_session.flush()

    summary = await DashboardService.get_patient_summary(db_session, patient.id)
    report = await ReportService.generate_weekly_clinical_summary(
        db_session, patient.id
    )
    from app.routes.games import get_patient_stats

    stats = await get_patient_stats(
        str(patient.id), days=14, current_user=clinician, db=db_session
    )

    expected = {
        "match_it": (2, 12, 10, 83.3, 200.0),
        "routine_sequencing": (1, 4, 3, 75.0, 500.0),
        "number_recall": (1, 1, 0, 0.0, 900.0),
        "odd_one_out": (1, 2, 2, 100.0, 700.0),
    }
    for game_type, (games, attempts, correct, accuracy, response_time) in expected.items():
        metric = summary["game_metrics"][game_type]
        assert metric["games_played"] == games
        assert metric["total_attempts"] == attempts
        assert metric["correct_count"] == correct
        assert metric["accuracy_pct"] == accuracy
        assert metric["avg_response_time_ms"] == response_time

    assert summary["games_played"] == 5
    assert summary["accuracy_pct"] == 78.9
    assert summary["avg_response_time_ms"] == 500.0
    assert summary["metric_scope"] == "all_completed_game_types"
    assert report["cognitive_metrics"]["game_metrics"] == summary["game_metrics"]
    assert report["cognitive_metrics"]["overall_accuracy_pct"] == 78.9
    assert report["cognitive_metrics"]["avg_response_time_ms"] == 500.0
    assert report["cognitive_metrics"]["metric_scope"] == "all_completed_game_types"
    assert stats["overall"] == {
        "sessions": 5,
        "accuracy_pct": 78.9,
        "avg_response_time_ms": 500.0,
        "metric_scope": "all_completed_game_types",
    }
    assert stats["game_metrics"] == summary["game_metrics"]


@pytest.mark.asyncio
async def test_future_sessions_are_excluded_from_every_analytics_window(db_session):
    patient, owner = await _make_patient(db_session)
    now = datetime.now(timezone.utc)
    db_session.add_all(
        [
            _session(
                patient,
                GameTypeEnum.MATCH_IT,
                now - timedelta(days=10),
                10,
                8,
                400.0,
                now - timedelta(days=10) + timedelta(minutes=1),
            ),
            _session(
                patient,
                GameTypeEnum.MATCH_IT,
                now - timedelta(days=1),
                10,
                8,
                400.0,
                now - timedelta(days=1) + timedelta(minutes=1),
            ),
            _session(
                patient,
                GameTypeEnum.ODD_ONE_OUT,
                now + timedelta(days=1),
                100,
                0,
                1.0,
                now + timedelta(days=1) + timedelta(minutes=1),
            ),
        ]
    )
    await _grant_game_consent(db_session, patient, owner)
    clinician = await _make_clinician(db_session)
    await db_session.flush()

    summary = await DashboardService.get_patient_summary(db_session, patient.id)
    report = await ReportService.generate_weekly_clinical_summary(
        db_session, patient.id
    )
    alert_result = await AlertEngine.evaluate_patient(
        db_session, patient.id, now=now
    )
    from app.routes.games import get_patient_stats

    stats = await get_patient_stats(
        str(patient.id), days=14, current_user=clinician, db=db_session
    )

    assert summary["games_played"] == 1
    assert summary["accuracy_pct"] == 80.0
    assert sum(day["games"] for day in summary["daily_trends"]) == 2
    assert report["cognitive_metrics"]["total_sessions"] == 1
    assert report["cognitive_metrics"]["overall_accuracy_pct"] == 80.0
    assert stats["overall"]["sessions"] == 2
    assert stats["overall"]["accuracy_pct"] == 80.0
    assert alert_result["alerts_raised"] == []
    assert summary["accuracy_drop_pct"] == 0.0
    assert summary["clinical_flags"]["cognitive_drop_detected"] is False

    future_only, future_owner = await _make_patient(db_session, "Future Only")
    await _grant_game_consent(db_session, future_only, future_owner)
    db_session.add(
        _session(
            future_only,
            GameTypeEnum.MATCH_IT,
            now + timedelta(days=1),
            10,
            0,
            100.0,
            now + timedelta(days=1) + timedelta(minutes=1),
        )
    )
    await db_session.flush()
    pass_stats = await AlertEngine.run_hourly_pass(db_session, now=now)
    assert pass_stats["patients_evaluated"] == 0


@pytest.mark.asyncio
async def test_dashboard_report_and_alert_use_the_same_completed_window(db_session):
    patient, _ = await _make_patient(db_session)
    now = datetime.now(timezone.utc)
    sessions = []
    for index in range(3):
        started = now - timedelta(days=10) + timedelta(hours=index)
        sessions.append(
            _session(
                patient,
                GameTypeEnum.MATCH_IT,
                started,
                10,
                9,
                1500.0,
                started + timedelta(minutes=1),
            )
        )
    for index in range(3):
        started = now - timedelta(days=1) + timedelta(hours=index)
        sessions.append(
            _session(
                patient,
                GameTypeEnum.MATCH_IT,
                started,
                10,
                5,
                3500.0,
                started + timedelta(minutes=1),
            )
        )
    sessions.append(
        _session(
            patient,
            GameTypeEnum.NUMBER_RECALL,
            now - timedelta(hours=1),
            100,
            0,
            1.0,
        )
    )
    db_session.add_all(sessions)
    await db_session.flush()

    summary = await DashboardService.get_patient_summary(db_session, patient.id)
    report = await ReportService.generate_weekly_clinical_summary(
        db_session, patient.id
    )
    alert_result = await AlertEngine.evaluate_patient(
        db_session, patient.id, now=now
    )
    cognitive_alerts = [
        alert
        for alert in alert_result["alerts_raised"]
        if alert.trigger_type.value == "cognitive_score_dip"
    ]

    assert summary["accuracy_pct"] == 50.0
    assert report["cognitive_metrics"]["overall_accuracy_pct"] == 50.0
    assert report["cognitive_metrics"]["total_sessions"] == 3
    assert len(cognitive_alerts) == 1
    detail = cognitive_alerts[0].threshold_detail
    assert detail["earlier_accuracy_pct"] == 90.0
    assert detail["later_accuracy_pct"] == 50.0
    assert detail["drop_pct"] == summary["accuracy_drop_pct"] == 44.4

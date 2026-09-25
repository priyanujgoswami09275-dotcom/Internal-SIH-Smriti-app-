"""P6 alert engine + P7 weekly reports — rules, dedup, job, endpoint."""
import uuid
from datetime import datetime, timedelta, timezone
from uuid import UUID

import pytest
from sqlalchemy import select

from app.models.all_models import (
    AlertFlag, AlertTriggerTypeEnum, GameSession, GameTypeEnum,
    PatientProfile, ReminderEvent, ReminderSchedule, ReminderStatusEnum,
    ReminderTypeEnum, WeeklyReport,
)
from app.models.user import RoleEnum, User
from app.services.alert_engine import AlertEngine
from app.services.report_service import ReportService

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
COMPLIANCE = "/api/v1/compliance"
REPORTS = "/api/v1/reports"
GAMES = "/api/v1/games"


async def _mk_patient(db_session, name="Engine Patient"):
    u = User(phone=f"+91{uuid.uuid4().int % 10**10}", password_hash="x", role=RoleEnum.PATIENT)
    db_session.add(u)
    await db_session.flush()
    p = PatientProfile(user_id=u.id, name=name, region="assam")
    db_session.add(p)
    await db_session.flush()
    return p, u


# ---------------- P6: cognitive-drop rule ----------------


@pytest.mark.asyncio
async def test_cognitive_drop_raises_deduped_alert(db_session):
    patient, user = await _mk_patient(db_session)
    now = datetime.now(timezone.utc)
    week_ago = now - timedelta(days=10)
    # earlier week: 90% accuracy
    for i in range(3):
        db_session.add(GameSession(patient_id=patient.id, game_type=GameTypeEnum.MATCH_IT,
            difficulty_level=1, attempts=10, correct_count=9, incorrect_count=1,
            avg_response_time_ms=1500.0, started_at=week_ago + timedelta(hours=i),
            completed_at=week_ago + timedelta(hours=i, minutes=1)))
    # current week: 50% accuracy -> (90-50)/90 = 44% drop
    for i in range(3):
        db_session.add(GameSession(patient_id=patient.id, game_type=GameTypeEnum.MATCH_IT,
            difficulty_level=1, attempts=10, correct_count=5, incorrect_count=5,
            avg_response_time_ms=3500.0, started_at=now - timedelta(hours=i + 1),
            completed_at=now - timedelta(hours=i, minutes=59)))
    await db_session.flush()

    result = await AlertEngine.evaluate_patient(db_session, patient.id, now=now)
    flags = [a for a in result["alerts_raised"]
             if a.trigger_type == AlertTriggerTypeEnum.COGNITIVE_SCORE_DIP]
    assert len(flags) == 1
    assert flags[0].severity.value == "warning"
    assert "44.4" in flags[0].alert_summary or "44" in flags[0].alert_summary

    # second evaluation within 24h dedupes (no new row)
    result2 = await AlertEngine.evaluate_patient(db_session, patient.id, now=now)
    flags2 = [a for a in result2["alerts_raised"]
              if a.trigger_type == AlertTriggerTypeEnum.COGNITIVE_SCORE_DIP]
    assert flags2 == []


@pytest.mark.asyncio
async def test_stable_accuracy_raises_no_cognitive_alert(db_session):
    patient, user = await _mk_patient(db_session)
    now = datetime.now(timezone.utc)
    for i in range(3):
        db_session.add(GameSession(patient_id=patient.id, game_type=GameTypeEnum.MATCH_IT,
            difficulty_level=1, attempts=10, correct_count=8, incorrect_count=2,
            avg_response_time_ms=2000.0, started_at=now - timedelta(days=10, hours=i),
            completed_at=now - timedelta(days=10, hours=i) + timedelta(minutes=1)))
        db_session.add(GameSession(patient_id=patient.id, game_type=GameTypeEnum.MATCH_IT,
            difficulty_level=1, attempts=10, correct_count=8, incorrect_count=2,
            avg_response_time_ms=2000.0, started_at=now - timedelta(hours=i + 1),
            completed_at=now - timedelta(hours=i, minutes=59)))
    await db_session.flush()

    result = await AlertEngine.evaluate_patient(db_session, patient.id, now=now)
    dips = [a for a in result["alerts_raised"]
            if a.trigger_type == AlertTriggerTypeEnum.COGNITIVE_SCORE_DIP]
    assert dips == []


@pytest.mark.asyncio
async def test_hourly_pass_covers_all_active_patients(db_session):
    patient, user = await _mk_patient(db_session)
    # The pass derives cognitive health signals, so it skips patients without
    # active health_data consent (Wave 5 purpose limitation).
    from app.models.all_models import ConsentRecord
    db_session.add(ConsentRecord(
        patient_id=patient.id, scope="all", consent_type="patient_self",
        grantor_id=user.id))
    now = datetime.now(timezone.utc)
    db_session.add(GameSession(patient_id=patient.id, game_type=GameTypeEnum.MATCH_IT,
        difficulty_level=1, attempts=10, correct_count=9, incorrect_count=1,
        avg_response_time_ms=1000.0, started_at=now, completed_at=now))
    await db_session.flush()
    stats = await AlertEngine.run_hourly_pass(db_session)
    assert stats["patients_evaluated"] >= 1


# ---------------- P7: weekly reports ----------------


@pytest.mark.asyncio
async def test_weekly_report_saved_idempotent_and_latest(client, db_session):
    from app.tests.conftest import provision_staff_user

    user = await provision_staff_user()
    login = await client.post(f"{AUTH}/login",
        json={"phone": user["phone"], "password": "Passw0rd123"})
    assert login.status_code == 200, login.text
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    from app.tests.conftest import create_consented_patient

    prof = await create_consented_patient(client, "Report Patient")
    pid = prof["id"]

    # run the "Sunday job" body directly
    stats = await ReportService.generate_reports_for_all_patients(db_session)
    assert stats["created"] >= 1

    # second run same week updates in place (no duplicate rows)
    stats2 = await ReportService.generate_reports_for_all_patients(db_session)
    rows = (await db_session.execute(
        select(WeeklyReport).where(WeeklyReport.patient_id == UUID(pid))
    )).scalars().all()
    assert len(rows) == 1
    assert stats2["updated"] >= 1

    # endpoint returns it
    resp = await client.get(f"{REPORTS}/patients/{pid}/latest", headers=h)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["report"]["patient_id"] == pid
    assert body["report"]["cognitive_metrics"]["total_sessions"] >= 0


@pytest.mark.asyncio
async def test_latest_endpoint_generates_on_demand_when_job_never_ran(client, db_session):
    from app.tests.conftest import provision_staff_user

    user = await provision_staff_user()
    login = await client.post(f"{AUTH}/login",
        json={"phone": user["phone"], "password": "Passw0rd123"})
    assert login.status_code == 200, login.text
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    from app.tests.conftest import create_consented_patient

    prof = await create_consented_patient(client, "Fresh Patient")
    pid = prof["id"]

    resp = await client.get(f"{REPORTS}/patients/{pid}/latest", headers=h)
    assert resp.status_code == 200
    assert resp.json()["report"]["patient_id"] == pid


def test_next_sunday_midnight_anchor():
    from app.jobs import _next_sunday_midnight
    # Wed 2026-09-09 15:00 UTC -> next Sunday 2026-09-13 00:00
    now = datetime(2026, 9, 9, 15, 0, tzinfo=timezone.utc)
    nxt = _next_sunday_midnight(now)
    assert nxt.weekday() == 6 and nxt.hour == 0 and nxt > now
    # Sunday 00:00 itself -> the FOLLOWING Sunday
    sun = datetime(2026, 9, 13, 0, 0, tzinfo=timezone.utc)
    nxt2 = _next_sunday_midnight(sun)
    assert nxt2 == sun + timedelta(days=7)

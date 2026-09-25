"""Wave 5C — jobs consent check: weekly-report and alert-engine passes skip
patients without active health_data consent (purpose limitation)."""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.models.all_models import (
    ConsentRecord, GameSession, GameTypeEnum, PatientProfile, User, WeeklyReport,
)
from app.services.alert_engine import AlertEngine
from app.services.report_service import ReportService


async def _mk_patient(db, name):
    u = User(phone=f"+91{uuid.uuid4().int % 10**10}", password_hash="x", role="patient")
    db.add(u)
    await db.flush()
    p = PatientProfile(user_id=u.id, name=name, region="assam")
    db.add(p)
    await db.flush()
    return p, u


async def _grant(db, patient, user, scope="all"):
    db.add(ConsentRecord(
        patient_id=patient.id, scope=scope, consent_type="patient_self",
        grantor_id=user.id))
    await db.flush()


def _session_for(patient):
    return GameSession(
        patient_id=patient.id, game_type=GameTypeEnum.MATCH_IT, difficulty_level=1,
        attempts=10, correct_count=9, incorrect_count=1, avg_response_time_ms=1000.0,
        started_at=datetime.now(timezone.utc) - timedelta(hours=1),
        completed_at=datetime.now(timezone.utc),
    )


@pytest.mark.asyncio
async def test_alert_pass_skips_unconsented_patient(db_session):
    """A patient with sessions but NO consent is never evaluated."""
    unconsented, _ = await _mk_patient(db_session, "No Consent")
    consented, c_user = await _mk_patient(db_session, "Consented")
    await _grant(db_session, consented, c_user)
    db_session.add_all([_session_for(unconsented), _session_for(consented)])
    await db_session.flush()

    stats = await AlertEngine.run_hourly_pass(db_session)
    assert stats["patients_evaluated"] == 1, "only the consented patient is evaluated"


@pytest.mark.asyncio
async def test_alert_pass_revoked_consent_skipped(db_session):
    """A revoked consent record does not re-enable the pass."""
    p, u = await _mk_patient(db_session, "Revoked")
    db_session.add(ConsentRecord(
        patient_id=p.id, scope="all", consent_type="patient_self",
        grantor_id=u.id, revoked_at=datetime.now(timezone.utc)))
    db_session.add(_session_for(p))
    await db_session.flush()

    stats = await AlertEngine.run_hourly_pass(db_session)
    assert stats["patients_evaluated"] == 0


@pytest.mark.asyncio
async def test_weekly_reports_pass_skips_unconsented_patient(db_session):
    """The Sunday job persists nothing for a patient without health_data consent."""
    unconsented, _ = await _mk_patient(db_session, "No Report")
    consented, c_user = await _mk_patient(db_session, "Reported")
    await _grant(db_session, consented, c_user)
    db_session.add_all([_session_for(unconsented), _session_for(consented)])
    await db_session.flush()

    result = await ReportService.generate_reports_for_all_patients(db_session)
    assert result["patients"] == 1, "only the consented patient gets a report"

    rows = (await db_session.execute(select(WeeklyReport))).scalars().all()
    assert all(r.patient_id == consented.id for r in rows)

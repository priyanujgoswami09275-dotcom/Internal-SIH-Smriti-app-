"""P5 — GET /games/patients/{id}/stats: accuracy + response-time trends."""
import uuid
from datetime import datetime, timezone

import pytest

from app.models.all_models import GameSession, GameTypeEnum

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
GAMES = "/api/v1/games"
COMPLIANCE = "/api/v1/compliance"


async def _clinician_patient(client, db_session):
    from app.tests.conftest import provision_staff_user

    user = await provision_staff_user()
    login = await client.post(f"{AUTH}/login",
        json={"phone": user["phone"], "password": "Passw0rd123"})
    assert login.status_code == 200, login.text
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    from app.tests.conftest import create_consented_patient

    prof = await create_consented_patient(client, "Stats Patient", scope="game_data")
    return h, prof["id"]


@pytest.mark.asyncio
async def test_stats_trend_and_deltas(client, db_session):
    from app.models.all_models import PatientProfile
    from app.models.user import User, RoleEnum

    h, pid = await _clinician_patient(client, db_session)
    pu = (await db_session.execute(
        __import__("sqlalchemy").select(User).where(User.phone.like("+91%"))
    )).scalars().first()  # any user row to own the session rows
    # simpler: fetch the patient row to satisfy FK via its profile
    pat = (await db_session.execute(
        __import__("sqlalchemy").select(PatientProfile).where(PatientProfile.id == __import__("uuid").UUID(pid))
    )).scalar_one()

    now = datetime.now(timezone.utc)
    # day 1: 8/10 correct; day 2: 5/10 -> a visible drop
    db_session.add(GameSession(patient_id=pat.id, game_type=GameTypeEnum.MATCH_IT,
        difficulty_level=1, attempts=10, correct_count=8, incorrect_count=2,
        avg_response_time_ms=2000.0, started_at=now.replace(hour=9), completed_at=now))
    db_session.add(GameSession(patient_id=pat.id, game_type=GameTypeEnum.MATCH_IT,
        difficulty_level=1, attempts=10, correct_count=5, incorrect_count=5,
        avg_response_time_ms=3000.0, started_at=now, completed_at=now))
    await db_session.commit()

    r = await client.get(f"{GAMES}/patients/{pid}/stats?days=14", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["overall"]["sessions"] == 2
    assert body["overall"]["accuracy_pct"] == 65.0
    assert body["overall"]["avg_response_time_ms"] == 2500.0
    assert len(body["trend"]) == 1  # both sessions fall on today
    t = body["trend"][0]
    assert t["games"] == 2
    assert t["accuracy_pct"] == 65.0


@pytest.mark.asyncio
async def test_stats_requires_clinical_tier(client):
    """A basic-tier family caregiver is blocked from raw stats (dashboard
    already serves them a filtered view)."""
    h, pid = await _clinician_patient(client, None)
    # family caregiver with a BASIC-tier link cannot use the clinical endpoint
    r = await client.post(f"{AUTH}/register", json={
        "phone": f"+91{uuid.uuid4().int % 10**10}",
        "email": f"{uuid.uuid4().hex[:8]}@test.in",
        "password": "Passw0rd123", "role": "family_caregiver", "preferred_language": "english"})
    login = await client.post(f"{AUTH}/login",
        json={"phone": r.json()["phone"], "password": "Passw0rd123"})
    fh = {"Authorization": f"Bearer {login.json()['access_token']}"}
    resp = await client.get(f"{GAMES}/patients/{pid}/stats", headers=fh)
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_stats_empty_window(client, db_session):
    h, pid = await _clinician_patient(client, db_session)
    r = await client.get(f"{GAMES}/patients/{pid}/stats", headers=h)
    assert r.status_code == 200
    assert r.json()["overall"]["sessions"] == 0
    assert r.json()["overall"]["accuracy_pct"] is None
    assert r.json()["trend"] == []

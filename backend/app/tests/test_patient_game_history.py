import uuid
from datetime import datetime

import pytest
from sqlalchemy import select

from app.models.all_models import AuditLog, GameSession, GameTypeEnum


async def _account(client, *, consent=True):
    phone = f"+91{uuid.uuid4().int % 10**10}"
    registered = await client.post(
        "/api/v1/auth/register",
        json={
            "phone": phone,
            "password": "Passw0rd123",
            "role": "patient",
            "preferred_language": "english",
        },
    )
    assert registered.status_code == 201, registered.text
    login = await client.post(
        "/api/v1/auth/login",
        json={"phone": phone, "password": "Passw0rd123"},
    )
    assert login.status_code == 200, login.text
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    me = await client.get("/api/v1/auth/me", headers=headers)
    assert me.status_code == 200, me.text
    profile = await client.post(
        "/api/v1/patients",
        headers=headers,
        json={"name": "History Patient", "region": "assam"},
    )
    assert profile.status_code == 201, profile.text
    if consent:
        granted = await client.post(
            "/api/v1/compliance/consent",
            headers=headers,
            json={
                "patient_id": profile.json()["id"],
                "consent_type": "patient_self",
                "scope": "game_data",
            },
        )
        assert granted.status_code == 200, granted.text
    return {
        "headers": headers,
        "user_id": uuid.UUID(me.json()["id"]),
        "profile": profile.json(),
    }


async def _session(
    db,
    patient_id,
    *,
    session_id,
    game_type,
    score,
    attempts,
    accuracy,
    completed_at,
):
    row = GameSession(
        id=session_id,
        patient_id=patient_id,
        game_type=game_type,
        difficulty_level=2,
        started_at=datetime(2026, 9, 24, 9, 0),
        completed_at=completed_at,
        attempts=attempts,
        correct_count=score,
        incorrect_count=attempts - score,
        accuracy_pct=accuracy,
        avg_response_time_ms=1250.0,
    )
    db.add(row)
    await db.commit()
    return row


@pytest.mark.asyncio
async def test_patient_history_returns_only_owned_recent_sessions(client, db_session):
    owner = await _account(client)
    other = await _account(client)
    owner_id = uuid.UUID(owner["profile"]["id"])
    other_id = uuid.UUID(other["profile"]["id"])
    owner_session = uuid.uuid4()
    other_session = uuid.uuid4()

    await _session(
        db_session,
        owner_id,
        session_id=owner_session,
        game_type=GameTypeEnum.MATCH_IT,
        score=7,
        attempts=8,
        accuracy=87.5,
        completed_at=datetime(2026, 9, 25, 10, 30),
    )
    await _session(
        db_session,
        other_id,
        session_id=other_session,
        game_type=GameTypeEnum.NUMBER_RECALL,
        score=3,
        attempts=4,
        accuracy=75.0,
        completed_at=datetime(2026, 9, 25, 11, 0),
    )

    response = await client.get(
        "/api/v1/games/me/history?limit=10", headers=owner["headers"]
    )

    assert response.status_code == 200, response.text
    assert response.json() == [
        {
            "session_id": str(owner_session),
            "game_type": "match_it",
            "difficulty_level": 2,
            "score": 7,
            "total_attempts": 8,
            "accuracy_pct": 87.5,
            "avg_response_time_ms": 1250.0,
            "completed_at": "2026-09-25T10:30:00Z",
        }
    ]


@pytest.mark.asyncio
async def test_patient_history_is_audited_for_the_owner(client, db_session):
    owner = await _account(client)
    patient_id = uuid.UUID(owner["profile"]["id"])
    await _session(
        db_session,
        patient_id,
        session_id=uuid.uuid4(),
        game_type=GameTypeEnum.ROUTINE_SEQUENCING,
        score=3,
        attempts=3,
        accuracy=100.0,
        completed_at=datetime(2026, 9, 25, 12, 0),
    )

    response = await client.get("/api/v1/games/me/history", headers=owner["headers"])
    assert response.status_code == 200, response.text

    audit = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.user_id == owner["user_id"],
                AuditLog.resource_type == "game_history",
                AuditLog.resource_id == patient_id,
            )
        )
    ).scalar_one()
    assert audit.action.value == "read"


@pytest.mark.asyncio
async def test_patient_history_requires_owner_consent_and_stays_owner_scoped(client):
    owner = await _account(client, consent=False)
    other = await _account(client)

    own_without_consent = await client.get(
        "/api/v1/games/me/history", headers=owner["headers"]
    )
    assert own_without_consent.status_code == 403

    cross_patient = await client.get(
        f"/api/v1/games/patients/{other['profile']['id']}/history",
        headers=owner["headers"],
    )
    assert cross_patient.status_code == 403

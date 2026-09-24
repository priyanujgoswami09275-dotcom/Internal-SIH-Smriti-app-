import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.models.all_models import (
    AlertFlag,
    AlertSeverityEnum,
    AlertTriggerTypeEnum,
    GameSession,
    GameTypeEnum,
)

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
DASHBOARD = "/api/v1/dashboard"

BASIC_SUMMARY_KEYS = {
    "patient_id",
    "patient_name",
    "period",
    "games_played",
    "reminders_total",
    "reminders_acknowledged",
    "reminders_missed",
    "compliance_pct",
    "permission_tier",
    "view",
}

CLINICAL_SUMMARY_KEYS = {
    "patient_id",
    "period",
    "games_played",
    "accuracy_pct",
    "avg_response_time_ms",
    "reminders_total",
    "reminders_acknowledged",
    "reminders_missed",
    "compliance_pct",
    "active_alerts",
    "daily_trends",
    "accuracy_drop_pct",
    "clinical_flags",
    "permission_tier",
    "view",
}


async def _register(client, role):
    response = await client.post(
        f"{AUTH}/register",
        json={
            "phone": f"+91{uuid.uuid4().int % 10**10}",
            "password": "Passw0rd123",
            "role": role,
            "preferred_language": "english",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _login(client, phone):
    response = await client.post(
        f"{AUTH}/login",
        json={"phone": phone, "password": "Passw0rd123"},
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


async def _create_basic_family_case(client, db_session):
    patient_user = await _register(client, "patient")
    patient_headers = await _login(client, patient_user["phone"])
    profile_response = await client.post(
        PATIENTS,
        headers=patient_headers,
        json={"name": "Allowlist Patient", "region": "assam"},
    )
    assert profile_response.status_code == 201, profile_response.text
    profile = profile_response.json()

    family_user = await _register(client, "family_caregiver")
    family_headers = await _login(client, family_user["phone"])
    me_response = await client.get(f"{AUTH}/me", headers=family_headers)
    assert me_response.status_code == 200, me_response.text
    link_response = await client.post(
        f"{PATIENTS}/{profile['id']}/caregivers",
        headers=patient_headers,
        json={
            "caregiver_id": me_response.json()["id"],
            "relationship_type": "family",
        },
    )
    assert link_response.status_code == 201, link_response.text
    assert link_response.json()["permission_tier"] == "basic"

    now = datetime.now(timezone.utc)
    db_session.add(
        GameSession(
            patient_id=uuid.UUID(profile["id"]),
            game_type=GameTypeEnum.MATCH_IT,
            difficulty_level=1,
            attempts=10,
            correct_count=5,
            incorrect_count=5,
            avg_response_time_ms=2000.0,
            started_at=now - timedelta(hours=1),
        )
    )
    db_session.add(
        AlertFlag(
            patient_id=uuid.UUID(profile["id"]),
            trigger_type=AlertTriggerTypeEnum.COGNITIVE_SCORE_DIP,
            severity=AlertSeverityEnum.WARNING,
            alert_summary="Possible cognitive decline",
            threshold_detail={"drop_pct": 25},
        )
    )
    await db_session.flush()
    return profile, family_headers, family_user


@pytest.mark.asyncio
async def test_basic_summary_uses_allowlist_and_hides_clinical_data(
    client, db_session
):
    profile, family_headers, family_user = await _create_basic_family_case(
        client, db_session
    )

    summary_response = await client.get(
        f"{DASHBOARD}/patients/{profile['id']}/summary", headers=family_headers
    )

    assert summary_response.status_code == 200, summary_response.text
    body = summary_response.json()
    assert set(body) == BASIC_SUMMARY_KEYS
    assert body["patient_name"] == "Allowlist Patient"
    assert body["view"] == "basic"
    assert body["permission_tier"] == "basic"
    for key in (
        "active_alerts",
        "clinical_flags",
        "cognitive_baseline",
        "accuracy_pct",
        "avg_response_time_ms",
        "daily_trends",
        "accuracy_drop_pct",
    ):
        assert key not in body

    roster_response = await client.get(
        f"{DASHBOARD}/caregivers/{family_user['id']}/patients",
        headers=family_headers,
    )
    assert roster_response.status_code == 200, roster_response.text
    assert roster_response.json()[0]["patient_id"] == profile["id"]
    assert "cognitive_baseline" not in roster_response.json()[0]


@pytest.mark.asyncio
async def test_clinician_summary_retains_full_clinical_payload(client, db_session):
    profile, _, _ = await _create_basic_family_case(client, db_session)
    from app.tests.conftest import provision_staff_user

    clinician = await provision_staff_user(role="clinician")
    clinician_headers = await _login(client, clinician["phone"])

    summary_response = await client.get(
        f"{DASHBOARD}/patients/{profile['id']}/summary",
        headers=clinician_headers,
    )

    assert summary_response.status_code == 200, summary_response.text
    body = summary_response.json()
    assert set(body) == CLINICAL_SUMMARY_KEYS
    assert body["view"] == "clinical"
    assert body["permission_tier"] == "clinical"
    assert body["accuracy_pct"] == 50.0
    assert body["avg_response_time_ms"] == 2000.0
    assert body["active_alerts"][0]["summary"] == "Possible cognitive decline"
    assert len(body["daily_trends"]) == 14
    assert "patient_name" not in body

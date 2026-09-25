from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.all_models import DifficultyAdjustmentLog, GameSession, GameTypeEnum, PatientProfile
from app.services import difficulty_engine
from app.tests.conftest import create_consented_patient, provision_staff_user

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
COMPLIANCE = "/api/v1/compliance"
GAMES = "/api/v1/games"


async def _staff_headers(client):
    staff = await provision_staff_user()
    login = await client.post("/api/v1/auth/login", json={
        "phone": staff["phone"], "password": "Passw0rd123"})
    assert login.status_code == 200, login.text
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


async def test_evaluate_requires_active_game_data_consent(client):
    owner = await client.post("/api/v1/auth/register", json={
        "phone": f"+91{uuid4().int % 10**10}", "password": "Passw0rd123",
        "role": "patient", "preferred_language": "english"})
    assert owner.status_code == 201, owner.text
    login = await client.post("/api/v1/auth/login", json={
        "phone": owner.json()["phone"], "password": "Passw0rd123"})
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    profile = await client.post("/api/v1/patients", headers=headers,
                                json={"name": "No Consent", "region": "assam"})
    assert profile.status_code == 201, profile.text
    staff_headers = await _staff_headers(client)
    denied = await client.post(
        "/api/v1/games/difficulty/evaluate",
        params={"patient_id": profile.json()["id"], "game_type": "match_it",
                "current_difficulty": 1},
        headers=staff_headers)
    assert denied.status_code == 403
    assert "consent" in denied.json()["detail"].lower()


async def test_evaluate_succeeds_with_consent_and_stays_rule_sourced(client):
    profile = await create_consented_patient(client, "Consented Eval", scope="game_data")
    staff_headers = await _staff_headers(client)
    allowed = await client.post(
        "/api/v1/games/difficulty/evaluate",
        params={"patient_id": profile["id"], "game_type": "match_it",
                "current_difficulty": 1},
        headers=staff_headers)
    assert allowed.status_code == 200, allowed.text
    assert allowed.json()["source"] == "rule_fallback"


@pytest.mark.parametrize("accuracies,current,expected", [
    ([], 1, None), ([90], 1, None), ([40, 40], 2, 1),
    ([85, 85, 85], 1, None), ([50, 50], 2, None),
    ([86, 86, 86], 1, 2), ([99, 99, 99], 3, None), ([20, 20], 1, None),
])
@pytest.mark.parametrize("probability", [0.01, 0.99])
async def test_rules_unchanged_and_every_evaluation_audited(db_session, monkeypatch, accuracies, current, expected, probability):
    patient = PatientProfile(name="Shadow test")
    db_session.add(patient)
    await db_session.flush()
    now = datetime.now(timezone.utc)
    for i, accuracy in enumerate(accuracies):
        db_session.add(GameSession(patient_id=patient.id, game_type=GameTypeEnum.MATCH_IT,
                                   difficulty_level=current, accuracy_pct=accuracy,
                                   started_at=now - timedelta(days=i + 1, seconds=60),
                                   completed_at=now - timedelta(days=i + 1)))
    await db_session.commit()
    async def prediction(*args, **kwargs):
        return dict(shadow_probability=probability, shadow_model_version="test-candidate", shadow_reason="predicted")
    monkeypatch.setattr(difficulty_engine, "evaluate_shadow", prediction, raising=False)
    result = await difficulty_engine.evaluate_difficulty(db_session, patient.id, GameTypeEnum.MATCH_IT, current)
    assert result["new_difficulty"] == expected
    assert result["source"] == "rule_fallback"
    assert result["rule_version"] == "rules-85-50-v1"
    log = (await db_session.execute(select(DifficultyAdjustmentLog))).scalar_one()
    assert log.source == "rule_fallback"
    assert log.old_difficulty == current
    assert log.new_difficulty == (expected or current)
    assert log.result == ("hold" if expected is None else "raise" if expected > current else "lower")
    assert log.shadow_probability == probability
    assert log.shadow_model_version == "test-candidate"
    assert log.reason == result["reason"]


async def test_custom_strategy_keeps_public_api_and_truthful_provenance(db_session, monkeypatch):
    class Custom(difficulty_engine.DifficultyStrategy):
        async def calculate_adjustment(self, db, patient_id, game_type, current_difficulty, recent_sessions):
            return 3

    async def forbidden(*args, **kwargs):
        raise AssertionError("Custom strategy must not enter default shadow integration")

    monkeypatch.setattr(difficulty_engine, "evaluate_shadow", forbidden, raising=False)
    result = await difficulty_engine.evaluate_difficulty(db_session, uuid4(), GameTypeEnum.MATCH_IT, 1, Custom())
    assert result["new_difficulty"] == 3
    assert result["source"] == "custom_strategy"
    assert result["rule_version"] is None
    assert result["shadow_reason"] == "custom_strategy"
    log = (await db_session.execute(select(DifficultyAdjustmentLog))).scalar_one()
    assert log.source == "custom_strategy"


async def test_shadow_exception_cannot_prevent_rule_result_or_hold_log(db_session, monkeypatch):
    async def broken(*args, **kwargs):
        raise RuntimeError("not logged")

    monkeypatch.setattr(difficulty_engine, "evaluate_shadow", broken, raising=False)
    result = await difficulty_engine.evaluate_difficulty(db_session, uuid4(), GameTypeEnum.MATCH_IT, 1)
    assert result["new_difficulty"] is None
    assert result["shadow_probability"] is None
    assert result["shadow_reason"] == "inference_error"
    assert (await db_session.execute(select(DifficultyAdjustmentLog))).scalar_one().result == "hold"


async def _register_patient(client):
    """Patient account + profile + scope-all consent (mirrors four-game flow)."""
    import uuid as uuid_mod
    phone = f"+91{uuid_mod.uuid4().int % 10**9:09d}"
    resp = await client.post(f"{AUTH}/register", json={
        "phone": phone, "password": "TestPass123", "role": "patient",
        "preferred_language": "english"})
    assert resp.status_code == 201, resp.text
    resp = await client.post(f"{AUTH}/login", json={"phone": phone, "password": "TestPass123"})
    assert resp.status_code == 200, resp.text
    headers = {"Authorization": f"Bearer {resp.json()['access_token']}"}
    resp = await client.post(PATIENTS, headers=headers, json={
        "name": "Shadow Complete", "cognitive_baseline": "healthy",
        "region": "Assam", "district": "Kamrup"})
    assert resp.status_code == 201, resp.text
    patient_id = resp.json()["id"]
    resp = await client.post(f"{COMPLIANCE}/consent", headers=headers, json={
        "patient_id": patient_id, "consent_type": "patient_self", "scope": "all"})
    assert resp.status_code == 200, resp.text
    return headers, patient_id


async def test_session_complete_returns_shadow_fields_without_rule_decision(client, db_session, monkeypatch):
    """Complete path surfaces shadow prediction only — no difficulty decision,
    no DifficultyAdjustmentLog (rules stay the sole authority)."""
    from app.routes import games as games_routes

    headers, _pid = await _register_patient(client)
    start = await client.post(f"{GAMES}/sessions", headers=headers, json={
        "game_type": "match_it", "difficulty_level": 1})
    assert start.status_code == 200, start.text
    session_id = start.json()["session_id"]

    async def prediction(*args, **kwargs):
        return dict(shadow_probability=0.42, shadow_model_version="test-candidate",
                    shadow_reason="predicted")

    monkeypatch.setattr(games_routes, "evaluate_shadow", prediction)
    resp = await client.post(f"{GAMES}/sessions/{session_id}/complete", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert abs(body["shadow_probability"] - 0.42) < 1e-9
    assert body["shadow_model_version"] == "test-candidate"
    assert body["shadow_reason"] == "predicted"
    assert "new_difficulty" not in body
    assert body.get("source") is None
    logs = (await db_session.execute(select(DifficultyAdjustmentLog))).scalars().all()
    assert logs == []  # complete never logs a difficulty decision


async def test_session_complete_surfaces_unsupported_shadow_for_odd_one_out(client, db_session):
    """Odd-One-Out has no learned support: honest shadow_reason, null probability."""
    headers, _pid = await _register_patient(client)
    start = await client.post(f"{GAMES}/sessions", headers=headers, json={
        "game_type": "odd_one_out", "difficulty_level": 1})
    assert start.status_code == 200, start.text
    session_id = start.json()["session_id"]
    resp = await client.post(f"{GAMES}/sessions/{session_id}/complete", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["shadow_probability"] is None
    assert body["shadow_reason"] == "unsupported_game"

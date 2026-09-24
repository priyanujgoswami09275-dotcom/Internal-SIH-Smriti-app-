import asyncio
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.models.all_models import GameAction, GameSession, GameTypeEnum
from app.services import (
    content_packs,
    difficulty_engine,
    game_service,
    recall_service,
    routine_service,
)


AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
CONSENT = "/api/v1/compliance/consent"
GAMES = "/api/v1/games"


async def _patient_context(client):
    phone = f"+91{uuid.uuid4().int % 10**10:010d}"
    response = await client.post(
        f"{AUTH}/register",
        json={
            "phone": phone,
            "password": "TestPass123",
            "role": "patient",
            "preferred_language": "english",
        },
    )
    assert response.status_code == 201, response.text
    response = await client.post(
        f"{AUTH}/login",
        json={"phone": phone, "password": "TestPass123"},
    )
    assert response.status_code == 200, response.text
    headers = {"Authorization": f"Bearer {response.json()['access_token']}"}
    response = await client.post(
        PATIENTS,
        json={
            "name": "Integrity Patient",
            "cognitive_baseline": "healthy",
            "region": "Assam",
            "district": "Kamrup",
        },
        headers=headers,
    )
    assert response.status_code == 201, response.text
    patient_id = response.json()["id"]
    response = await client.post(
        CONSENT,
        json={
            "patient_id": patient_id,
            "consent_type": "patient_self",
            "scope": "all",
        },
        headers=headers,
    )
    assert response.status_code == 200, response.text
    return headers, patient_id


async def _start_session(client, headers, game_type, level=1):
    response = await client.post(
        f"{GAMES}/sessions",
        json={"game_type": game_type, "difficulty_level": level},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    return response.json()["session_id"]


async def _post_action(
    client,
    headers,
    session_id,
    action_type,
    action_data,
    *,
    claimed_correct=None,
    response_time_ms=500,
    idempotency_key=None,
):
    payload = {
        "action_type": action_type,
        "action_data": action_data,
        "response_time_ms": response_time_ms,
    }
    if claimed_correct is not None:
        payload["is_correct"] = claimed_correct
    if idempotency_key is not None:
        payload["idempotency_key"] = idempotency_key
    return await client.post(
        f"{GAMES}/sessions/{session_id}/actions",
        json=payload,
        headers=headers,
    )


async def _complete(client, headers, session_id, **body):
    return await client.post(
        f"{GAMES}/sessions/{session_id}/complete",
        json=body,
        headers=headers,
    )


async def _session_counts(db_session, session_id):
    session = await db_session.get(GameSession, uuid.UUID(session_id))
    await db_session.refresh(session)
    return session.attempts, session.correct_count, session.incorrect_count


def test_match_board_clamps_pair_count_to_playable_inventory(monkeypatch):
    pack = content_packs.ContentPack(
        id="integrity_tiny_pack",
        name="Integrity Tiny Pack",
        region="Test",
        description="Two-item generator fixture",
        items=[
            content_packs.ContentItem("one", "One", "এক", "এক", "एक", "test", ""),
            content_packs.ContentItem("two", "Two", "দুই", "দুই", "दो", "test", ""),
        ],
    )
    monkeypatch.setitem(content_packs.NER_CONTENT_PACKS, pack.id, pack)

    for requested, expected in ((-4, 1), (0, 1), (99, 2)):
        board = content_packs.generate_match_it_board(
            pack_id=pack.id,
            difficulty_level=3,
            pair_count=requested,
        )

        assert board["pair_count"] == expected
        assert board["total_cards"] == expected * 2
        assert len(board["cards"]) == expected * 2


def test_routine_board_clamps_step_count_to_available_steps():
    routine = [
        dict(routine_service.DEFAULT_DAILY_ROUTINE[0]),
        dict(routine_service.DEFAULT_DAILY_ROUTINE[1]),
    ]

    for requested, expected in ((-3, 1), (0, 1), (99, 2)):
        board = routine_service.generate_routine_sequencing_board(
            routine,
            difficulty_level=3,
            step_count=requested,
        )

        assert board["step_count"] == expected
        assert len(board["shuffled_items"]) == expected
        assert len(board["correct_sequence"]) == expected


@pytest.mark.parametrize(
    ("requested", "expected"),
    ((-5, 1), (0, 1), (3, 3), (99, 10)),
)
def test_recall_board_clamps_sequence_length_to_playable_range(requested, expected):
    board = recall_service.generate_number_recall_board(
        difficulty_level=3,
        sequence_length=requested,
    )

    assert board["sequence_length"] == expected
    assert len(board["sequence"]) == expected


@pytest.mark.asyncio
async def test_odd_board_withholds_answer_from_response_and_cached_snapshot(
    client, db_session,
):
    headers, _patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "odd_one_out")

    response = await client.get(
        f"{GAMES}/odd-one-out/board",
        params={"session_id": session_id, "difficulty_level": 1},
        headers=headers,
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert "answer_item_id" not in body
    assert "explanation" not in body
    stored = await db_session.get(GameSession, uuid.UUID(session_id))
    assert "answer_item_id" not in stored.board_snapshot
    assert "explanation" not in stored.board_snapshot


@pytest.mark.asyncio
async def test_odd_completion_returns_server_explanation(client):
    headers, _patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "odd_one_out")
    response = await client.get(
        f"{GAMES}/odd-one-out/board",
        params={"session_id": session_id, "difficulty_level": 1},
        headers=headers,
    )
    assert response.status_code == 200, response.text

    response = await client.post(
        f"{GAMES}/sessions/{session_id}/complete",
        headers=headers,
    )

    assert response.status_code == 200, response.text
    explanation = response.json()["explanation"]
    assert isinstance(explanation, str)
    assert explanation


@pytest.mark.asyncio
async def test_match_tampered_wrong_pair_is_server_scored_incorrect(
    client, db_session,
):
    headers, _patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "match_it")
    response = await client.get(
        f"{GAMES}/content-packs/festivals_ner/board",
        params={"session_id": session_id, "difficulty_level": 1},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    cards = response.json()["cards"]
    first = cards[0]
    second = next(card for card in cards[1:] if card["item_id"] != first["item_id"])

    response = await _post_action(
        client,
        headers,
        session_id,
        "flip_card",
        {"card_id": first["card_id"]},
        claimed_correct=True,
        idempotency_key=f"{session_id}-match-first",
    )
    assert response.status_code == 200, response.text
    assert response.json()["event"]["is_correct"] is None
    assert await _session_counts(db_session, session_id) == (0, 0, 0)

    response = await _post_action(
        client,
        headers,
        session_id,
        "flip_card",
        {"card_id": second["card_id"]},
        claimed_correct=True,
        idempotency_key=f"{session_id}-match-second",
    )
    assert response.status_code == 200, response.text
    assert response.json()["event"]["is_correct"] is False
    assert await _session_counts(db_session, session_id) == (1, 0, 1)

    response = await _complete(client, headers, session_id)
    assert response.status_code == 200, response.text
    assert response.json()["accuracy_pct"] == 0.0


@pytest.mark.asyncio
async def test_match_correct_pair_is_server_scored_correct(client, db_session):
    headers, _patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "match_it")
    response = await client.get(
        f"{GAMES}/content-packs/festivals_ner/board",
        params={"session_id": session_id, "difficulty_level": 1},
        headers=headers,
    )
    cards = response.json()["cards"]
    first = cards[0]
    second = next(card for card in cards[1:] if card["item_id"] == first["item_id"])

    for suffix, card in (("first", first), ("second", second)):
        response = await _post_action(
            client,
            headers,
            session_id,
            "flip_card",
            {"card_id": card["card_id"]},
            claimed_correct=True,
            idempotency_key=f"{session_id}-correct-{suffix}",
        )
        assert response.status_code == 200, response.text

    assert await _session_counts(db_session, session_id) == (1, 1, 0)
    response = await _complete(client, headers, session_id)
    assert response.status_code == 200, response.text
    assert response.json()["accuracy_pct"] == 100.0


@pytest.mark.asyncio
async def test_routine_tampered_wrong_step_is_server_scored_incorrect(
    client, db_session,
):
    headers, patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "routine_sequencing")
    response = await client.get(
        f"{GAMES}/routine/board",
        params={
            "patient_id": patient_id,
            "session_id": session_id,
            "difficulty_level": 1,
        },
        headers=headers,
    )
    assert response.status_code == 200, response.text
    board = response.json()
    wrong_step = next(
        item["step_id"]
        for item in board["shuffled_items"]
        if item["step_id"] != board["correct_sequence"][0]
    )

    response = await _post_action(
        client,
        headers,
        session_id,
        "place_step",
        {"position": 0, "step_id": wrong_step},
        claimed_correct=True,
        idempotency_key=f"{session_id}-routine-wrong",
    )

    assert response.status_code == 200, response.text
    assert response.json()["event"]["is_correct"] is False
    assert await _session_counts(db_session, session_id) == (1, 0, 1)
    response = await _complete(client, headers, session_id)
    assert response.status_code == 200, response.text
    assert response.json()["accuracy_pct"] == 0.0


@pytest.mark.asyncio
async def test_routine_correct_step_is_server_scored_correct(client, db_session):
    headers, patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "routine_sequencing")
    response = await client.get(
        f"{GAMES}/routine/board",
        params={
            "patient_id": patient_id,
            "session_id": session_id,
            "difficulty_level": 1,
        },
        headers=headers,
    )
    board = response.json()

    response = await _post_action(
        client,
        headers,
        session_id,
        "place_step",
        {"position": 0, "step_id": board["correct_sequence"][0]},
        claimed_correct=True,
        idempotency_key=f"{session_id}-routine-correct",
    )

    assert response.status_code == 200, response.text
    assert response.json()["event"]["is_correct"] is True
    assert await _session_counts(db_session, session_id) == (1, 1, 0)
    response = await _complete(client, headers, session_id)
    assert response.status_code == 200, response.text
    assert response.json()["accuracy_pct"] == 100.0


@pytest.mark.asyncio
async def test_recall_tampered_wrong_digit_is_server_scored_incorrect(
    client, db_session,
):
    headers, _patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "number_recall")
    response = await client.get(
        f"{GAMES}/recall/board",
        params={"session_id": session_id, "difficulty_level": 1},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    expected = response.json()["sequence"][0]
    wrong = (expected + 1) % 10

    response = await _post_action(
        client,
        headers,
        session_id,
        "recall_tap",
        {"position": 0, "digit": wrong, "expected": expected},
        claimed_correct=True,
        idempotency_key=f"{session_id}-recall-wrong",
    )

    assert response.status_code == 200, response.text
    assert response.json()["event"]["is_correct"] is False
    assert await _session_counts(db_session, session_id) == (1, 0, 1)
    response = await _complete(client, headers, session_id)
    assert response.status_code == 200, response.text
    assert response.json()["accuracy_pct"] == 0.0


@pytest.mark.asyncio
async def test_recall_correct_digit_is_server_scored_correct(client, db_session):
    headers, _patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "number_recall")
    response = await client.get(
        f"{GAMES}/recall/board",
        params={"session_id": session_id, "difficulty_level": 1},
        headers=headers,
    )
    expected = response.json()["sequence"][0]

    response = await _post_action(
        client,
        headers,
        session_id,
        "recall_tap",
        {"position": 0, "digit": expected, "expected": expected},
        claimed_correct=True,
        idempotency_key=f"{session_id}-recall-correct",
    )

    assert response.status_code == 200, response.text
    assert response.json()["event"]["is_correct"] is True
    assert await _session_counts(db_session, session_id) == (1, 1, 0)
    response = await _complete(client, headers, session_id)
    assert response.status_code == 200, response.text
    assert response.json()["accuracy_pct"] == 100.0


@pytest.mark.asyncio
async def test_action_after_completion_is_rejected(client, db_session):
    headers, _patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "number_recall")
    response = await _post_action(
        client,
        headers,
        session_id,
        "stuck",
        {"stuck_duration_ms": 1000},
        idempotency_key=f"{session_id}-before-complete",
    )
    assert response.status_code == 200, response.text
    response = await _complete(client, headers, session_id)
    assert response.status_code == 200, response.text

    response = await _post_action(
        client,
        headers,
        session_id,
        "stuck",
        {"stuck_duration_ms": 2000},
        idempotency_key=f"{session_id}-after-complete",
    )

    assert response.status_code == 409, response.text
    assert await _session_counts(db_session, session_id) == (0, 0, 0)


@pytest.mark.asyncio
async def test_duplicate_action_key_is_applied_once(client, db_session):
    headers, _patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "number_recall")
    response = await client.get(
        f"{GAMES}/recall/board",
        params={"session_id": session_id, "difficulty_level": 1},
        headers=headers,
    )
    expected = response.json()["sequence"][0]
    key = f"{session_id}-same-action"
    payload = {
        "position": 0,
        "digit": expected,
        "expected": expected,
    }

    first = await _post_action(
        client,
        headers,
        session_id,
        "recall_tap",
        payload,
        claimed_correct=True,
        idempotency_key=key,
    )
    second = await _post_action(
        client,
        headers,
        session_id,
        "recall_tap",
        payload,
        claimed_correct=True,
        idempotency_key=key,
    )

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert second.json()["idempotent_replay"] is True
    assert await _session_counts(db_session, session_id) == (1, 1, 0)


@pytest.mark.asyncio
async def test_duplicate_completion_key_returns_same_completion(client):
    headers, _patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "number_recall")
    completion_key = f"{session_id}-complete"

    first = await _complete(
        client,
        headers,
        session_id,
        idempotency_key=completion_key,
    )
    second = await _complete(
        client,
        headers,
        session_id,
        idempotency_key=completion_key,
    )

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert second.json()["completed_at"] == first.json()["completed_at"]
    assert second.json()["idempotent_replay"] is True


@pytest.mark.asyncio
async def test_completion_waits_for_every_expected_action(client, db_session):
    headers, _patient_id = await _patient_context(client)
    session_id = await _start_session(client, headers, "number_recall")
    action_key = f"{session_id}-pending"
    completion_key = f"{session_id}-barrier-complete"

    blocked = await _complete(
        client,
        headers,
        session_id,
        idempotency_key=completion_key,
        expected_action_ids=[action_key],
    )

    assert blocked.status_code == 409, blocked.text
    session = await db_session.get(GameSession, uuid.UUID(session_id))
    await db_session.refresh(session)
    assert session.completed_at is None

    action = await _post_action(
        client,
        headers,
        session_id,
        "stuck",
        {"stuck_duration_ms": 1000},
        idempotency_key=action_key,
    )
    assert action.status_code == 200, action.text
    completed = await _complete(
        client,
        headers,
        session_id,
        idempotency_key=completion_key,
        expected_action_ids=[action_key],
    )
    assert completed.status_code == 200, completed.text


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("history_accuracy", "level", "matching", "shadow_probability"),
    (
        (100.0, 1, True, 0.0),
        (0.0, 3, False, 1.0),
    ),
)
async def test_completion_recommends_rule_level_without_shadow_override(
    client,
    db_session,
    monkeypatch,
    history_accuracy,
    level,
    matching,
    shadow_probability,
):
    headers, patient_id = await _patient_context(client)
    now = datetime.now()
    for index in (3, 2):
        db_session.add(
            GameSession(
                patient_id=uuid.UUID(patient_id),
                game_type=GameTypeEnum.MATCH_IT,
                difficulty_level=level,
                attempts=10,
                correct_count=10 if history_accuracy == 100.0 else 0,
                incorrect_count=0 if history_accuracy == 100.0 else 10,
                accuracy_pct=history_accuracy,
                raw_event_log=[],
                started_at=now - timedelta(minutes=index),
                completed_at=now - timedelta(minutes=index - 1),
            )
        )
    await db_session.commit()

    async def shadow_result(*args, **kwargs):
        return {
            "shadow_probability": shadow_probability,
            "shadow_model_version": "integrity-shadow-v1",
            "shadow_reason": "informational_test_signal",
        }

    monkeypatch.setattr(
        difficulty_engine,
        "evaluate_shadow",
        shadow_result,
    )

    session_id = await _start_session(
        client,
        headers,
        "match_it",
        level,
    )
    response = await client.get(
        f"{GAMES}/content-packs/festivals_ner/board",
        params={"session_id": session_id, "difficulty_level": level},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    cards = response.json()["cards"]
    first = cards[0]
    second = next(
        card
        for card in cards[1:]
        if (card["item_id"] == first["item_id"]) is matching
    )
    for suffix, card in (("first", first), ("second", second)):
        response = await _post_action(
            client,
            headers,
            session_id,
            "flip_card",
            {"card_id": card["card_id"]},
            claimed_correct=True,
            idempotency_key=f"{session_id}-rule-{suffix}",
        )
        assert response.status_code == 200, response.text

    response = await _complete(
        client,
        headers,
        session_id,
        idempotency_key=f"{session_id}-rule-complete",
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["recommended_level"] == 2
    assert body["difficulty_source"] == "rule_fallback"
    assert body["shadow_probability"] == shadow_probability
    assert body["shadow_model_version"] == "integrity-shadow-v1"


@pytest.mark.asyncio
async def test_concurrent_action_appends_persist_every_event(db_session):
    session = GameSession(
        patient_id=uuid.uuid4(),
        game_type=GameTypeEnum.MATCH_IT,
        difficulty_level=1,
        started_at=datetime.now(),
        raw_event_log=[],
    )
    db_session.add(session)
    await db_session.commit()
    session_id = session.id
    session_factory = async_sessionmaker(
        bind=db_session.bind,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    async def append(key, value):
        async with session_factory() as concurrent_db:
            await game_service.record_game_action(
                concurrent_db,
                session_id=session_id,
                action_type="stuck",
                action_data={"value": value},
                response_time_ms=value,
                idempotency_key=key,
            )
            await concurrent_db.commit()

    await asyncio.gather(
        append(f"{session_id}-concurrent-a", 100),
        append(f"{session_id}-concurrent-b", 200),
    )

    count = await db_session.scalar(
        select(func.count())
        .select_from(GameAction)
        .where(GameAction.session_id == session_id)
    )
    assert count == 2
    await game_service.complete_game_session(db_session, session_id=session_id)
    await db_session.refresh(session)
    assert len(session.raw_event_log) == 2


@pytest.mark.asyncio
async def test_start_idempotency_key_replays_existing_session(client, db_session):
    headers, patient_id = await _patient_context(client)
    payload = {
        "game_type": "number_recall",
        "difficulty_level": 1,
        "idempotency_key": "offline-start-key",
    }

    first = await client.post(f"{GAMES}/sessions", json=payload, headers=headers)
    second = await client.post(f"{GAMES}/sessions", json=payload, headers=headers)

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert first.json()["idempotent_replay"] is False
    assert second.json()["idempotent_replay"] is True
    assert first.json()["session_id"] == second.json()["session_id"]
    assert first.json()["started_at"] == second.json()["started_at"]

    count = await db_session.scalar(
        select(func.count())
        .select_from(GameSession)
        .where(GameSession.patient_id == uuid.UUID(patient_id))
    )
    assert count == 1


@pytest.mark.asyncio
async def test_replay_preserves_original_timestamps(client, db_session):
    headers, _patient_id = await _patient_context(client)
    now = datetime.now(timezone.utc)
    original_started = now - timedelta(minutes=10)
    original_completed = now - timedelta(minutes=5)

    response = await client.post(
        f"{GAMES}/sessions",
        json={
            "game_type": "number_recall",
            "difficulty_level": 1,
            "idempotency_key": "offline-timestamp-key",
            "started_at": original_started.isoformat(),
            "completed_at": original_completed.isoformat(),
        },
        headers=headers,
    )

    assert response.status_code == 200, response.text
    session_id = response.json()["session_id"]
    expected_started = original_started.replace(tzinfo=None).isoformat()
    expected_completed = original_completed.replace(tzinfo=None).isoformat()
    assert response.json()["started_at"] == expected_started

    stored = await db_session.get(GameSession, uuid.UUID(session_id))
    await db_session.refresh(stored)
    assert stored.started_at.isoformat() == expected_started

    completed = await _complete(
        client,
        headers,
        session_id,
        idempotency_key="offline-timestamp-completion",
    )

    assert completed.status_code == 200, completed.text
    assert completed.json()["completed_at"] == expected_completed


@pytest.mark.asyncio
async def test_start_ignores_client_supplied_patient_identity(client, db_session):
    headers, patient_id = await _patient_context(client)
    supplied_id = str(uuid.uuid4())

    response = await client.post(
        f"{GAMES}/sessions",
        json={
            "game_type": "number_recall",
            "difficulty_level": 1,
            "patient_id": supplied_id,
            "user_id": supplied_id,
        },
        headers=headers,
    )

    assert response.status_code == 200, response.text
    stored = await db_session.get(
        GameSession, uuid.UUID(response.json()["session_id"])
    )
    await db_session.refresh(stored)
    assert stored.patient_id == uuid.UUID(patient_id)


@pytest.mark.asyncio
async def test_start_without_idempotency_key_remains_supported(client, db_session):
    headers, patient_id = await _patient_context(client)

    response = await client.post(
        f"{GAMES}/sessions",
        json={"game_type": "number_recall", "difficulty_level": 1},
        headers=headers,
    )

    assert response.status_code == 200, response.text
    assert response.json()["idempotent_replay"] is False
    stored = await db_session.get(
        GameSession, uuid.UUID(response.json()["session_id"])
    )
    await db_session.refresh(stored)
    assert stored.patient_id == uuid.UUID(patient_id)

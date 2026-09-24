import uuid

import pytest
from sqlalchemy import select

from app.models.all_models import SymptomLog, SyncQueue
from app.services.sync_service import consume_sync_queue

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
SYNC = "/api/v1/sync"


async def _register(client, role="patient"):
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


async def _login(client, user):
    response = await client.post(
        f"{AUTH}/login",
        json={"phone": user["phone"], "password": "Passw0rd123"},
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


async def _create_patient(client, headers, name):
    response = await client.post(
        PATIENTS,
        headers=headers,
        json={"name": name, "region": "assam"},
    )
    assert response.status_code == 201, response.text
    return response.json()


async def _grant_health_consent(client, headers, patient_id):
    response = await client.post(
        "/api/v1/compliance/consent",
        headers=headers,
        json={
            "patient_id": patient_id,
            "consent_type": "patient_self",
            "scope": "health_data",
        },
    )
    assert response.status_code == 200, response.text


def _symptom_item(idempotency_key=None):
    item = {
        "resource_type": "offline_symptom",
        "operation": "create",
        "resource_id": str(uuid.uuid4()),
        "payload": {
            "source": "manual_asha",
            "severity": 3,
            "notes": "Offline clinical note",
        },
    }
    if idempotency_key is not None:
        item["idempotency_key"] = idempotency_key
    return item


@pytest.mark.asyncio
async def test_owner_without_health_data_consent_cannot_sync_clinical_note(
    client, db_session
):
    owner = await _register(client)
    headers = await _login(client, owner)
    patient = await _create_patient(client, headers, "No Health Consent")

    response = await client.post(
        SYNC,
        headers=headers,
        json={
            "patient_id": patient["id"],
            "items": [_symptom_item(str(uuid.uuid4()))],
        },
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Active consent required for scope 'health_data'"
    rows = (await db_session.execute(select(SyncQueue))).scalars().all()
    assert rows == []


@pytest.mark.asyncio
async def test_linked_caregiver_without_health_data_consent_cannot_sync_clinical_note(
    client, db_session
):
    owner = await _register(client)
    caregiver = await _register(client, role="family_caregiver")
    owner_headers = await _login(client, owner)
    caregiver_headers = await _login(client, caregiver)
    patient = await _create_patient(client, owner_headers, "Linked Caregiver")
    me = await client.get(f"{AUTH}/me", headers=caregiver_headers)
    link = await client.post(
        f"{PATIENTS}/{patient['id']}/caregivers",
        headers=owner_headers,
        json={
            "caregiver_id": me.json()["id"],
            "relationship_type": "family",
            "permission_tier": "basic",
        },
    )
    assert link.status_code == 201, link.text

    response = await client.post(
        SYNC,
        headers=caregiver_headers,
        json={
            "patient_id": patient["id"],
            "items": [_symptom_item(str(uuid.uuid4()))],
        },
    )

    assert response.status_code == 403
    assert response.json()["detail"] == "Active consent required for scope 'health_data'"
    rows = (await db_session.execute(select(SyncQueue))).scalars().all()
    assert rows == []


@pytest.mark.asyncio
async def test_health_data_consent_allows_clinical_note_sync(client, db_session):
    owner = await _register(client)
    headers = await _login(client, owner)
    patient = await _create_patient(client, headers, "Consented Clinical Note")
    await _grant_health_consent(client, headers, patient["id"])

    response = await client.post(
        SYNC,
        headers=headers,
        json={
            "patient_id": patient["id"],
            "items": [_symptom_item(str(uuid.uuid4()))],
        },
    )

    assert response.status_code == 200, response.text
    assert response.json() == {
        "patient_id": patient["id"],
        "synced": 1,
        "errors": [],
    }
    counts = await consume_sync_queue(db_session, patient_id=uuid.UUID(patient["id"]))
    assert counts["materialized"] == 1
    symptoms = (
        await db_session.execute(
            select(SymptomLog).where(SymptomLog.patient_id == uuid.UUID(patient["id"]))
        )
    ).scalars().all()
    assert len(symptoms) == 1


@pytest.mark.asyncio
async def test_replaying_client_idempotency_key_materializes_one_symptom(
    client, db_session
):
    owner = await _register(client)
    headers = await _login(client, owner)
    patient = await _create_patient(client, headers, "Idempotent Clinical Note")
    await _grant_health_consent(client, headers, patient["id"])
    item = _symptom_item(str(uuid.uuid4()))

    first = await client.post(
        SYNC,
        headers=headers,
        json={"patient_id": patient["id"], "items": [item]},
    )
    second = await client.post(
        SYNC,
        headers=headers,
        json={"patient_id": patient["id"], "items": [item]},
    )

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert first.json()["synced"] == 1
    assert second.json()["synced"] == 1
    counts = await consume_sync_queue(db_session, patient_id=uuid.UUID(patient["id"]))
    assert counts["materialized"] == 1
    symptoms = (
        await db_session.execute(
            select(SymptomLog).where(SymptomLog.patient_id == uuid.UUID(patient["id"]))
        )
    ).scalars().all()
    assert len(symptoms) == 1
    queue_items = (
        await db_session.execute(
            select(SyncQueue).where(SyncQueue.patient_id == uuid.UUID(patient["id"]))
        )
    ).scalars().all()
    assert len(queue_items) == 1


@pytest.mark.asyncio
async def test_legacy_event_without_key_uses_deterministic_idempotency(
    client, db_session
):
    owner = await _register(client)
    headers = await _login(client, owner)
    patient = await _create_patient(client, headers, "Legacy Idempotency")
    await _grant_health_consent(client, headers, patient["id"])
    item = _symptom_item()

    first = await client.post(
        SYNC,
        headers=headers,
        json={"patient_id": patient["id"], "items": [item]},
    )
    second = await client.post(
        SYNC,
        headers=headers,
        json={"patient_id": patient["id"], "items": [item]},
    )

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    await consume_sync_queue(db_session, patient_id=uuid.UUID(patient["id"]))
    symptoms = (
        await db_session.execute(
            select(SymptomLog).where(SymptomLog.patient_id == uuid.UUID(patient["id"]))
        )
    ).scalars().all()
    assert len(symptoms) == 1


@pytest.mark.asyncio
async def test_unsupported_resource_type_is_rejected_without_queueing(client, db_session):
    owner = await _register(client)
    headers = await _login(client, owner)
    patient = await _create_patient(client, headers, "Unsupported Sync")

    response = await client.post(
        SYNC,
        headers=headers,
        json={
            "patient_id": patient["id"],
            "items": [
                {
                    "resource_type": "game_session",
                    "operation": "create",
                    "resource_id": str(uuid.uuid4()),
                    "payload": {"score": 10},
                }
            ],
        },
    )

    assert response.status_code == 422
    assert response.json()["detail"] == (
        "Unsupported sync resource_type/operation: game_session/create. "
        "Only offline_symptom/create is supported"
    )
    rows = (await db_session.execute(select(SyncQueue))).scalars().all()
    assert rows == []


@pytest.mark.asyncio
async def test_malformed_client_idempotency_key_is_rejected(client, db_session):
    owner = await _register(client)
    headers = await _login(client, owner)
    patient = await _create_patient(client, headers, "Invalid Idempotency Key")
    await _grant_health_consent(client, headers, patient["id"])

    response = await client.post(
        SYNC,
        headers=headers,
        json={
            "patient_id": patient["id"],
            "items": [_symptom_item("not-a-uuid")],
        },
    )

    assert response.status_code == 422
    rows = (await db_session.execute(select(SyncQueue))).scalars().all()
    assert rows == []


@pytest.mark.asyncio
async def test_consumer_treats_materialized_key_collision_as_idempotent_success(
    client, db_session
):
    owner = await _register(client)
    headers = await _login(client, owner)
    patient = await _create_patient(client, headers, "Consumer Idempotency")
    await _grant_health_consent(client, headers, patient["id"])
    patient_id = uuid.UUID(patient["id"])
    idempotency_key = str(uuid.uuid4())
    item = _symptom_item(idempotency_key)

    accepted = await client.post(
        SYNC,
        headers=headers,
        json={"patient_id": patient["id"], "items": [item]},
    )
    assert accepted.status_code == 200, accepted.text
    assert (await consume_sync_queue(db_session, patient_id=patient_id))[
        "materialized"
    ] == 1
    queue_item = (
        await db_session.execute(
            select(SyncQueue).where(SyncQueue.patient_id == patient_id)
        )
    ).scalar_one()
    await db_session.delete(queue_item)
    await db_session.commit()
    db_session.add(
        SyncQueue(
            patient_id=patient_id,
            resource_type="offline_symptom",
            operation="create",
            resource_id=uuid.uuid4(),
            idempotency_key=idempotency_key,
            payload={
                "entered_by": owner["id"],
                "source": "manual_asha",
                "severity": 3,
                "notes": "Offline clinical note",
            },
        )
    )
    await db_session.commit()

    counts = await consume_sync_queue(db_session, patient_id=patient_id)

    assert counts == {"materialized": 0, "acked": 1, "errors": 0}
    symptoms = (
        await db_session.execute(
            select(SymptomLog).where(SymptomLog.patient_id == patient_id)
        )
    ).scalars().all()
    assert len(symptoms) == 1
    replayed_queue_item = (
        await db_session.execute(
            select(SyncQueue).where(SyncQueue.patient_id == patient_id)
        )
    ).scalar_one()
    assert replayed_queue_item.synced_at is not None

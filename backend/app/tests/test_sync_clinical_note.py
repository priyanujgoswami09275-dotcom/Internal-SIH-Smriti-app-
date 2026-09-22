"""Wave 2 Batch D — clinical notes ride the offline_symptom pipeline.

The mobile `ClinicalNotesScreen` enqueues notes as `offline_symptom`/`create`
items (no new enum, no migration). This test posts that exact envelope to
`POST /api/v1/sync` and runs `consume_sync_queue`, proving save → server row
exists end-to-end. No backend source change is expected for this to pass; if
any source change is needed, stop and report instead of expanding scope.
"""
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import select

from app.models.all_models import SymptomLog
from app.services.compliance_service import EncryptionService
from app.services.sync_service import consume_sync_queue

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
SYNC = "/api/v1/sync"


async def _register(client, phone, role="patient"):
    r = await client.post(f"{AUTH}/register", json={
        "phone": phone, "password": "Passw0rd123", "role": role,
        "preferred_language": "english"})
    assert r.status_code == 201, r.text
    return r.json()


async def _login(client, phone):
    r = await client.post(f"{AUTH}/login", json={
        "phone": phone, "password": "Passw0rd123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.mark.asyncio
async def test_clinical_note_envelope_materializes_symptom_log(
    client, db_session
):
    """Mobile offline_symptom envelope → 200 → one encrypted MANUAL_ASHA row."""
    owner = await _register(client, f"+91{uuid.uuid4().int % 10**10}")
    headers = await _login(client, owner["phone"])
    entered_by = owner["id"]  # staff/owner id recorded as entered_by

    prof = await client.post(
        PATIENTS, json={"name": "Clinical Note", "region": "assam"},
        headers=headers)
    assert prof.status_code == 201, prof.text
    patient_id = prof.json()["id"]

    # Exact mobile envelope: entered_by + manual_asha source + 1-5 severity +
    # notes + recorded_at, with a client-generated UUID resource_id.
    notes = "Patient walked slower than usual; mild ankle swelling observed."
    resp = await client.post(SYNC, headers=headers, json={
        "patient_id": patient_id,
        "items": [{
            "resource_type": "offline_symptom",
            "operation": "create",
            "resource_id": str(uuid.uuid4()),
            "payload": {
                "entered_by": entered_by,
                "source": "manual_asha",
                "severity": 3,
                "notes": notes,
                "recorded_at": datetime.now(timezone.utc).isoformat(),
            },
        }],
    })
    assert resp.status_code == 200, resp.text
    assert resp.json()["synced"] == 1
    assert resp.json()["errors"] == []

    counts = await consume_sync_queue(db_session, patient_id=uuid.UUID(patient_id))
    assert counts["materialized"] == 1

    rows = (await db_session.execute(
        select(SymptomLog).where(SymptomLog.patient_id == uuid.UUID(patient_id))
    )).scalars().all()
    assert len(rows) == 1
    row = rows[0]
    assert row.entry_source.value == "manual_asha"
    assert row.notes != notes  # AES-256 at rest: stored ciphertext
    assert EncryptionService().decrypt(row.notes) == notes
    assert row.severity == 3

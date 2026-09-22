"""Sync service — offline outbox + consumer.

POST /sync stores offline-created items from mobile as PENDING outbox rows
(``synced_at IS NULL``) and returns the number accepted. A consumer
(``consume_sync_queue``) later materializes supported resource types into
domain rows:

- ``offline_symptom`` (operation create) -> ``SymptomLog`` with AES-256
  encrypted notes (DPDP at-rest encryption).
- Any other resource type is acknowledged at the outbox (``synced_at`` set)
  because those flows replay through their live endpoints instead (game
  sessions replay start/actions/complete; reminder acks call the live ack
  endpoint when the device reconnects).

Retention purges synced rows after 7 days (see RetentionService).
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import List, Optional
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.all_models import (
    SymptomEntrySourceEnum,
    SymptomLog,
    SyncOperationEnum,
    SyncQueue,
)
from app.services.compliance_service import EncryptionService

logger = logging.getLogger(__name__)


async def process_sync_batch(
    db: AsyncSession, patient_id: UUID, items: List[dict]
) -> dict:
    """Accept a batch of offline-queued items into the pending outbox.

    Each item: {resource_type, operation, resource_id, payload, created_at}
    Returns: {synced: int, errors: list}  — ``synced`` counts rows accepted
    into the outbox (not yet materialized by the consumer).
    """
    synced = 0
    errors = []
    for item in items:
        try:
            resource_id = item.get("resource_id")
            if isinstance(resource_id, str):
                resource_id = UUID(resource_id)
            created_at = item.get("created_at")
            if isinstance(created_at, str):
                created_at = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
            entry = SyncQueue(
                patient_id=patient_id,
                resource_type=item["resource_type"],
                operation=item["operation"],
                resource_id=resource_id,
                payload=item["payload"],
                created_at=created_at or datetime.now(timezone.utc),
                synced_at=None,  # pending until the consumer materializes it
            )
            db.add(entry)
            synced += 1
        except Exception as exc:  # noqa: BLE001 — per-item isolation
            errors.append({"resource_id": str(item.get("resource_id")), "error": str(exc)})
    if synced:
        await db.commit()
    return {"synced": synced, "errors": errors}


async def get_pending_sync(db: AsyncSession, patient_id: UUID) -> list:
    """Get unsynced (pending) items for a patient (synced_at IS NULL)."""
    result = await db.execute(
        select(SyncQueue)
        .where(SyncQueue.patient_id == patient_id, SyncQueue.synced_at.is_(None))
        .order_by(SyncQueue.created_at)
    )
    return result.scalars().all()


async def consume_sync_queue(
    db: AsyncSession,
    patient_id: Optional[UUID] = None,
    limit: int = 200,
    encryption: Optional[EncryptionService] = None,
) -> dict:
    """Materialize pending outbox rows into domain records.

    Currently supports ``offline_symptom`` creates -> encrypted ``SymptomLog``.
    Other resource types are acknowledged at the outbox (replayed via live
    endpoints). Rows that fail materialization stay pending (``synced_at``
    NULL) with ``last_error`` set and ``retry_count`` incremented so they
    remain visible in ``GET /sync/pending`` for retry. Returns per-kind
    counts.
    """
    encryption = encryption or EncryptionService()
    stmt = select(SyncQueue).where(SyncQueue.synced_at.is_(None))
    if patient_id is not None:
        stmt = stmt.where(SyncQueue.patient_id == patient_id)
    stmt = stmt.order_by(SyncQueue.created_at).limit(limit)

    result = await db.execute(stmt)
    rows = result.scalars().all()

    counts = {"materialized": 0, "acked": 0, "errors": 0}
    for item in rows:
        try:
            if (
                item.resource_type.value == "offline_symptom"
                and item.operation == SyncOperationEnum.CREATE
            ):
                payload = item.payload or {}
                entered_by = payload.get("entered_by")
                notes = payload.get("note") or payload.get("notes") or ""
                if not entered_by or not notes:
                    raise ValueError("offline_symptom payload needs entered_by and note")
                symptom = SymptomLog(
                    patient_id=item.patient_id,
                    entered_by=UUID(str(entered_by)),
                    entry_source=(
                        SymptomEntrySourceEnum(payload["source"])
                        if payload.get("source")
                        else SymptomEntrySourceEnum.MANUAL_CAREGIVER
                    ),
                    notes=encryption.encrypt(str(notes)),  # AES-256 at rest
                    severity=int(payload.get("severity", 1)),
                    timestamp=(
                        datetime.fromisoformat(payload["recorded_at"].replace("Z", "+00:00"))
                        if payload.get("recorded_at")
                        else datetime.now(timezone.utc)
                    ),
                )
                db.add(symptom)
                counts["materialized"] += 1
            else:
                # Replay-through-live-endpoint flows: acknowledge at the outbox.
                counts["acked"] += 1
            item.synced_at = datetime.now(timezone.utc)
            item.last_error = None
        except Exception as exc:  # noqa: BLE001 — per-item isolation
            logger.warning("Sync item %s failed: %s", item.id, exc)
            counts["errors"] += 1
            item.last_error = str(exc)[:480]
            item.retry_count = (item.retry_count or 0) + 1
            # Do NOT set synced_at — failure stays pending and retryable
    if rows:
        await db.commit()
    return counts


async def mark_synced(db: AsyncSession, item_ids: List[UUID]) -> int:
    """Explicitly acknowledge outbox rows (used by tests / admin tooling)."""
    if not item_ids:
        return 0
    res = await db.execute(
        update(SyncQueue)
        .where(SyncQueue.id.in_(item_ids))
        .values(synced_at=datetime.now(timezone.utc))
    )
    await db.commit()
    return res.rowcount or 0

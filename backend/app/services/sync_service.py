"""Sync service — offline outbox + consumer.

POST /sync stores supported offline-created items from mobile as PENDING
outbox rows (``synced_at IS NULL``) and returns the number accepted. A consumer
(``consume_sync_queue``) materializes ``offline_symptom`` creates into
``SymptomLog`` rows with encrypted notes. Replays use the queue idempotency key
and a deterministic domain ID so concurrent workers cannot duplicate a symptom.

Retention purges synced rows after 7 days (see RetentionService).
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import List, Optional
from uuid import NAMESPACE_URL, UUID, uuid5

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.all_models import (
    SymptomEntrySourceEnum,
    SymptomLog,
    SyncOperationEnum,
    SyncQueue,
    SyncResourceTypeEnum,
)
from app.services.compliance_service import ComplianceService, EncryptionService

logger = logging.getLogger(__name__)

SUPPORTED_SYNC_RESOURCE_TYPE = SyncResourceTypeEnum.OFFLINE_SYMPTOM.value
SUPPORTED_SYNC_OPERATION = SyncOperationEnum.CREATE.value
UNSUPPORTED_SYNC_ERROR = (
    "Unsupported sync resource_type/operation: "
    "{resource_type}/{operation}. Only offline_symptom/create is supported"
)


def _enum_value(value) -> str:
    return value.value if hasattr(value, "value") else str(value)


def _derive_idempotency_key(
    patient_id: UUID,
    resource_type: str,
    operation: str,
    resource_id: UUID,
    payload: dict,
    created_at: Optional[datetime],
) -> str:
    content = {
        "patient_id": str(patient_id),
        "resource_type": resource_type,
        "operation": operation,
        "resource_id": str(resource_id),
        "payload": payload,
        "created_at": created_at.isoformat() if created_at is not None else None,
    }
    canonical = json.dumps(
        content,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )
    return str(uuid5(NAMESPACE_URL, f"smriti-sync:{canonical}"))


def _materialized_symptom_id(patient_id: UUID, idempotency_key: str) -> UUID:
    return uuid5(
        NAMESPACE_URL,
        f"smriti-symptom:{patient_id}:{idempotency_key}",
    )


def _is_unique_violation(exc: IntegrityError) -> bool:
    original = exc.orig
    if getattr(original, "sqlstate", None) == "23505":
        return True
    if getattr(original, "sqlite_errorcode", None) == 2067:
        return True
    message = str(original).lower()
    return "unique constraint failed" in message or "duplicate key value" in message


async def process_sync_batch(
    db: AsyncSession, patient_id: UUID, items: List[dict]
) -> dict:
    """Accept a batch of offline-queued items into the pending outbox.

    Each item: {resource_type, operation, resource_id, idempotency_key,
    payload, created_at}. A missing key is replaced by a deterministic UUID
    derived from the canonical item content. Returns ``synced`` as the number
    accepted, including idempotent duplicates.
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
            resource_type = _enum_value(item["resource_type"])
            operation = _enum_value(item["operation"])
            idempotency_key = item.get("idempotency_key")
            if idempotency_key is None:
                idempotency_key = _derive_idempotency_key(
                    patient_id,
                    resource_type,
                    operation,
                    resource_id,
                    item["payload"],
                    created_at,
                )
            else:
                idempotency_key = str(UUID(str(idempotency_key)))
            entry = SyncQueue(
                patient_id=patient_id,
                resource_type=item["resource_type"],
                operation=item["operation"],
                resource_id=resource_id,
                idempotency_key=idempotency_key,
                payload=item["payload"],
                created_at=created_at or datetime.now(timezone.utc),
                synced_at=None,
            )
            async with db.begin_nested():
                db.add(entry)
                await db.flush()
            synced += 1
        except IntegrityError as exc:
            if _is_unique_violation(exc):
                synced += 1
            else:
                errors.append(
                    {"resource_id": str(item.get("resource_id")), "error": str(exc)}
                )
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

    Supports ``offline_symptom`` creates only. Pending rows are claimed with
    ``FOR UPDATE SKIP LOCKED`` so concurrent workers do not process the same
    row. A deterministic symptom ID makes a unique violation an idempotent
    success. Unsupported or invalid rows stay pending with ``last_error`` set.
    """
    encryption = encryption or EncryptionService()
    stmt = select(SyncQueue).where(SyncQueue.synced_at.is_(None))
    if patient_id is not None:
        stmt = stmt.where(SyncQueue.patient_id == patient_id)
    stmt = (
        stmt.order_by(SyncQueue.created_at, SyncQueue.id)
        .limit(limit)
        .with_for_update(skip_locked=True)
    )

    result = await db.execute(stmt)
    rows = result.scalars().all()

    counts = {"materialized": 0, "acked": 0, "errors": 0}
    materialized_audits = []
    for item in rows:
        try:
            resource_type = _enum_value(item.resource_type)
            operation = _enum_value(item.operation)
            if (
                resource_type != SUPPORTED_SYNC_RESOURCE_TYPE
                or operation != SUPPORTED_SYNC_OPERATION
            ):
                raise ValueError(
                    UNSUPPORTED_SYNC_ERROR.format(
                        resource_type=resource_type,
                        operation=operation,
                    )
                )
            payload = item.payload or {}
            entered_by = payload.get("entered_by")
            notes = payload.get("note") or payload.get("notes") or ""
            if not entered_by or not notes:
                raise ValueError("offline_symptom payload needs entered_by and note")
            actor_id = UUID(str(entered_by))
            symptom = SymptomLog(
                id=_materialized_symptom_id(
                    item.patient_id,
                    item.idempotency_key,
                ),
                patient_id=item.patient_id,
                entered_by=actor_id,
                entry_source=(
                    SymptomEntrySourceEnum(payload["source"])
                    if payload.get("source")
                    else SymptomEntrySourceEnum.MANUAL_CAREGIVER
                ),
                notes=encryption.encrypt(str(notes)),
                severity=int(payload.get("severity", 1)),
                timestamp=(
                    datetime.fromisoformat(payload["recorded_at"].replace("Z", "+00:00"))
                    if payload.get("recorded_at")
                    else datetime.now(timezone.utc)
                ),
            )
            try:
                async with db.begin_nested():
                    db.add(symptom)
                    await db.flush()
            except IntegrityError as exc:
                if not _is_unique_violation(exc):
                    raise
                counts["acked"] += 1
            else:
                materialized_audits.append((actor_id, str(symptom.id)))
                counts["materialized"] += 1
            item.synced_at = datetime.now(timezone.utc)
            item.last_error = None
        except Exception as exc:  # noqa: BLE001 — per-item isolation
            logger.warning("Sync item %s failed: %s", item.id, exc)
            counts["errors"] += 1
            item.last_error = str(exc)[:480]
            item.retry_count = (item.retry_count or 0) + 1
    if rows:
        await db.commit()
    for actor_id, symptom_id in materialized_audits:
        await ComplianceService.log_write_access(
            db,
            actor_id,
            "symptom_log",
            symptom_id,
            details={
                "resource_type": "offline_symptom",
                "operation": "sync_materialize",
            },
        )
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

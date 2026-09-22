"""Offline-First Sync API Routes — batched offline events from mobile SyncQueue.

Endpoints:
  POST /sync — accept a batch of offline-created events (idempotent, fresh INSERTs)
  GET  /sync/pending/{patient_id} — list unsynced queue items (admin/staff)
"""
from datetime import datetime
from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import require_role
from app.database import get_db
from app.deps import ensure_patient_access
from app.models.all_models import (
    SyncResourceTypeEnum,
    SyncOperationEnum,
)
from app.models.user import User
from app.services.sync_service import process_sync_batch, get_pending_sync

router = APIRouter(prefix="/sync", tags=["sync"])

require_patient_or_staff = require_role("patient", "family_caregiver", "asha_worker", "clinician")


# ============= Schemas =============


class SyncItem(BaseModel):
    resource_type: str
    operation: str
    resource_id: UUID
    payload: dict
    created_at: Optional[datetime] = None  # device timestamp


class SyncBatchRequest(BaseModel):
    patient_id: UUID
    items: List[SyncItem]


# ============= Endpoints =============


@router.post("")
async def sync_batch(
    body: SyncBatchRequest,
    current_user: User = Depends(require_patient_or_staff),
    db: AsyncSession = Depends(get_db),
):
    """Persist offline-created events from the mobile device into the backend.

    Each item is stored in the server SyncQueue as a fresh INSERT; MVP sync is
    conflict-free (no updates/deletes of existing rows).
    """
    await ensure_patient_access(db, current_user, body.patient_id)
    # Validate resource_type / operation against the domain enums up front.
    for item in body.items:
        try:
            SyncResourceTypeEnum(item.resource_type)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Invalid resource_type: {item.resource_type}",
            )
        try:
            SyncOperationEnum(item.operation)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Invalid operation: {item.operation}",
            )

    result = await process_sync_batch(
        db,
        patient_id=body.patient_id,
        items=[
            {
                "resource_type": item.resource_type,
                "operation": item.operation,
                "resource_id": item.resource_id,
                "payload": item.payload,
                **({} if item.created_at is None else {"created_at": item.created_at}),
            }
            for item in body.items
        ],
    )
    return {
        "patient_id": str(body.patient_id),
        "synced": result["synced"],
        "errors": result["errors"],
    }


@router.get("/pending/{patient_id}")
async def pending_sync_items(
    patient_id: UUID,
    current_user: User = Depends(require_role("asha_worker", "clinician", "admin")),
    db: AsyncSession = Depends(get_db),
):
    """Return unsynced queue items for a patient (synced_at IS NULL)."""
    await ensure_patient_access(db, current_user, patient_id)
    items = await get_pending_sync(db, patient_id)
    return [
        {
            "id": str(i.id),
            "resource_type": i.resource_type.value if hasattr(i.resource_type, "value") else str(i.resource_type),
            "operation": i.operation.value if hasattr(i.operation, "value") else str(i.operation),
            "resource_id": str(i.resource_id),
            "payload": i.payload,
            "created_at": i.created_at.isoformat() if i.created_at else None,
            "synced_at": i.synced_at.isoformat() if i.synced_at else None,
            "retry_count": i.retry_count,
            "last_error": i.last_error,
        }
        for i in items
    ]

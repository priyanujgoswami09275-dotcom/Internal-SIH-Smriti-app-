"""DPDP Consent & Security Audit API Routes."""

import uuid
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from sqlalchemy import select

from app.database import get_db
from app.deps import ensure_patient_access, get_permission_tier
from app.models.all_models import (
    AuditActionEnum, AuditLog, User, ConsentRecord, ConsentTypeEnum, RoleEnum,
)
from app.middleware.auth_middleware import get_current_user, require_role
from app.services.compliance_service import ComplianceService

router = APIRouter(prefix="/compliance", tags=["DPDP Act 2023 & Compliance"])


class ConsentCreateRequest(BaseModel):
    patient_id: uuid.UUID
    consent_type: ConsentTypeEnum = ConsentTypeEnum.PATIENT_SELF
    scope: str = "all"
    guardian_id: Optional[uuid.UUID] = None


class ConsentResponse(BaseModel):
    id: str
    patient_id: str
    consent_type: str
    scope: str
    granted_at: str
    revoked_at: Optional[str] = None


@router.post("/consent", response_model=ConsentResponse)
async def grant_consent(
    req: ConsentCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Explicitly grant DPDP consent before storing or accessing patient health data."""
    record = await ComplianceService.record_consent(
        db=db,
        patient_id=req.patient_id,
        consent_type=req.consent_type,
        scope=req.scope,
        actor=current_user,
        guardian_id=req.guardian_id,
    )
    return ConsentResponse(
        id=str(record.id),
        patient_id=str(record.patient_id),
        consent_type=record.consent_type.value if hasattr(record.consent_type, 'value') else str(record.consent_type),
        scope=record.scope,
        granted_at=record.granted_at.isoformat(),
        revoked_at=record.revoked_at.isoformat() if record.revoked_at else None,
    )


@router.get("/consent/{patient_id}", response_model=List[ConsentResponse])
async def list_patient_consents(
    patient_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all consent and revocation records for a patient."""
    await ensure_patient_access(db, current_user, patient_id)
    stmt = select(ConsentRecord).where(ConsentRecord.patient_id == patient_id)
    res = await db.execute(stmt)
    records = res.scalars().all()

    return [
        ConsentResponse(
            id=str(r.id),
            patient_id=str(r.patient_id),
            consent_type=r.consent_type.value if hasattr(r.consent_type, 'value') else str(r.consent_type),
            scope=r.scope,
            granted_at=r.granted_at.isoformat(),
            revoked_at=r.revoked_at.isoformat() if r.revoked_at else None,
        )
        for r in records
    ]


@router.get("/audit-logs")
async def list_audit_logs(
    resource_type: Optional[str] = None,
    action: Optional[str] = None,
    limit: int = 100,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_role("admin")),
):
    """Admin-only view of the immutable compliance audit trail.

    Filters: optional resource_type / action; newest first. The trail itself
    is never deleted (see RetentionService).
    """
    stmt = select(AuditLog).order_by(AuditLog.timestamp.desc()).limit(min(max(limit, 1), 500))
    if resource_type:
        stmt = stmt.where(AuditLog.resource_type == resource_type)
    if action:
        stmt = stmt.where(AuditLog.action == AuditActionEnum(action))
    res = await db.execute(stmt)
    logs = res.scalars().all()
    return [
        {
            "id": str(log.id),
            "user_id": str(log.user_id),
            "action": log.action.value if hasattr(log.action, "value") else str(log.action),
            "resource_type": log.resource_type,
            "resource_id": str(log.resource_id),
            "timestamp": log.timestamp.isoformat() if log.timestamp else None,
            "ip_address": log.ip_address,
            "details": log.details or {},
        }
        for log in logs
    ]


@router.get("/patients/{patient_id}/export")
async def export_patient_data(
    patient_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """DPDP right of access — JSON dump of stored records, clinical detail gated by tier."""
    patient = await ensure_patient_access(db, current_user, patient_id)
    tier = await get_permission_tier(db, current_user, patient)
    audit = await ComplianceService.log_read_access(db, current_user.id, "data_export", patient_id)
    if audit is None and tier == "clinical":
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Export audit unavailable; screening data withheld",
        )
    export = await ComplianceService.export_patient_data(db, patient_id)
    if tier != "clinical":
        export.pop("risk_screening", None)
    return export


@router.post("/consent/{consent_id}/revoke")
async def revoke_consent(
    consent_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Revoke consent in accordance with DPDP right to withdraw consent."""
    record = await ComplianceService.revoke_consent(db, consent_id, actor=current_user)
    return {
        "message": "Consent record revoked.",
        "revoked_at": record.revoked_at.isoformat() if record and record.revoked_at else None,
    }

"""Caregiver & Clinician Dashboard API Routes."""

import uuid
from typing import List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.deps import ensure_patient_access, get_permission_tier
from app.services.compliance_service import ComplianceService
from app.services.dashboard_service import DashboardService
from app.models.all_models import AlertFlag, User, RoleEnum
from app.middleware.auth_middleware import get_current_user, require_role

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])


@router.get("/caregivers/{caregiver_id}/patients", response_model=List[Dict[str, Any]])
async def get_caregiver_patients(
    caregiver_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Retrieve all patients linked to this caregiver / ASHA worker."""
    # A caregiver can only view their own patients unless admin/clinician
    if current_user.id != caregiver_id and current_user.role not in (RoleEnum.ADMIN, RoleEnum.CLINICIAN):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied to other caregiver rosters."
        )
    roster = await DashboardService.get_caregiver_patients(db, caregiver_id)
    from app.services.compliance_service import ComplianceService

    await ComplianceService.log_read_access(
        db, current_user.id, "caregiver_roster", caregiver_id)
    return roster


@router.get("/patients/{patient_id}/summary", response_model=Dict[str, Any])
async def get_patient_summary(
    patient_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Retrieve 7-day cognitive trends, reminder compliance, and active alerts for a patient.

    No-implicit-access: patient owners, linked caregivers, and staff only; the
    read is audited."""
    patient = await ensure_patient_access(db, current_user, patient_id)
    await ComplianceService.log_read_access(db, current_user.id, "dashboard_summary", patient_id)
    summary = await DashboardService.get_patient_summary(db, patient_id)
    tier = await get_permission_tier(db, current_user, patient)
    summary["permission_tier"] = tier
    if tier != "clinical":
        summary.pop("accuracy_pct", None)
        summary.pop("avg_response_time_ms", None)
        summary.pop("clinical_flags", None)
        summary.pop("daily_trends", None)
        summary.pop("accuracy_drop_pct", None)
        summary["view"] = "basic"
    else:
        summary["view"] = "clinical"
    return summary


@router.post("/alerts/{alert_id}/acknowledge")
async def acknowledge_alert(
    alert_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Mark an AlertFlag / Risk notification as acknowledged by a caregiver or clinician."""
    stmt = select(AlertFlag).where(AlertFlag.id == alert_id)
    res = await db.execute(stmt)
    alert = res.scalar_one_or_none()

    if not alert:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert not found")

    # Enforce: a caregiver/clinician may only acknowledge alerts bound to
    # their own patient panel (patients they are linked to).
    await ensure_patient_access(db, current_user, alert.patient_id)

    from datetime import datetime, timezone
    alert.acknowledged_at = datetime.now(timezone.utc)
    alert.acknowledged_by = current_user.id
    await db.commit()
    await ComplianceService.log_write_access(
        db, current_user.id, "alert", str(alert_id),
        details={"patient_id": str(alert.patient_id), "acknowledged": True},
    )

    return {"message": "Alert acknowledged successfully", "alert_id": str(alert_id)}

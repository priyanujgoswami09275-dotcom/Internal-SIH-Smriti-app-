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
    roster = await DashboardService.get_caregiver_patients(
        db,
        caregiver_id,
        current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role),
    )
    if current_user.role == RoleEnum.FAMILY_CAREGIVER and current_user.id == caregiver_id:
        for patient in roster:
            if patient.get("permission_tier") == "basic":
                patient.pop("cognitive_baseline", None)
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
    if tier == "clinical":
        summary["view"] = "clinical"
        return summary

    # Basic allowlist: patient_id, patient_name, period, games_played,
    # reminders_total, reminders_acknowledged, reminders_missed, compliance_pct, permission_tier, view.
    basic_keys = (
        "patient_id",
        "period",
        "games_played",
        "reminders_total",
        "reminders_acknowledged",
        "reminders_missed",
        "compliance_pct",
    )
    basic_summary = {key: summary[key] for key in basic_keys if key in summary}
    basic_summary["patient_name"] = patient.name
    basic_summary["permission_tier"] = tier
    basic_summary["view"] = "basic"
    return basic_summary


@router.get("/patients/{patient_id}/risk-screening/consent")
async def get_risk_screening_consent(
    patient_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    patient = await ensure_patient_access(db, current_user, patient_id)
    tier = await get_permission_tier(db, current_user, patient)
    if tier != "clinical":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Clinical permission tier required for this resource",
        )
    granted = await ComplianceService.verify_consent(db, patient_id, "health_data")
    return {
        "patient_id": str(patient_id),
        "permission_tier": tier,
        "required_scope": "health_data",
        "health_data_consent": granted,
        "consent_state": "granted" if granted else "required",
    }


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

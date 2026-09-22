"""Reminder API Routes — Schedules, Events, Acknowledgments, Escalations."""
import uuid
from datetime import datetime
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.deps import ensure_patient_access, get_current_user
from app.database import get_db
from app.models.user import User, RoleEnum
from app.models.all_models import (
    ReminderSchedule, ReminderEvent,
    ReminderTypeEnum, ReminderStatusEnum, AcknowledgmentMethodEnum,
)
from app.services.compliance_service import ComplianceService
from app.services.reminder_service import ReminderService

router = APIRouter(prefix="/reminders", tags=["reminders"])


class CreateScheduleRequest(BaseModel):
    patient_id: uuid.UUID
    reminder_type: ReminderTypeEnum
    # Structured cadence understood by the generation job (times are IST):
    #   "08:00" | "daily@08:00" | "08:00,20:00" | "daily@08:00,13:00,20:00"
    # Free-text cadences are accepted but generate no automatic events.
    cadence: str = Field(examples=["daily@08:00,20:00"])


class ScheduleResponse(BaseModel):
    id: uuid.UUID
    patient_id: uuid.UUID
    reminder_type: ReminderTypeEnum
    cadence: str
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


class RecordEventRequest(BaseModel):
    schedule_id: uuid.UUID
    patient_id: uuid.UUID
    scheduled_at: datetime
    delivered_at: Optional[datetime] = None
    event_id: Optional[uuid.UUID] = None


class AcknowledgeEventRequest(BaseModel):
    method: AcknowledgmentMethodEnum = AcknowledgmentMethodEnum.BUTTON


class EventResponse(BaseModel):
    id: uuid.UUID
    schedule_id: uuid.UUID
    patient_id: uuid.UUID
    scheduled_at: datetime
    delivered_at: Optional[datetime]
    acknowledged_at: Optional[datetime]
    acknowledgment_method: Optional[AcknowledgmentMethodEnum]
    status: ReminderStatusEnum
    synced_at: Optional[datetime]

    class Config:
        from_attributes = True


@router.post("/schedules", response_model=ScheduleResponse)
async def create_schedule(
    request: CreateScheduleRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if current_user.role not in [RoleEnum.FAMILY_CAREGIVER, RoleEnum.ASHA_WORKER, RoleEnum.CLINICIAN, RoleEnum.ADMIN]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Only caregivers or clinicians can create schedules")

    await ensure_patient_access(db, current_user, request.patient_id)
    schedule = await ReminderService.create_schedule(
        db=db,
        patient_id=request.patient_id,
        reminder_type=request.reminder_type,
        cadence=request.cadence,
        created_by=current_user.id,
    )
    return schedule


@router.get("/schedules/{patient_id}", response_model=List[ScheduleResponse])
async def get_patient_schedules(
    patient_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List a patient's schedules. Patient/link access is enforced and audited."""
    await ensure_patient_access(db, current_user, patient_id)
    await ComplianceService.log_read_access(db, current_user.id, "reminder_schedule", patient_id)
    return await ReminderService.get_patient_schedules(db, patient_id)


@router.delete("/schedules/{schedule_id}")
async def deactivate_schedule(
    schedule_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Deactivate a schedule. The caller must have access to its patient."""
    res = await db.execute(select(ReminderSchedule).where(ReminderSchedule.id == schedule_id))
    schedule = res.scalar_one_or_none()
    if schedule is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Schedule not found")
    await ensure_patient_access(db, current_user, schedule.patient_id)
    success = await ReminderService.deactivate_schedule(db, schedule_id)
    if not success:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Schedule not found")
    return {"status": "deactivated"}


@router.post("/events", response_model=EventResponse)
async def record_event(
    request: RecordEventRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Record a reminder event. Caller must have access to the patient."""
    await ensure_patient_access(db, current_user, request.patient_id)
    # The schedule must exist and belong to the named patient — otherwise a
    # forged or cross-patient schedule_id would be stored on the event row.
    schedule = await ReminderService.get_schedule(db, request.schedule_id)
    if schedule is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Schedule not found"
        )
    if schedule.patient_id != request.patient_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="schedule does not belong to this patient",
        )
    event = await ReminderService.record_reminder_event(
        db=db,
        schedule_id=request.schedule_id,
        patient_id=request.patient_id,
        scheduled_at=request.scheduled_at,
        delivered_at=request.delivered_at,
        event_id=request.event_id,
    )
    return event


@router.post("/events/{event_id}/acknowledge", response_model=EventResponse)
async def acknowledge_event(
    event_id: uuid.UUID,
    request: AcknowledgeEventRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Enforce access to the event's patient before acknowledging.
    res = await db.execute(select(ReminderEvent).where(ReminderEvent.id == event_id))
    existing = res.scalar_one_or_none()
    if existing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    await ensure_patient_access(db, current_user, existing.patient_id)

    event = await ReminderService.acknowledge_reminder(
        db=db,
        event_id=event_id,
        method=request.method,
    )
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    return event


@router.get("/patients/{patient_id}/events", response_model=List[EventResponse])
async def get_patient_events(
    patient_id: uuid.UUID,
    status_filter: Optional[ReminderStatusEnum] = None,
    limit: int = 50,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List a patient's reminder events. Access is enforced and audited."""
    limit = min(max(limit, 1), 500)  # cap like the compliance audit trail
    await ensure_patient_access(db, current_user, patient_id)
    await ComplianceService.log_read_access(db, current_user.id, "reminder_event", patient_id)
    return await ReminderService.get_patient_reminder_events(
        db=db,
        patient_id=patient_id,
        status=status_filter,
        limit=limit,
    )


@router.post("/patients/{patient_id}/evaluate-escalations")
async def evaluate_escalations(
    patient_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await ensure_patient_access(db, current_user, patient_id)
    result = await ReminderService.evaluate_escalations(db, patient_id)
    # Fan out newly raised AlertFlags to family/ASHA via the notification
    # provider (console mock by default). Never fails the request.
    from app.services.notification_service import notify_escalation_results

    result["notified_recipients"] = await notify_escalation_results(db, patient_id, result)
    # Snapshot ORM alerts to plain dicts before returning (avoids lazy loads
    # during response serialization when expire_on_commit is enabled).
    result["alerts"] = [
        {
            "id": str(a.id),
            "trigger_type": a.trigger_type.value if hasattr(a.trigger_type, "value") else str(a.trigger_type),
            "severity": a.severity.value if hasattr(a.severity, "value") else str(a.severity),
            "alert_summary": a.alert_summary,
        }
        for a in result.get("alerts") or []
    ]
    return result

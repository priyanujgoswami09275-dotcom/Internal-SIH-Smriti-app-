"""Patient API Routes — PatientProfile CRUD + CaregiverPatientLink management.

Endpoints:
  POST   /patients            — create a patient profile (staff/caregiver; patient self-registers)
  GET    /patients/me         — current patient's own profile
  GET    /patients/{id}       — retrieve a patient profile
  GET    /patients/{id}/caregivers — list active caregiver links
  POST   /patients/{id}/caregivers — link a caregiver to a patient
"""
from datetime import date, datetime, timezone
from typing import List, Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import require_role
from app.database import get_db
from app.deps import ensure_patient_access, ensure_clinical_access, ensure_patient_owner, _role
from app.services.compliance_service import ComplianceService
from app.models.all_models import (
    PatientProfile,
    RiskScreening,
    ConsentRecord,
    CaregiverPatientLink,
    CognitiveBaselineEnum,
    RelationshipTypeEnum,
    PermissionTierEnum,
)
from app.models.user import User

router = APIRouter(prefix="/patients", tags=["patients"])

require_creator = require_role("patient", "family_caregiver", "asha_worker", "clinician")
require_caregiver_or_staff = require_role("family_caregiver", "asha_worker", "clinician")


# ============= Schemas =============


class PatientCreateRequest(BaseModel):
    name: str
    dob: Optional[date] = None
    cognitive_baseline: str = CognitiveBaselineEnum.HEALTHY.value
    region: Optional[str] = None
    district: Optional[str] = None
    routine: Optional[dict] = None
    user_id: Optional[UUID] = None  # link an existing patient-role account


class PatientResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: Optional[UUID]
    name: str
    dob: Optional[date]
    cognitive_baseline: str
    region: Optional[str]
    district: Optional[str]
    created_at: datetime


class CaregiverLinkRequest(BaseModel):
    caregiver_id: UUID
    relationship_type: RelationshipTypeEnum = RelationshipTypeEnum.FAMILY
    permission_tier: PermissionTierEnum = PermissionTierEnum.BASIC


class CaregiverLinkResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    caregiver_id: UUID
    patient_id: UUID
    relationship_type: RelationshipTypeEnum
    permission_tier: PermissionTierEnum
    consent_granted_at: datetime
    is_active: bool
    created_at: datetime


# ============= Helpers =============


async def _get_patient(db: AsyncSession, patient_id: UUID) -> Optional[PatientProfile]:
    res = await db.execute(select(PatientProfile).where(PatientProfile.id == patient_id))
    return res.scalar_one_or_none()


async def _can_view_patient(db: AsyncSession, user: User, patient: PatientProfile) -> bool:
    """No-implicit-access: staff/owner may view; caregivers need an active link."""
    if patient is None:
        return False
    role = user.role.value if hasattr(user.role, "value") else str(user.role)
    if role in ("admin", "clinician", "asha_worker"):
        return True
    if patient.user_id == user.id:
        return True
    if role in ("family_caregiver", "patient"):
        res = await db.execute(
            select(CaregiverPatientLink).where(
                CaregiverPatientLink.caregiver_id == user.id,
                CaregiverPatientLink.patient_id == patient.id,
                CaregiverPatientLink.is_active == True,
            )
        )
        return res.scalar_one_or_none() is not None
    return False


def resolve_profile_binding(user: User, requested_id: Optional[UUID]) -> Optional[UUID]:
    if not user.is_active or user.id is None:
        raise HTTPException(status_code=403, detail="Active account required")
    if _role(user) == "patient":
        if requested_id not in (None, user.id):
            raise HTTPException(status_code=403, detail="Patients may only self-register")
        return user.id
    if _role(user) not in {"admin", "clinician", "asha_worker"} or requested_id is not None:
        raise HTTPException(status_code=403, detail="Only staff may create unbound profiles; account binding requires patient self-registration")
    return None


def validate_caregiver_target(owner: User, target: Optional[User], relationship: RelationshipTypeEnum) -> None:
    roles = {"family": "family_caregiver", "asha": "asha_worker", "clinician": "clinician"}
    if (
        target is None or not target.is_active or target.id == owner.id
        or _role(target) != roles.get(relationship)
    ):
        raise HTTPException(status_code=422, detail="Caregiver must be a different active account with the matching relationship role")


def _baseline(value: str) -> CognitiveBaselineEnum:
    try:
        return CognitiveBaselineEnum(value)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Invalid cognitive_baseline: {value}. Choose from {[e.value for e in CognitiveBaselineEnum]}",
        )


from app.services import risk_screening_service


# ============= Risk Screening Endpoint =============


class RiskScreeningRequest(BaseModel):
    """32 feature fields in the model input guide's canonical order."""
    model_config = ConfigDict(extra="forbid")

    Age: Optional[float] = None
    Gender: Optional[int] = None
    Ethnicity: Optional[int] = None
    EducationLevel: Optional[int] = None
    BMI: Optional[float] = None
    Smoking: Optional[int] = None
    AlcoholConsumption: Optional[float] = None
    PhysicalActivity: Optional[float] = None
    DietQuality: Optional[float] = None
    SleepQuality: Optional[float] = None
    FamilyHistoryAlzheimers: Optional[int] = None
    CardiovascularDisease: Optional[int] = None
    Diabetes: Optional[int] = None
    Depression: Optional[int] = None
    HeadInjury: Optional[int] = None
    Hypertension: Optional[int] = None
    SystolicBP: Optional[int] = None
    DiastolicBP: Optional[int] = None
    CholesterolTotal: Optional[float] = None
    CholesterolLDL: Optional[float] = None
    CholesterolHDL: Optional[float] = None
    CholesterolTriglycerides: Optional[float] = None
    MMSE: Optional[float] = None
    FunctionalAssessment: Optional[float] = None
    MemoryComplaints: Optional[int] = None
    BehavioralProblems: Optional[int] = None
    ADL: Optional[float] = None
    Confusion: Optional[int] = None
    Disorientation: Optional[int] = None
    PersonalityChanges: Optional[int] = None
    DifficultyCompletingTasks: Optional[int] = None
    Forgetfulness: Optional[int] = None


class RiskScreeningResponse(BaseModel):
    status: str
    risk_score: Optional[float] = None
    probability: Optional[float] = None
    tier: Optional[str] = None
    feature_count: Optional[int] = None
    note: Optional[str] = None
    errors: Optional[List[str]] = None
    message: Optional[str] = None
    model_version: Optional[str] = None


@router.post("/{patient_id}/risk-screening", response_model=RiskScreeningResponse)
async def risk_screening(
    patient_id: UUID,
    body: RiskScreeningRequest,
    current_user: User = Depends(require_caregiver_or_staff),
    db: AsyncSession = Depends(get_db),
):
    """Run consented preliminary screening and atomically audit/persist success."""
    await ensure_clinical_access(db, current_user, patient_id)
    consent = (await db.execute(
        select(ConsentRecord).where(
            ConsentRecord.patient_id == patient_id,
            ConsentRecord.revoked_at.is_(None),
            ConsentRecord.scope.in_(["health_data", "all"]),
        ).order_by(ConsentRecord.granted_at.desc(), ConsentRecord.id.desc()).limit(1).with_for_update()
    )).scalar_one_or_none()
    if consent is None:
        raise HTTPException(status_code=403, detail="Active consent required for scope 'health_data'")
    result = risk_screening_service.run_inference(body.model_dump(exclude_unset=True))
    try:
        if result["status"] == "ok":
            dialect = db.get_bind().dialect.name
            if dialect == "postgresql":
                from sqlalchemy.dialects.postgresql import insert
            elif dialect == "sqlite":
                from sqlalchemy.dialects.sqlite import insert
            else:
                raise RuntimeError("Unsupported screening persistence dialect")
            values = {
                "patient_id": patient_id,
                "consent_id": consent.id,
                "probability": result["probability"],
                "risk_score": result["risk_score"],
                "model_version": result["model_version"],
                "screened_at": datetime.now(timezone.utc).replace(tzinfo=None),
            }
            await db.execute(insert(RiskScreening).values(**values).on_conflict_do_update(
                index_elements=["patient_id"],
                set_={key: value for key, value in values.items() if key != "patient_id"},
            ))
        await ComplianceService.log_audit_access(
            db, current_user.id, "write", "risk_screening", patient_id,
            details={"status": result["status"], "model_version": risk_screening_service.MODEL_VERSION},
        )
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=503, detail="Screening persistence or audit unavailable")
    return RiskScreeningResponse(**result)


def _risk_tier(score: float) -> str:
    """Same thresholds as risk_screening_service.run_inference."""
    return "low_risk" if score < 33 else "moderate_risk" if score < 67 else "high_risk"


@router.get("/{patient_id}/risk-screening", response_model=RiskScreeningResponse)
async def get_risk_screening(
    patient_id: UUID,
    current_user: User = Depends(require_caregiver_or_staff),
    db: AsyncSession = Depends(get_db),
):
    """Latest persisted preliminary screening for rehydration.

    Same gates as POST: caregiver/staff role, clinical permission tier, and
    active health_data (or all) consent. Read is audited.
    """
    await ensure_clinical_access(db, current_user, patient_id)
    consent = (await db.execute(
        select(ConsentRecord).where(
            ConsentRecord.patient_id == patient_id,
            ConsentRecord.revoked_at.is_(None),
            ConsentRecord.scope.in_(["health_data", "all"]),
        ).order_by(ConsentRecord.granted_at.desc(), ConsentRecord.id.desc()).limit(1)
    )).scalar_one_or_none()
    if consent is None:
        raise HTTPException(status_code=403, detail="Active consent required for scope 'health_data'")
    row = (await db.execute(
        select(RiskScreening).where(RiskScreening.patient_id == patient_id)
    )).scalar_one_or_none()
    await ComplianceService.log_read_access(
        db, current_user.id, "risk_screening", patient_id,
        details={"found": row is not None},
    )
    if row is None:
        return RiskScreeningResponse(status="not_assessed")
    return RiskScreeningResponse(
        status="ok",
        risk_score=row.risk_score,
        probability=row.probability,
        tier=_risk_tier(row.risk_score),
        feature_count=32,
        note="Preliminary screening only; not a clinical diagnosis",
        model_version=row.model_version,
    )


# ============= Endpoints =============


@router.post("", response_model=PatientResponse, status_code=status.HTTP_201_CREATED)
async def create_patient(
    body: PatientCreateRequest,
    current_user: User = Depends(require_creator),
    db: AsyncSession = Depends(get_db),
):
    """Create a patient profile. A patient-role account can self-register (own user_id)."""
    user_id = resolve_profile_binding(current_user, body.user_id)
    if user_id is not None:
        locked_user = (await db.execute(
            select(User).where(User.id == user_id).with_for_update()
            .execution_options(populate_existing=True)
        )).scalar_one_or_none()
        if locked_user is None:
            raise HTTPException(status_code=403, detail="Active patient account required")
        user_id = resolve_profile_binding(locked_user, body.user_id)
        existing = (await db.execute(
            select(PatientProfile.id).where(PatientProfile.user_id == user_id).limit(1)
        )).scalar_one_or_none()
        if existing is not None:
            raise HTTPException(status_code=409, detail="Patient profile already exists for this account")

    patient = PatientProfile(
        user_id=user_id,
        name=body.name,
        dob=body.dob,
        cognitive_baseline=_baseline(body.cognitive_baseline),
        region=body.region,
        district=body.district,
        routine=body.routine,
    )
    db.add(patient)
    await db.commit()
    await db.refresh(patient)
    return patient


@router.get("/me", response_model=PatientResponse)
async def get_my_patient(
    current_user: User = Depends(require_role("patient", "family_caregiver", "asha_worker", "clinician")),
    db: AsyncSession = Depends(get_db),
):
    """Return the PatientProfile bound to the current account, if any."""
    res = await db.execute(select(PatientProfile).where(PatientProfile.user_id == current_user.id))
    patient = res.scalar_one_or_none()
    if patient is None:
        raise HTTPException(status_code=404, detail="No patient profile linked to this account")
    return patient


@router.get("/{patient_id}", response_model=PatientResponse)
async def get_patient(
    patient_id: UUID,
    current_user: User = Depends(require_role("patient", "family_caregiver", "asha_worker", "clinician")),
    db: AsyncSession = Depends(get_db),
):
    """Retrieve a patient profile. Access is audited: staff see rosters, others need a link."""
    patient = await ensure_patient_access(db, current_user, patient_id)
    await ComplianceService.log_read_access(
        db, current_user.id, "patient_profile", patient_id
    )
    return patient


@router.get("/{patient_id}/caregivers", response_model=List[CaregiverLinkResponse])
async def list_patient_caregivers(
    patient_id: UUID,
    current_user: User = Depends(require_role("patient", "family_caregiver", "asha_worker", "clinician")),
    db: AsyncSession = Depends(get_db),
):
    """List active caregivers linked to a patient."""
    await ensure_patient_access(db, current_user, patient_id)
    res = await db.execute(
        select(CaregiverPatientLink)
        .where(
            CaregiverPatientLink.patient_id == patient_id,
            CaregiverPatientLink.is_active == True,
        )
        .order_by(CaregiverPatientLink.created_at)
    )
    return list(res.scalars().all())


@router.post("/{patient_id}/caregivers", response_model=CaregiverLinkResponse, status_code=status.HTTP_201_CREATED)
async def link_caregiver(
    patient_id: UUID,
    body: CaregiverLinkRequest,
    current_user: User = Depends(require_role("patient")),
    db: AsyncSession = Depends(get_db),
):
    await ensure_patient_owner(db, current_user, patient_id)
    target = (await db.execute(select(User).where(User.id == body.caregiver_id))).scalar_one_or_none()
    validate_caregiver_target(current_user, target, body.relationship_type)

    existing = await db.execute(
        select(CaregiverPatientLink).where(
            CaregiverPatientLink.caregiver_id == body.caregiver_id,
            CaregiverPatientLink.patient_id == patient_id,
            CaregiverPatientLink.is_active == True,
        )
    )
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(status_code=409, detail="Caregiver already linked to this patient")

    link = CaregiverPatientLink(
        id=uuid4(),
        caregiver_id=body.caregiver_id,
        patient_id=patient_id,
        relationship_type=body.relationship_type,
        permission_tier=body.permission_tier,
        is_active=True,
    )
    try:
        db.add(link)
        audit = await ComplianceService.log_audit_access(
            db, current_user.id, "write", "caregiver_link", link.id,
            details={"patient_id": str(patient_id), "caregiver_id": str(body.caregiver_id),
                     "relationship_type": body.relationship_type.value, "permission_tier": body.permission_tier.value},
        )
        if audit is None:
            raise RuntimeError("Mutation audit unavailable")
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=503, detail="Caregiver link persistence or audit unavailable")
    return link

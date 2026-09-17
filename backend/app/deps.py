"""Auth + patient-access dependencies.

- get_current_user: extracts the user from the JWT Bearer token.
- ensure_patient_access / can_access_patient: shared no-implicit-access rule
  used by every route that touches a patient's data (patients, reminders,
  dashboard, companion, reports). Staff (asha/clinician/admin) may view any
  patient; owners and family caregivers need an active CaregiverPatientLink.
"""
import uuid as uuid_lib
from typing import Optional
from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models.all_models import CaregiverPatientLink, PatientProfile
from app.services.auth_service import AuthService
from app.services.compliance_service import ComplianceService
from app.models.user import User

security = HTTPBearer()


def _role(user: User) -> str:
    return user.role.value if hasattr(user.role, "value") else str(user.role)


def _parse_sub(user_id: str):
    """JWT 'sub' is a stringified UUID; normalize for UUID column comparison."""
    try:
        return uuid_lib.UUID(str(user_id))
    except (ValueError, TypeError):
        return user_id


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> User:
    payload = AuthService.verify_token(credentials.credentials)
    if payload is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user_id = payload.get("sub")
    if user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload")
    result = await db.execute(select(User).where(User.id == _parse_sub(user_id)))
    user = result.scalar_one_or_none()
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found or inactive")
    return user


async def load_patient(db: AsyncSession, patient_id: UUID) -> Optional[PatientProfile]:
    """Fetch a patient profile by id, or None."""
    res = await db.execute(select(PatientProfile).where(PatientProfile.id == patient_id))
    return res.scalar_one_or_none()


def require_patient_owner(user: User, patient: PatientProfile) -> None:
    if (
        not user.is_active
        or _role(user) != "patient"
        or user.id is None
        or patient.user_id != user.id
    ):
        raise HTTPException(status_code=403, detail="Active patient owner required")


async def ensure_patient_owner(
    db: AsyncSession, current_user: User, patient_id: UUID
) -> PatientProfile:
    patient = (await db.execute(
        select(PatientProfile).where(PatientProfile.id == patient_id)
        .with_for_update().execution_options(populate_existing=True)
    )).scalar_one_or_none()
    if patient is None:
        raise HTTPException(status_code=404, detail="Patient not found")
    require_patient_owner(current_user, patient)
    return patient


async def can_access_patient(
    db: AsyncSession, user: User, patient: Optional[PatientProfile]
) -> bool:
    """No-implicit-access: staff may view any patient; owners and linked
    family caregivers need an active CaregiverPatientLink."""
    if patient is None:
        return False
    role = _role(user)
    if role in ("admin", "clinician", "asha_worker"):
        return True
    if patient.user_id == user.id:
        return True
    if role in ("family_caregiver", "patient"):
        res = await db.execute(
            select(CaregiverPatientLink).where(
                CaregiverPatientLink.caregiver_id == user.id,
                CaregiverPatientLink.patient_id == patient.id,
                CaregiverPatientLink.is_active == True,  # noqa: E712
            )
        )
        return res.scalar_one_or_none() is not None
    return False


async def ensure_patient_access(
    db: AsyncSession, current_user: User, patient_id: UUID
) -> PatientProfile:
    """Resolve a patient profile and enforce no-implicit-access.

    404 when the patient does not exist; 403 when the caller has no link or
    role entitlement to that patient's data.
    """
    patient = await load_patient(db, patient_id)
    if patient is None:
        raise HTTPException(status_code=404, detail="Patient not found")
    if not await can_access_patient(db, current_user, patient):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No caregiver link or permission for this patient",
        )
    return patient


async def ensure_consent(
    db: AsyncSession, patient_id: UUID, required_scope: str
) -> None:
    """Purpose-limitation gate: 403 unless an active ConsentRecord covers the scope."""
    ok = await ComplianceService.verify_consent(db, patient_id, required_scope)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Active consent required for scope '{required_scope}'",
        )


async def get_permission_tier(
    db: AsyncSession, user: User, patient: PatientProfile
) -> str:
    """Resolve basic | clinical for this caller against this patient."""
    role = _role(user)
    if role in ("admin", "clinician", "asha_worker"):
        return "clinical"
    if patient.user_id == user.id:
        return "clinical"
    res = await db.execute(
        select(CaregiverPatientLink).where(
            CaregiverPatientLink.caregiver_id == user.id,
            CaregiverPatientLink.patient_id == patient.id,
            CaregiverPatientLink.is_active == True,  # noqa: E712
        )
    )
    link = res.scalar_one_or_none()
    if link is None:
        return "basic"
    tier = link.permission_tier
    return tier.value if hasattr(tier, "value") else str(tier or "basic")


async def ensure_clinical_access(
    db: AsyncSession, current_user: User, patient_id: UUID
) -> PatientProfile:
    """Family caregivers on the basic tier cannot read clinical detail."""
    patient = await ensure_patient_access(db, current_user, patient_id)
    tier = await get_permission_tier(db, current_user, patient)
    if tier != "clinical":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Clinical permission tier required for this resource",
        )
    return patient

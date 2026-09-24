"""Voice Companion API Routes (Phase 9).

- Chat (text / voice) is authenticated. Patients may only chat as themselves;
  staff see any patient; family caregivers need an active link (checked via
  the shared patient-access rules on the patients router).
- System prompt versions are managed via /companion/config endpoints
  (admin / clinician only) and stored in voice_companion_configs.
"""

import uuid
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import require_role
from app.database import get_db
from app.deps import can_access_patient, ensure_consent, load_patient
from app.services.compliance_service import ComplianceService
from app.services.conversation_store import get_conversation_store
from app.models.all_models import PatientProfile, VoiceCompanionConfig
from app.models.user import User
from app.services.voice_companion_service import (
    VoiceCompanionService,
    CompanionServiceError,
)

router = APIRouter(prefix="/companion", tags=["Voice Companion"])

require_viewer = require_role("patient", "family_caregiver", "asha_worker", "clinician")
require_admin_clinician = require_role("clinician", "admin")


# ============= Schemas =============


class TextChatRequest(BaseModel):
    patient_id: uuid.UUID
    # Bounded so an oversized message can never reach the LLM provider.
    message: str = Field(max_length=2000)
    language: str = "assamese"
    history: Optional[List[dict]] = Field(default=None, max_length=50)


class VoiceChatRequest(BaseModel):
    patient_id: uuid.UUID
    audio_base64: str
    language: str = "assamese"


class ConfigCreateRequest(BaseModel):
    version: str
    system_prompt: str
    persona_name: str = "Saathi"
    activate: bool = True


class ConfigResponse(BaseModel):
    version: str
    persona_name: str
    system_prompt: str
    is_active: bool
    created_at: datetime

    @classmethod
    def from_model(cls, config: VoiceCompanionConfig) -> "ConfigResponse":
        return cls(
            version=config.version,
            persona_name=config.persona_name,
            system_prompt=config.system_prompt,
            is_active=config.is_active,
            created_at=config.created_at,
        )


# ============= Helpers =============


async def _resolve_patient_access(
    db: AsyncSession, current_user: User, patient_id: uuid.UUID
) -> Optional[PatientProfile]:
    """Load profile and enforce no-implicit-access.

    Patients may only chat as themselves; family caregivers need an active
    link; staff (ASHA/clinician) may chat with any patient.
    """
    patient = await load_patient(db, patient_id)
    if patient is None:
        raise HTTPException(status_code=404, detail="Patient not found")

    role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role)
    if role == "patient" and patient.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Patients may only chat as themselves",
        )
    if not await can_access_patient(db, current_user, patient):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No caregiver link or permission for this patient",
        )
    return patient


def _companion_error(exc: Exception) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail=getattr(exc, "message", str(exc)),
    )


# ============= Chat endpoints =============


@router.post("/chat/text")
async def chat_text(
    req: TextChatRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_viewer),
):
    """Text-based conversation with the elder companion (Redis-backed history)."""
    patient = await _resolve_patient_access(db, current_user, req.patient_id)
    await ensure_consent(db, req.patient_id, "voice_companion")
    await ComplianceService.log_write_access(
        db,
        current_user.id,
        "conversation",
        str(req.patient_id),
        details={"channel": "text"},
    )
    service = VoiceCompanionService()
    store = await get_conversation_store()
    history = await store.get(req.patient_id)
    # client-supplied turns (offline replay) extend the stored ones
    if req.history:
        history = history + [h for h in req.history if h not in history]
    try:
        result = await service.chat(
            user_message=req.message,
            patient_name=patient.name,
            patient_language=req.language,
            conversation_history=history,
            db=db,
        )
    except CompanionServiceError as exc:
        raise _companion_error(exc)
    if not result.get("fallback"):
        await store.append(req.patient_id, req.message, result["reply_text"])
    return result


@router.post("/chat/voice")
async def chat_voice(
    req: VoiceChatRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_viewer),
):
    """End-to-end voice conversation: Bhashini ASR -> Claude -> Bhashini TTS."""
    patient = await _resolve_patient_access(db, current_user, req.patient_id)
    await ensure_consent(db, req.patient_id, "voice_companion")
    await ComplianceService.log_write_access(
        db,
        current_user.id,
        "conversation",
        str(req.patient_id),
        details={"channel": "voice"},
    )
    service = VoiceCompanionService()
    store = await get_conversation_store()
    history = await store.get(req.patient_id)
    try:
        result = await service.voice_chat_pipeline(
            audio_base64=req.audio_base64,
            patient_name=patient.name,
            language=req.language,
            conversation_history=history,
        )
    except CompanionServiceError as exc:
        raise _companion_error(exc)
    recognized = result.get("recognized_query") or ""
    if recognized and not result.get("fallback"):
        await store.append(req.patient_id, recognized, result["reply_text"])
    return result


# ============= Prompt version management (admin / clinician) =============


@router.get("/config", response_model=List[ConfigResponse])
async def list_voice_configs(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_admin_clinician),
):
    """List all voice companion system-prompt versions (oldest first)."""
    configs = await VoiceCompanionService.list_configs(db)
    return [ConfigResponse.from_model(c) for c in configs]


@router.post("/config", response_model=ConfigResponse, status_code=status.HTTP_201_CREATED)
async def create_voice_config(
    req: ConfigCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_admin_clinician),
):
    """Create a new versioned system prompt; optionally activate it."""
    try:
        config = await VoiceCompanionService.create_config(
            db=db,
            version=req.version,
            system_prompt=req.system_prompt,
            persona_name=req.persona_name,
            activate=req.activate,
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    return ConfigResponse.from_model(config)


@router.post("/config/{version}/activate", response_model=ConfigResponse)
async def activate_voice_config(
    version: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_admin_clinician),
):
    """Activate a previously created prompt version."""
    config = await VoiceCompanionService.activate_config(db, version)
    if config is None:
        raise HTTPException(status_code=404, detail="Voice companion version not found")
    return ConfigResponse.from_model(config)

"""Speech & Language Translation API Routes.

Routes wrap the configured language provider (Bhashini when credentials are
set, Mock otherwise). Provider failures surface as HTTP 502; unsupported
languages as HTTP 400.
"""

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import Optional

from app.deps import get_current_user
from app.models.user import User
from app.services.language_service import (
    LanguageServiceProvider,
    LanguageServiceError,
    UnsupportedLanguageError,
    get_language_service,
)

router = APIRouter(prefix="/language", tags=["Language & Speech"])


class ASRRequest(BaseModel):
    audio_base64: str
    source_language: str = "assamese"


class TTSRequest(BaseModel):
    text: str
    target_language: str = "assamese"


class TranslationRequest(BaseModel):
    text: str
    source_language: str = "assamese"
    target_language: str = "english"


def _get_provider() -> LanguageServiceProvider:
    """Depends-safe wrapper: keep FastAPI from introspecting httpx transport args."""
    return get_language_service()


def _handle(exc: LanguageServiceError) -> HTTPException:
    if isinstance(exc, UnsupportedLanguageError):
        # Language not covered by the active provider's models — a distinct
        # code so clients render "not yet available" instead of an error.
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=exc.message,
            headers={"X-Unsupported-Language": exc.language},
        )
    if exc.provider_status and 500 <= exc.provider_status < 600:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=exc.message
        )
    # Unsupported language / upstream 4xx payloads
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST
        if exc.provider_status is None
        else status.HTTP_502_BAD_GATEWAY,
        detail=exc.message,
    )


@router.get("/status")
async def language_status(
    lang_service: LanguageServiceProvider = Depends(_get_provider),
):
    """Report the active speech provider and supported NER languages."""
    return {
        "provider": getattr(lang_service, "name", "unknown"),
        "supported_languages": lang_service.supported_languages(),
    }


@router.post("/asr")
async def speech_to_text(
    req: ASRRequest,
    lang_service: LanguageServiceProvider = Depends(_get_provider),
    current_user: User = Depends(get_current_user),
):
    """Convert patient spoken audio into recognized text in NER regional language."""
    try:
        text = await lang_service.speech_to_text(req.audio_base64, req.source_language)
    except LanguageServiceError as exc:
        _handle(exc)
    return {"recognized_text": text, "source_language": req.source_language, "provider": getattr(lang_service, "name", "unknown")}


@router.post("/tts")
async def text_to_speech(
    req: TTSRequest,
    lang_service: LanguageServiceProvider = Depends(_get_provider),
    current_user: User = Depends(get_current_user),
):
    """Synthesize text into spoken audio in patient's preferred language."""
    try:
        audio = await lang_service.text_to_speech(req.text, req.target_language)
    except LanguageServiceError as exc:
        _handle(exc)
    return {"audio_base64": audio, "target_language": req.target_language, "provider": getattr(lang_service, "name", "unknown")}


@router.post("/translate")
async def translate_text(
    req: TranslationRequest,
    lang_service: LanguageServiceProvider = Depends(_get_provider),
    current_user: User = Depends(get_current_user),
):
    """Translate between NER regional languages and English."""
    try:
        translated = await lang_service.translate_text(
            req.text, req.source_language, req.target_language
        )
    except LanguageServiceError as exc:
        _handle(exc)
    return {
        "original_text": req.text,
        "translated_text": translated,
        "source_language": req.source_language,
        "target_language": req.target_language,
    }

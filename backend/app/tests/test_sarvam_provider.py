"""Sarvam AI provider tests — Phase 8 alternate.

Mock-transport tests verify request payloads, auth headers, response parsing
(translate JSON, STT multipart, TTS base64 audios[]), and the
Khasi/Mizo UnsupportedLanguageError contract. A live test at the bottom calls
the real API with an Assamese phrase — skipped unless RUN_LIVE_SARVAM=1 and
SARVAM_API_KEY are both set (same opt-in pattern as the AI4Bharat live test).
"""

import base64
import json
import os

import httpx
import pytest

from app.config import settings
from app.services.language_service import (
    SARVAM_LANG_CODES,
    Ai4BharatLanguageService,
    BhashiniLanguageService,
    LanguageServiceError,
    MockLanguageService,
    SarvamLanguageService,
    UnsupportedLanguageError,
    get_language_service,
)

LIVE = pytest.mark.skipif(
    not (os.environ.get("RUN_LIVE_SARVAM") == "1" and settings.SARVAM_API_KEY),
    reason="needs RUN_LIVE_SARVAM=1 and SARVAM_API_KEY",
)


def _client(handler, key: str = "test-key") -> SarvamLanguageService:
    return SarvamLanguageService(
        api_key=key,
        base_url="https://api.sarvam.ai",
        transport=httpx.MockTransport(handler),
    )


# ---------- construction ----------


def test_requires_key():
    with pytest.raises(LanguageServiceError, match="SARVAM_API_KEY"):
        SarvamLanguageService(api_key="")


def test_supported_languages_include_ner_four():
    langs = SarvamLanguageService(api_key="t").supported_languages()
    for expected in ("assamese", "bengali", "bodo", "manipuri"):
        assert expected in langs
    assert "khasi" not in langs
    assert "mizo" not in langs


def test_lang_code_mapping():
    assert SARVAM_LANG_CODES["assamese"] == "as-IN"
    assert SARVAM_LANG_CODES["bengali"] == "bn-IN"
    assert SARVAM_LANG_CODES["bodo"] == "brx-IN"
    assert SARVAM_LANG_CODES["manipuri"] == "mni-IN"


# ---------- translation ----------


@pytest.mark.asyncio
async def test_translate_payload_and_parse():
    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["headers"] = dict(request.headers)
        captured["json"] = json.loads(request.content.decode())
        return httpx.Response(
            200,
            json={
                "request_id": "r1",
                "translated_text": "Hello, how are you today?",
                "source_language_code": "as-IN",
            },
        )

    client = _client(handler)
    result = await client.translate_text("নমস্কাৰ, আজি কেনে আছে?", "assamese", "english")
    assert result == "Hello, how are you today?"

    assert captured["url"] == "https://api.sarvam.ai/translate"
    assert captured["headers"]["api-subscription-key"] == "test-key"
    assert captured["json"] == {
        "input": "নমস্কাৰ, আজি কেনে আছে?",
        "source_language_code": "as-IN",
        "target_language_code": "en-IN",
        "model": "sarvam-translate:v1",
    }


@pytest.mark.asyncio
async def test_translate_same_language_short_circuits():
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        return httpx.Response(200, json={})

    client = _client(handler)
    assert await client.translate_text("namaskar", "assamese", "assamese") == "namaskar"
    assert calls == []


@pytest.mark.asyncio
async def test_translate_unsupported_language_raises():
    client = _client(lambda r: httpx.Response(200, json={}))
    with pytest.raises(UnsupportedLanguageError, match="not yet available") as exc:
        await client.translate_text("hi", "khasi", "english")
    assert exc.value.language == "khasi"


@pytest.mark.asyncio
async def test_translate_upstream_error_has_status():
    client = _client(lambda r: httpx.Response(401, text="invalid key"))
    with pytest.raises(LanguageServiceError) as exc_info:
        await client.translate_text("hi", "assamese", "english")
    assert exc_info.value.provider_status == 401


# ---------- ASR ----------


@pytest.mark.asyncio
async def test_asr_payload_and_parse():
    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["headers"] = dict(request.headers)
        captured["content_type"] = request.headers.get("content-type", "")
        captured["url"] = str(request.url)
        return httpx.Response(
            200,
            json={
                "request_id": "r2",
                "transcript": "নমস্কাৰ",
                "language_code": "as-IN",
            },
        )

    client = _client(handler)
    audio = base64.b64encode(b"fake-wav-bytes").decode()
    text = await client.speech_to_text(audio, "assamese")
    assert text == "নমস্কাৰ"

    assert captured["url"] == "https://api.sarvam.ai/speech-to-text"
    assert captured["headers"]["api-subscription-key"] == "test-key"
    assert "multipart/form-data" in captured["content_type"]


@pytest.mark.asyncio
async def test_asr_unsupported_language_raises():
    client = _client(lambda r: httpx.Response(200, json={"transcript": ""}))
    with pytest.raises(UnsupportedLanguageError):
        await client.speech_to_text("audio", "khasi")


# ---------- TTS ----------


@pytest.mark.asyncio
async def test_tts_payload_and_parse_base64_audios():
    captured = {}
    fake_audio = base64.b64encode(b"RIFF....wav-bytes").decode()

    def handler(request: httpx.Request) -> httpx.Response:
        captured["headers"] = dict(request.headers)
        captured["json"] = json.loads(request.content.decode())
        captured["url"] = str(request.url)
        return httpx.Response(200, json={"request_id": "r3", "audios": [fake_audio]})

    client = _client(handler)
    # Bulbul-covered language (Wave 6 gating): assamese is NMT/ASR-only and
    # now raises UnsupportedLanguageError before any network call.
    audio_b64 = await client.text_to_speech("नमस्कार", "hindi")
    assert audio_b64 == fake_audio
    # Proves the audios[] entry is valid base64 (interface returns base64 audio).
    assert base64.b64decode(audio_b64) == b"RIFF....wav-bytes"

    assert captured["url"] == "https://api.sarvam.ai/text-to-speech"
    assert captured["headers"]["api-subscription-key"] == "test-key"
    assert captured["json"]["text"] == "नमस्कार"
    assert captured["json"]["language_code"] == "hi-IN"
    assert captured["json"]["model"] == "bulbul:v3"


@pytest.mark.asyncio
async def test_tts_unsupported_language_raises():
    client = _client(lambda r: httpx.Response(200, json={"audios": []}))
    with pytest.raises(UnsupportedLanguageError):
        await client.text_to_speech("hello", "mizo")


@pytest.mark.asyncio
async def test_tts_empty_audios_raises():
    client = _client(lambda r: httpx.Response(200, json={"request_id": "r", "audios": []}))
    with pytest.raises(LanguageServiceError, match="audios"):
        await client.text_to_speech("hello", "bengali")


# ---------- factory chain ----------


@pytest.mark.asyncio
async def test_factory_sarvam_forced_without_key_raises(monkeypatch):
    monkeypatch.setattr(settings, "SARVAM_API_KEY", "")
    with pytest.raises(LanguageServiceError, match="SARVAM_API_KEY"):
        get_language_service(provider="sarvam")


@pytest.mark.asyncio
async def test_factory_auto_prefers_sarvam_when_key_set(monkeypatch):
    monkeypatch.setattr(settings, "SARVAM_API_KEY", "sarvam-real")
    monkeypatch.setattr(settings, "HUGGINGFACE_API_TOKEN", "hf-real")
    monkeypatch.setattr(settings, "BHASHINI_API_KEY", "real-key")
    monkeypatch.setattr(settings, "BHASHINI_USER_ID", "uid-1")
    service = get_language_service(provider="auto")
    assert isinstance(service, SarvamLanguageService)


@pytest.mark.asyncio
async def test_factory_auto_falls_back_to_ai4bharat_without_sarvam(monkeypatch):
    monkeypatch.setattr(settings, "SARVAM_API_KEY", "")
    monkeypatch.setattr(settings, "HUGGINGFACE_API_TOKEN", "hf-real")
    monkeypatch.setattr(settings, "BHASHINI_API_KEY", "real-key")
    monkeypatch.setattr(settings, "BHASHINI_USER_ID", "uid-1")
    service = get_language_service(provider="auto")
    assert isinstance(service, Ai4BharatLanguageService)


@pytest.mark.asyncio
async def test_factory_auto_falls_back_to_bhashini(monkeypatch):
    monkeypatch.setattr(settings, "SARVAM_API_KEY", "")
    monkeypatch.setattr(settings, "HUGGINGFACE_API_TOKEN", "")
    monkeypatch.setattr(settings, "BHASHINI_API_KEY", "real-key")
    monkeypatch.setattr(settings, "BHASHINI_USER_ID", "uid-1")
    service = get_language_service(provider="auto")
    assert isinstance(service, BhashiniLanguageService)


@pytest.mark.asyncio
async def test_factory_auto_falls_back_to_mock(monkeypatch):
    monkeypatch.setattr(settings, "SARVAM_API_KEY", "")
    monkeypatch.setattr(settings, "HUGGINGFACE_API_TOKEN", "")
    monkeypatch.setattr(settings, "BHASHINI_API_KEY", "")
    monkeypatch.setattr(settings, "BHASHINI_USER_ID", "")
    service = get_language_service(provider="auto")
    assert isinstance(service, MockLanguageService)


# ---------- live endpoint (opt-in) ----------


@LIVE
@pytest.mark.asyncio
async def test_live_assamese_all_three():
    """Calls the real Sarvam API with an Assamese phrase for translate,
    text-to-speech, and speech-to-text, confirming real (non-mock) output.

    Live-probe verdict (2026-09-12): translate + STT accept as-IN; Bulbul TTS
    rejects as-IN with HTTP 400 ("request beta access"). The test asserts
    real translate/STT output and pins the TTS beta-gate as a real-API
    (non-mock) response instead of a success assertion.

    Skipped unless RUN_LIVE_SARVAM=1 and SARVAM_API_KEY are set.
    """
    service = SarvamLanguageService()  # key from settings/env
    phrase = "নমস্কাৰ, আজি ভাল আছে নে?"

    translated = await service.translate_text(phrase, "assamese", "english")
    assert isinstance(translated, str)
    assert translated.strip(), "empty translation returned"
    assert translated.strip() != phrase, "echoed input, not translated"
    assert "Translated to" not in translated, "mock output leaked into live test"
    print(f"\nLIVE Sarvam translate (as->en): {translated!r}")

    control_audio = await service.text_to_speech("হ্যালো, আজ কেমন আছো?", "bengali")
    assert len(base64.b64decode(control_audio)) > 100
    print(f"\nLIVE Sarvam TTS (bn control): {len(base64.b64decode(control_audio))} bytes")

    try:
        audio_b64 = await service.text_to_speech("নমস্কাৰ", "assamese")
    except LanguageServiceError as exc:
        # Real API verdict, not a mock: Bulbul gates as-IN behind beta access.
        assert exc.provider_status == 400, f"unexpected Assamese TTS failure: {exc}"
        assert "Translated to" not in str(exc)
        print(f"\nLIVE Sarvam TTS (as): beta-gated as probed: {exc.message[:120]!r}")
    else:
        assert len(base64.b64decode(audio_b64)) > 100
        print(f"\nLIVE Sarvam TTS (as): {len(base64.b64decode(audio_b64))} bytes")

    transcript = await service.speech_to_text(control_audio, "assamese")
    assert isinstance(transcript, str)
    assert transcript.strip(), "empty transcript returned"
    assert transcript.strip() != "I took my morning medicine and had a cup of tea."
    print(f"\nLIVE Sarvam STT (as-IN code): {transcript!r}")

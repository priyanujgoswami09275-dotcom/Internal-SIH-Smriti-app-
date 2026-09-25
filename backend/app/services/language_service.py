"""Bhashini Multi-lingual Speech & Translation Service.

Phase 8 — real Bhashini (ULCA) integration with a pluggable provider interface:

- `LanguageServiceProvider` — abstract ASR / TTS / NMT interface.
- `SarvamLanguageService` — Sarvam AI REST client (`api-subscription-key`
  auth; Sarvam-Translate for NMT, Saaras for ASR, Bulbul for TTS).
- `Ai4BharatLanguageService` — AI4Bharat models served via Hugging Face
  Inference API (IndicTrans2 for NMT, Indic Conformer for ASR,
  Indic Parler-TTS for speech synthesis).
- `BhashiniLanguageService` — real Government of India ULCA inference pipeline
  client (headers: `Authorization` = API key, `userID` = user id).
- `MockLanguageService` — deterministic local provider for tests/offline dev.
- `get_language_service()` — factory honouring `LANGUAGE_SERVICE_PROVIDER`:
  `auto`      -> sarvam when SARVAM_API_KEY is set, else ai4bharat when
                  HUGGINGFACE_API_TOKEN is set, else Bhashini when
                  credentials configured, otherwise Mock (logged)
  `sarvam`    -> always Sarvam (raises `LanguageServiceError` if unconfigured)
  `ai4bharat` -> always AI4Bharat (raises `LanguageServiceError` if unconfigured)
  `bhashini`  -> always Bhashini (raises `LanguageServiceError` if unconfigured)
  `mock`      -> always Mock

NER language codes (ISO 639): Assamese, Bengali, Hindi, English plus
config-only additions: Manipuri (mni), Bodo (brx), Nepali (ne), Mizo (lus),
Khasi (kha). No code changes needed to add more — extend `LANG_CODES`.
"""

import base64
import binascii
import logging
from abc import ABC, abstractmethod
from typing import Dict, List, Optional

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

# Bhashini pipeline language codes.
# "meitei" is the mobile display name for Manipuri — accepted everywhere as
# an alias of "manipuri" (canonical). Garo has no provider code on any
# backend and is hard-gated in the mobile picker; do not add it here until
# a provider actually covers it.
LANG_CODES: Dict[str, str] = {
    "assamese": "as",
    "bengali": "bn",
    "hindi": "hi",
    "english": "en",
    "manipuri": "mni",
    "meitei": "mni",
    "bodo": "brx",
    "nepali": "ne",
    "mizo": "lus",
    "khasi": "kha",
}

_PLACEHOLDER_KEYS = {"", "mock_key", "placeholder-key"}

# Sarvam AI language codes (BCP-47). Translate (Sarvam-Translate) and ASR
# (Saaras) cover all 23 listed languages incl. Assamese/Bodo/Manipuri.
# TTS (Bulbul) docs list only 11 (bn/en/gu/hi/kn/ml/mr/od/pa/ta/te) —
# Khasi and Mizo are NOT covered anywhere — see SarvamLanguageService._lang_code.
SARVAM_LANG_CODES: Dict[str, str] = {
    "assamese": "as-IN",
    "bengali": "bn-IN",
    "hindi": "hi-IN",
    "english": "en-IN",
    "manipuri": "mni-IN",
    "meitei": "mni-IN",  # alias of manipuri (mobile display name)
    "bodo": "brx-IN",
    "nepali": "ne-IN",
    "dogri": "doi-IN",
    "konkani": "kok-IN",
    "kashmiri": "ks-IN",
    "maithili": "mai-IN",
    "sanskrit": "sa-IN",
    "santali": "sat-IN",
    "sindhi": "sd-IN",
    "urdu": "ur-IN",
    "gujarati": "gu-IN",
    "kannada": "kn-IN",
    "malayalam": "ml-IN",
    "marathi": "mr-IN",
    "odia": "od-IN",
    "punjabi": "pa-IN",
    "tamil": "ta-IN",
    "telugu": "te-IN",
}

# Bulbul TTS covers only these base languages (Sarvam docs): bn/en/gu/hi/kn/
# ml/mr/od/pa/ta/te. TTS requests outside this subset (e.g. Assamese — the
# app default) must fail fast with UnsupportedLanguageError instead of a
# gateway error from the live API.
BULBUL_TTS_BASE_CODES = {"bn", "en", "gu", "hi", "kn", "ml", "mr", "od", "pa", "ta", "te"}
TTS_LANG_CODES: Dict[str, str] = {
    name: code for name, code in SARVAM_LANG_CODES.items()
    if code.split("-")[0] in BULBUL_TTS_BASE_CODES
}

# AI4Bharat models on the Hugging Face Inference API. Language subsets: these
# models cover Assamese, Bengali, Bodo, Manipuri, Nepali, Hindi, English.
# Khasi and Mizo are NOT covered — see Ai4BharatLanguageService._lang_code.
AI4BHARAT_LANG_CODES: Dict[str, str] = {
    "assamese": "asm_Beng",
    "bengali": "ben_Beng",
    "bodo": "brx_Deva",
    "manipuri": "mni_Mtei",
    "meitei": "mni_Mtei",  # alias of manipuri (mobile display name)
    "nepali": "npi_Deva",
    "hindi": "hin_Deng",
    "english": "eng_Latn",
}


class LanguageServiceError(Exception):
    """Raised when a language provider cannot complete a request."""

    def __init__(self, message: str, provider_status: Optional[int] = None):
        super().__init__(message)
        self.message = message
        self.provider_status = provider_status


class UnsupportedLanguageError(LanguageServiceError):
    """Raised when the active provider's models do not cover a language.

    Distinct from a generic provider failure so callers can surface a
    friendly "not yet available" message instead of an error (e.g. AI4Bharat
    models cover Khasi/Mizo nowhere — the frontend disables those options).
    """

    def __init__(self, message: str, language: str):
        super().__init__(message)
        self.language = language


class LanguageServiceProvider(ABC):
    """Abstract interface for speech and translation services."""

    name: str = "abstract"

    @abstractmethod
    async def speech_to_text(self, audio_base64: str, source_language: str) -> str:
        """Convert patient voice audio to recognized text."""

    @abstractmethod
    async def text_to_speech(self, text: str, target_language: str) -> str:
        """Synthesize text into spoken audio (base64 audio format)."""

    @abstractmethod
    async def translate_text(
        self, text: str, source_language: str, target_language: str
    ) -> str:
        """Translate text between NER languages and English for LLM reasoning."""

    def supported_languages(self) -> List[str]:
        return list(LANG_CODES.keys())

    def operation_capabilities(self) -> Dict[str, Dict[str, object]]:
        languages = self.supported_languages()
        return {
            operation: {
                "provider": self.name,
                "languages": languages,
                "simulated": self.name == "mock",
            }
            for operation in ("asr", "nmt", "tts")
        }


class BhashiniLanguageService(LanguageServiceProvider):
    """Real Government of India Bhashini (ULCA) inference pipeline client."""

    name = "bhashini"

    def __init__(
        self,
        api_key: Optional[str] = None,
        user_id: Optional[str] = None,
        endpoint: Optional[str] = None,
        transport: Optional[httpx.AsyncBaseTransport] = None,
    ):
        self.api_key = api_key if api_key is not None else settings.BHASHINI_API_KEY
        self.user_id = user_id if user_id is not None else settings.BHASHINI_USER_ID
        self.endpoint = endpoint or settings.BHASHINI_ENDPOINT
        self._transport = transport

        if not self.api_key or self.api_key.strip() in _PLACEHOLDER_KEYS:
            raise LanguageServiceError(
                "Bhashini API key not configured. Set BHASHINI_API_KEY."
            )
        if not self.user_id or not self.user_id.strip():
            raise LanguageServiceError(
                "Bhashini user id not configured. Set BHASHINI_USER_ID."
            )
        if not self.endpoint:
            raise LanguageServiceError("Bhashini endpoint not configured.")

    # ---------- internals ----------

    def _lang_code(self, language: str) -> str:
        code = LANG_CODES.get((language or "").lower())
        if not code:
            raise UnsupportedLanguageError(
                f"Unsupported language '{language}'. Supported: {sorted(LANG_CODES)}",
                language=language or "",
            )
        return code

    async def _post(self, payload: dict) -> dict:
        headers = {
            "Authorization": self.api_key,
            "userID": self.user_id,
            "Content-Type": "application/json",
        }
        try:
            async with httpx.AsyncClient(
                timeout=20.0, transport=self._transport
            ) as client:
                resp = await client.post(self.endpoint, json=payload, headers=headers)
        except httpx.HTTPError as exc:
            raise LanguageServiceError(f"Bhashini request failed: {exc}") from exc

        if resp.status_code != 200:
            raise LanguageServiceError(
                f"Bhashini API error (HTTP {resp.status_code}): {resp.text[:300]}",
                provider_status=resp.status_code,
            )
        try:
            return resp.json()
        except ValueError as exc:
            raise LanguageServiceError("Bhashini returned non-JSON response") from exc

    @staticmethod
    def _dig(data: dict, *path):
        """Walk nested ULCA response (dicts + list indexes); None if missing."""
        cur: object = data
        for key in path:
            if isinstance(cur, dict) and key in cur:
                cur = cur[key]
            elif isinstance(cur, list) and isinstance(key, int) and 0 <= key < len(cur):
                cur = cur[key]
            else:
                return None
        return cur

    # ---------- public API ----------

    async def speech_to_text(self, audio_base64: str, source_language: str) -> str:
        code = self._lang_code(source_language)
        payload = {
            "pipelineTasks": [
                {
                    "taskType": "asr",
                    "config": {
                        "language": {"sourceLanguage": code},
                        "audioFormat": "wav",
                        "samplingRate": 16000,
                    },
                }
            ],
            "inputData": {"audio": [{"audioContent": audio_base64}]},
        }
        data = await self._post(payload)
        text = self._dig(data, "pipelineResponse", 0, "output", 0, "source")
        if text is None:
            raise LanguageServiceError("Unexpected Bhashini ASR response shape")
        return text

    async def text_to_speech(self, text: str, target_language: str) -> str:
        code = self._lang_code(target_language)
        payload = {
            "pipelineTasks": [
                {
                    "taskType": "tts",
                    "config": {"language": {"sourceLanguage": code}, "gender": "female"},
                }
            ],
            "inputData": {"input": [{"source": text}]},
        }
        data = await self._post(payload)
        audio = self._dig(data, "pipelineResponse", 0, "audio", 0, "audioContent")
        if audio is None:
            raise LanguageServiceError("Unexpected Bhashini TTS response shape")
        return audio

    async def translate_text(
        self, text: str, source_language: str, target_language: str
    ) -> str:
        src_code = self._lang_code(source_language)
        tgt_code = self._lang_code(target_language)
        if src_code == tgt_code:
            return text
        payload = {
            "pipelineTasks": [
                {
                    "taskType": "translation",
                    "config": {
                        "language": {"sourceLanguage": src_code, "targetLanguage": tgt_code}
                    },
                }
            ],
            "inputData": {"input": [{"source": text}]},
        }
        data = await self._post(payload)
        translated = self._dig(data, "pipelineResponse", 0, "output", 0, "target")
        if translated is None:
            raise LanguageServiceError("Unexpected Bhashini translation response shape")
        return translated


class Ai4BharatLanguageService(LanguageServiceProvider):
    """AI4Bharat speech & translation models via the Hugging Face Inference API.

    Models:
      - NMT: ai4bharat/indictrans2-indic-indic-1B (IndicTrans2)
      - ASR: ai4bharat/indicconformer600m-multilingual (Indic Conformer)
      - TTS: ai4bharat/indic-parler-tts

    Auth: `Authorization: Bearer {HUGGINGFACE_API_TOKEN}` on every call; the
    token is read from settings, never hardcoded.

    Language coverage is narrower than Bhashini's — see `AI4BHARAT_LANG_CODES`.
    Khasi and Mizo raise `UnsupportedLanguageError` so the UI can show
    "not yet available" rather than a generic provider failure.
    """

    name = "ai4bharat"

    TRANSLATE_MODEL = "ai4bharat/indictrans2-indic-indic-1B"
    ASR_MODEL = "ai4bharat/indic-conformer-600m-multilingual"
    TTS_MODEL = "ai4bharat/indic-parler-tts"

    def __init__(
        self,
        api_token: Optional[str] = None,
        inference_base: Optional[str] = None,
        transport: Optional[httpx.AsyncBaseTransport] = None,
    ):
        self.api_token = (
            api_token if api_token is not None else settings.HUGGINGFACE_API_TOKEN
        )
        self.inference_base = (
            inference_base
            if inference_base is not None
            else settings.HUGGINGFACE_INFERENCE_BASE
        ).rstrip("/")
        self._transport = transport

        if not self.api_token or self.api_token.strip() in _PLACEHOLDER_KEYS:
            raise LanguageServiceError(
                "Hugging Face API token not configured. Set HUGGINGFACE_API_TOKEN."
            )
        if not self.inference_base:
            raise LanguageServiceError(
                "Hugging Face Inference base URL not configured."
            )

    # ---------- internals ----------

    def _lang_code(self, language: str) -> str:
        """Map a NER language to its AI4Bharat script tag.

        Raises UnsupportedLanguageError for languages the models do not cover
        (Khasi, Mizo, unknown codes) — callers render "not yet available".
        """
        code = AI4BHARAT_LANG_CODES.get((language or "").lower())
        if not code:
            raise UnsupportedLanguageError(
                f"Language '{language}' is not yet available on the AI4Bharat "
                f"models. Supported: {sorted(AI4BHARAT_LANG_CODES)}",
                language=language or "",
            )
        return code

    async def _request(self, model: str, *, json_body=None, content=None, headers=None) -> httpx.Response:
        """POST to the Inference API; return the raw response for the caller to interpret."""
        url = f"{self.inference_base}/models/{model}"
        merged_headers = {"Authorization": f"Bearer {self.api_token}"}
        if headers:
            merged_headers.update(headers)
        try:
            async with httpx.AsyncClient(
                timeout=60.0, transport=self._transport
            ) as client:
                resp = await client.post(
                    url, json=json_body, content=content, headers=merged_headers
                )
        except httpx.HTTPError as exc:
            raise LanguageServiceError(f"Hugging Face request failed: {exc}") from exc
        return resp

    def _json_or_error(self, resp: httpx.Response) -> dict:
        if resp.status_code in (200, 201):
            try:
                return resp.json()
            except ValueError as exc:
                raise LanguageServiceError(
                    "Hugging Face returned non-JSON response"
                ) from exc
        raise LanguageServiceError(
            f"Hugging Face API error (HTTP {resp.status_code}): {resp.text[:300]}",
            provider_status=resp.status_code,
        )

    # ---------- public API ----------

    def supported_languages(self) -> List[str]:
        """Only the languages the AI4Bharat models actually cover — the
        frontend uses this to mark Khasi/Mizo 'not yet available'."""
        return list(AI4BHARAT_LANG_CODES.keys())

    async def speech_to_text(self, audio_base64: str, source_language: str) -> str:
        """ASR via Indic Conformer. Base64-decoded audio is posted as binary body."""
        code = self._lang_code(source_language)
        try:
            audio_bytes = base64.b64decode(audio_base64)
        except (binascii.Error, ValueError) as exc:
            raise LanguageServiceError(f"Invalid base64 audio: {exc}") from exc
        resp = await self._request(
            self.ASR_MODEL,
            content=audio_bytes,
            headers={"Content-Type": "application/octet-stream"},
        )
        data = self._json_or_error(resp)
        text = data.get("text") if isinstance(data, dict) else None
        if text is None and isinstance(data, dict):
            # Some ASR endpoints return {"chunks": [{"text": ...}]}
            chunks = data.get("chunks") or []
            text = " ".join(
                c.get("text", "") for c in chunks if isinstance(c, dict)
            ).strip() or None
        if text is None:
            raise LanguageServiceError("Unexpected Hugging Face ASR response shape")
        return text

    async def text_to_speech(self, text: str, target_language: str, gender: str = "female") -> str:
        """TTS via Indic Parler-TTS; returns base64-encoded audio."""
        code = self._lang_code(target_language)
        payload = {
            "inputs": text,
            "parameters": {
                "lang": code,
                "gender": gender,
            },
        }
        resp = await self._request(self.TTS_MODEL, json_body=payload)
        content_type = resp.headers.get("content-type", "")
        if resp.status_code in (200, 201):
            if "audio" in content_type or "octet-stream" in content_type:
                return base64.b64encode(resp.content).decode()
            # Some deployments return a JSON blob describing the audio
            try:
                data = resp.json()
                if isinstance(data, dict) and data.get("audio_base64"):
                    return data["audio_base64"]
                if isinstance(data, dict) and data.get("audio"):
                    return data["audio"]
            except ValueError:
                pass
        raise LanguageServiceError(
            f"Hugging Face TTS error (HTTP {resp.status_code}): {resp.text[:300]}",
            provider_status= resp.status_code if resp.status_code not in (200, 201) else None,
        )

    async def translate_text(
        self, text: str, source_language: str, target_language: str
    ) -> str:
        """NMT via IndicTrans2; `inputs` carries the text, parameters carry script tags."""
        src_code = self._lang_code(source_language)
        tgt_code = self._lang_code(target_language)
        if src_code == tgt_code:
            return text
        payload = {
            "inputs": text,
            "parameters": {
                "src_lang": src_code,
                "tgt_lang": tgt_code,
            },
        }
        resp = await self._request(self.TRANSLATE_MODEL, json_body=payload)
        data = self._json_or_error(resp)
        result = None
        if isinstance(data, list) and data and isinstance(data[0], dict):
            result = (
                data[0].get("translation_text")
                or data[0].get("generated_text")
                or data[0].get("text")
            )
        elif isinstance(data, dict):
            result = (
                data.get("translation_text")
                or data.get("generated_text")
                or data.get("text")
            )
        result = result.strip() if isinstance(result, str) else None
        if result is None:
            raise LanguageServiceError(
                "Unexpected Hugging Face translation response shape"
            )
        return result


class SarvamLanguageService(LanguageServiceProvider):
    """Sarvam AI speech & translation via the api.sarvam.ai REST API.

    Endpoints:
      - NMT: POST /translate (Sarvam-Translate — full 23-language coverage
        incl. Assamese, Bodo, Manipuri).
      - ASR: POST /speech-to-text (multipart audio upload, Saaras model).
      - TTS: POST /text-to-speech (Bulbul model — response is JSON with
        base64-encoded audio in an `audios[]` array, NOT raw binary).

    Auth: `api-subscription-key: {SARVAM_API_KEY}` on every call; the key is
    read from settings, never hardcoded.

    Language coverage is narrower than translate for speech — Khasi and Mizo
    raise `UnsupportedLanguageError` so the UI can show "not yet available"
    rather than a generic provider failure.
    """

    name = "sarvam"

    TRANSLATE_MODEL = "sarvam-translate:v1"
    STT_MODEL = "saaras:v3"
    TTS_MODEL = "bulbul:v3"
    TTS_SPEAKER = "shubh"

    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: Optional[str] = None,
        transport: Optional[httpx.AsyncBaseTransport] = None,
    ):
        self.api_key = api_key if api_key is not None else settings.SARVAM_API_KEY
        self.base_url = (
            base_url if base_url is not None else settings.SARVAM_BASE_URL
        ).rstrip("/")
        self._transport = transport

        if not self.api_key or self.api_key.strip() in _PLACEHOLDER_KEYS:
            raise LanguageServiceError(
                "Sarvam API key not configured. Set SARVAM_API_KEY."
            )
        if not self.base_url:
            raise LanguageServiceError("Sarvam base URL not configured.")

    # ---------- internals ----------

    def _lang_code(self, language: str) -> str:
        """Map a NER language to its Sarvam BCP-47 tag.

        Raises UnsupportedLanguageError for languages Sarvam does not cover
        (Khasi, Mizo, unknown codes) — callers render "not yet available".
        """
        code = SARVAM_LANG_CODES.get((language or "").lower())
        if not code:
            raise UnsupportedLanguageError(
                f"Language '{language}' is not yet available on Sarvam. "
                f"Supported: {sorted(SARVAM_LANG_CODES)}",
                language=language or "",
            )
        return code

    def _tts_lang_code(self, language: str) -> str:
        """Map a language to its Bulbul TTS tag — restricted to the languages
        Bulbul actually synthesizes. Raises UnsupportedLanguageError for
        NMT/ASR-only languages (e.g. Assamese) so the UI shows an honest
        "not yet available" instead of a gateway error."""
        code = TTS_LANG_CODES.get((language or "").lower())
        if not code:
            raise UnsupportedLanguageError(
                f"Text-to-speech for '{language}' is not yet available. "
                f"TTS-supported: {sorted(TTS_LANG_CODES)}",
                language=language or "",
            )
        return code

    def _headers(self) -> dict:
        return {"api-subscription-key": self.api_key}

    def _json_or_error(self, resp: httpx.Response, service: str) -> dict:
        if resp.status_code in (200, 201):
            try:
                data = resp.json()
            except ValueError as exc:
                raise LanguageServiceError(
                    f"Sarvam {service} returned non-JSON response"
                ) from exc
            if isinstance(data, dict):
                return data
            raise LanguageServiceError(
                f"Unexpected Sarvam {service} response shape"
            )
        raise LanguageServiceError(
            f"Sarvam {service} error (HTTP {resp.status_code}): {resp.text[:300]}",
            provider_status=resp.status_code,
        )

    # ---------- public API ----------

    def supported_languages(self) -> List[str]:
        """Languages with Sarvam BCP-47 tags — Khasi/Mizo excluded so the
        frontend can mark them 'not yet available'."""
        return list(SARVAM_LANG_CODES.keys())

    def operation_capabilities(self) -> Dict[str, Dict[str, object]]:
        languages = self.supported_languages()
        tts_languages = list(TTS_LANG_CODES.keys())
        return {
            "asr": {
                "provider": self.name,
                "languages": languages,
                "simulated": False,
            },
            "nmt": {
                "provider": self.name,
                "languages": languages,
                "simulated": False,
            },
            "tts": {
                "provider": self.name,
                "languages": tts_languages,
                "simulated": False,
            },
        }

    async def translate_text(
        self, text: str, source_language: str, target_language: str
    ) -> str:
        """NMT via Sarvam-Translate; same-language input short-circuits."""
        src_code = self._lang_code(source_language)
        tgt_code = self._lang_code(target_language)
        if src_code == tgt_code:
            return text
        payload = {
            "input": text,
            "source_language_code": src_code,
            "target_language_code": tgt_code,
            "model": self.TRANSLATE_MODEL,
        }
        try:
            async with httpx.AsyncClient(
                timeout=30.0, transport=self._transport
            ) as client:
                resp = await client.post(
                    f"{self.base_url}/translate",
                    json=payload,
                    headers={**self._headers(), "Content-Type": "application/json"},
                )
        except httpx.HTTPError as exc:
            raise LanguageServiceError(f"Sarvam request failed: {exc}") from exc
        data = self._json_or_error(resp, "translation")
        translated = data.get("translated_text")
        translated = translated.strip() if isinstance(translated, str) else None
        if not translated:
            raise LanguageServiceError(
                "Unexpected Sarvam translation response shape"
            )
        return translated

    async def speech_to_text(self, audio_base64: str, source_language: str) -> str:
        """ASR via Saaras. Base64-decoded audio is uploaded as multipart `file`."""
        code = self._lang_code(source_language)
        try:
            audio_bytes = base64.b64decode(audio_base64)
        except (binascii.Error, ValueError) as exc:
            raise LanguageServiceError(f"Invalid base64 audio: {exc}") from exc
        try:
            async with httpx.AsyncClient(
                timeout=60.0, transport=self._transport
            ) as client:
                resp = await client.post(
                    f"{self.base_url}/speech-to-text",
                    files={"file": ("audio.wav", audio_bytes, "audio/wav")},
                    data={"language_code": code, "model": self.STT_MODEL},
                    headers=self._headers(),
                )
        except httpx.HTTPError as exc:
            raise LanguageServiceError(f"Sarvam request failed: {exc}") from exc
        data = self._json_or_error(resp, "transcription")
        transcript = data.get("transcript")
        transcript = transcript.strip() if isinstance(transcript, str) else None
        if not transcript:
            raise LanguageServiceError(
                "Unexpected Sarvam transcription response shape"
            )
        return transcript

    async def text_to_speech(self, text: str, target_language: str) -> str:
        """TTS via Bulbul; returns the base64 audio from `audios[0]` as-is
        (the interface contract is already base64 audio). Validated against
        the Bulbul-covered language subset, not the full NMT list."""
        code = self._tts_lang_code(target_language)
        payload = {
            "text": text,
            "language_code": code,
            "model": self.TTS_MODEL,
            "speaker": self.TTS_SPEAKER,
        }
        try:
            async with httpx.AsyncClient(
                timeout=60.0, transport=self._transport
            ) as client:
                resp = await client.post(
                    f"{self.base_url}/text-to-speech",
                    json=payload,
                    headers={**self._headers(), "Content-Type": "application/json"},
                )
        except httpx.HTTPError as exc:
            raise LanguageServiceError(f"Sarvam request failed: {exc}") from exc
        data = self._json_or_error(resp, "speech synthesis")
        audios = data.get("audios")
        audio = audios[0] if isinstance(audios, list) and audios else None
        if not isinstance(audio, str) or not audio:
            raise LanguageServiceError(
                "Unexpected Sarvam TTS response shape (missing audios[])"
            )
        try:
            base64.b64decode(audio)
        except (binascii.Error, ValueError) as exc:
            raise LanguageServiceError(
                f"Sarvam TTS returned invalid base64 audio: {exc}"
            ) from exc
        return audio


class MockLanguageService(LanguageServiceProvider):
    """Deterministic local language provider for testing and offline development."""

    name = "mock"

    async def speech_to_text(self, audio_base64: str, source_language: str) -> str:
        return "I took my morning medicine and had a cup of tea."

    async def text_to_speech(self, text: str, target_language: str) -> str:
        return "UklGRjIAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="

    async def translate_text(
        self, text: str, source_language: str, target_language: str
    ) -> str:
        return f"Translated to {target_language}: {text}"


def get_language_service(
    provider: Optional[str] = None,
    transport: Optional[httpx.AsyncBaseTransport] = None,
) -> LanguageServiceProvider:
    """Dependency injector for speech and language service.

    `provider` overrides `settings.LANGUAGE_SERVICE_PROVIDER`
    (auto | sarvam | ai4bharat | bhashini | mock).
    """
    choice = (provider or settings.LANGUAGE_SERVICE_PROVIDER or "auto").lower()

    if choice == "mock":
        return MockLanguageService()
    if choice == "sarvam":
        return SarvamLanguageService(transport=transport)
    if choice == "ai4bharat":
        return Ai4BharatLanguageService(transport=transport)
    if choice == "bhashini":
        return BhashiniLanguageService(transport=transport)

    # auto: same graceful-degradation chain as the embedding provider —
    # sarvam first (SARVAM_API_KEY set), then ai4bharat (Hugging Face token
    # set), then bhashini (ULCA creds set), then the deterministic mock.
    sarvam_configured = bool(settings.SARVAM_API_KEY) and (
        settings.SARVAM_API_KEY.strip() not in _PLACEHOLDER_KEYS
    )
    if sarvam_configured:
        return SarvamLanguageService(transport=transport)
    hf_configured = bool(settings.HUGGINGFACE_API_TOKEN) and (
        settings.HUGGINGFACE_API_TOKEN.strip() not in _PLACEHOLDER_KEYS
    )
    if hf_configured:
        return Ai4BharatLanguageService(transport=transport)
    bhashini_configured = bool(settings.BHASHINI_API_KEY) and (
        settings.BHASHINI_API_KEY.strip() not in _PLACEHOLDER_KEYS
    )
    if bhashini_configured and settings.BHASHINI_USER_ID:
        return BhashiniLanguageService(transport=transport)
    logger.warning(
        "No language provider configured — using MockLanguageService. "
        "Set SARVAM_API_KEY, HUGGINGFACE_API_TOKEN (AI4Bharat) or "
        "BHASHINI_API_KEY + BHASHINI_USER_ID to enable real ASR/TTS/NMT."
    )
    return MockLanguageService()

from pydantic_settings import BaseSettings
from pathlib import Path
from typing import List

# The canonical .env lives at the repo root. Resolve it absolutely so the
# backend picks it up no matter which directory it is launched from (repo root,
# backend/, or a test runner). In Docker the file may be absent — that is fine,
# compose passes the same values as real environment variables, which take
# precedence over any .env file anyway.
_ROOT_ENV = Path(__file__).resolve().parents[2] / ".env"
_LOCAL_ENV = Path(__file__).resolve().parents[1] / ".env"  # optional backend/.env override

_PLACEHOLDER_SECRETS = {
    "your-secret-key-change-in-production",
    "CHANGE_ME_IN_PRODUCTION",
    "CHANGE_ME_32_BYTE_KEY_HERE",
    "your-encryption-key-change-in-production",
}


class Settings(BaseSettings):
    PROJECT_NAME: str = "Elder-Care Cognitive Companion"
    PROJECT_VERSION: str = "0.1.0"
    API_V1_STR: str = "/api/v1"

    # Database
    DATABASE_URL: str = "postgresql+psycopg://user:password@localhost:5432/elder_care"

    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

    # Auth
    SECRET_KEY: str = "your-secret-key-change-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Multilingual
    LANGUAGE_SET: List[str] = [
        "assamese", "bengali", "hindi", "english",
        "mizo", "manipuri", "khasi", "bodo", "garo", "nepali",
    ]
    DEFAULT_LANGUAGE: str = "english"

    # Compliance
    ENCRYPTION_KEY: str = "your-encryption-key-change-in-production"

    # --- Bhashini (speech: ASR / TTS / NMT) ---
    # Provider selection: "auto" (ai4bharat -> bhashini -> mock by configured
    # creds), "ai4bharat", "bhashini" (always real — errors when creds missing),
    # "mock" (deterministic local).
    LANGUAGE_SERVICE_PROVIDER: str = "auto"
    BHASHINI_API_KEY: str = ""
    BHASHINI_USER_ID: str = ""
    # ULCA inference pipeline endpoint
    BHASHINI_ENDPOINT: str = "https://dhruva-api.bhashini.gov.in/services/inference/pipeline"

    # --- AI4Bharat via Hugging Face Inference API (alternate ASR / TTS / NMT) ---
    # Supported languages: assamese, bengali, bodo, manipuri, nepali, hindi,
    # english. Khasi and Mizo are NOT supported by these models — requests
    # raise UnsupportedLanguageError (surfaced as "not yet available" upstream).
    #
    # NOTE: the legacy api-inference.huggingface.co host was retired; the
    # default points at the Inference Providers router. The AI4Bharat models
    # are not currently served by the serverless platform — override this base
    # with a dedicated Inference Endpoint URL to run them.
    HUGGINGFACE_API_TOKEN: str = ""
    HUGGINGFACE_INFERENCE_BASE: str = "https://router.huggingface.co/hf-inference"

    # --- Sarvam AI (alternate ASR / TTS / NMT; 23-language translate coverage) ---
    # translate: Sarvam-Translate model (full NER coverage incl. Assamese/Bodo/Manipuri).
    # ASR (Saaras) and TTS (Bulbul) speech model language coverage is narrower —
    # per-language support must be verified against the live API. Auth uses the
    # `api-subscription-key` header (not Bearer).
    SARVAM_API_KEY: str = ""
    SARVAM_BASE_URL: str = "https://api.sarvam.ai"

    # --- LLM (voice companion + clinical answer synthesis) ---
    # Provider: auto | openrouter | anthropic. `auto` infers from the key prefix
    # (`sk-or-` => openrouter). OpenRouter is the project default.
    LLM_PROVIDER: str = "auto"
    LLM_MAX_TOKENS: int = 300
    LLM_TIMEOUT_SECONDS: float = 45.0
    # When true (default), companion chat falls back to a warm canned reply if no
    # API key is configured or the upstream call fails; never crashes the elder UX.
    LLM_AUTO_FALLBACK: bool = True

    # --- OpenRouter (default provider; free tier only) ---
    OPENROUTER_API_KEY: str = ""
    OPENROUTER_BASE_URL: str = "https://openrouter.ai/api/v1"
    # Free-tier models are individually unreliable (provider errors, or HTTP 200
    # with null content). The client walks this chain until one answers.
    # Verified 2026-09-05: minimax-m3 returns clean Assamese + honours citation
    # instructions; nemotron-ultra works but is weaker; *-lightning leaks its
    # chain-of-thought, so it is deliberately NOT in the chain.
    OPENROUTER_MODEL: str = "minimax/minimax-m3:free"
    OPENROUTER_FALLBACK_MODELS: str = (
        "nvidia/nemotron-3-ultra-550b-a55b:free,nvidia/nemotron-3-super-120b-a12b:free"
    )
    # Hard guard: refuse any model slug that is not ':free'. Keeps a typo from
    # spending money on a paid model.
    OPENROUTER_FREE_ONLY: bool = True
    OPENROUTER_APP_URL: str = "https://github.com/sih26003/eldercare"
    OPENROUTER_APP_TITLE: str = "Elder-Care Cognitive Companion (SIH26003)"

    # --- Anthropic Claude (alternative provider; unused when OpenRouter is set) ---
    ANTHROPIC_API_KEY: str = ""          # also honoured via CLAUDE_API_KEY
    ANTHROPIC_VERSION: str = "2023-06-01"
    CLAUDE_MODEL: str = "claude-3-haiku-20240307"
    CLAUDE_MAX_TOKENS: int = 300

    # --- Embeddings (RAG). Provider: heuristic | local | openai ---
    # heuristic: deterministic md5-TF hashing, no dependencies, always available.
    # local:     sentence-transformers (needs `pip install sentence-transformers`
    #            + a one-time model download). openai: hosted embeddings API.
    # Missing backends degrade gracefully to heuristic with a warning.
    EMBEDDING_PROVIDER: str = "heuristic"
    EMBEDDING_MODEL: str = "intfloat/multilingual-e5-small"  # local/openai backend model id
    EMBEDDING_DIMENSIONS: int = 1536  # heuristic vector width (deterministic)

    # --- Notifications (reminder escalation / alert fan-out).
    # Provider: console | (future: sms, fcm, email). console logs + records
    # deliveries in-process — the local mock until a real channel is configured.
    NOTIFICATION_PROVIDER: str = "console"

    # --- Reminder engine (Phase 1 roadmap). The generation job materializes a
    # PENDING ReminderEvent for each schedule's due time; escalation then walks
    # PENDING -> ESCALATED (reprompt) -> MISSED. Cadence times are wall-clock in
    # REMINDER_TIMEZONE (NER is IST). ---
    REMINDER_TIMEZONE: str = "Asia/Kolkata"
    REMINDER_ESCALATE_MINUTES: int = 10   # unacknowledged -> secondary notification
    REMINDER_MISSED_MINUTES: int = 60     # still unacknowledged after this -> MISSED
    REMINDER_GENERATION_SECONDS: int = 60  # background generation cadence

    # Phase 12 — production posture. ENVIRONMENT=production refuses placeholder
    # secrets and wildcard CORS. Rate limiting is on in production even if the
    # explicit flag is left at its development default.
    ENVIRONMENT: str = "development"
    CORS_ORIGINS: str = "*"
    RATE_LIMIT_ENABLED: bool = False
    RATE_LIMIT_PER_MINUTE: int = 100
    ENABLE_BACKGROUND_JOBS: bool = True

    class Config:
        # Load repo-root .env, then an optional backend/.env override.
        env_file = (str(_ROOT_ENV), str(_LOCAL_ENV))
        case_sensitive = True
        extra = "ignore"

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT.lower() == "production"

    @property
    def cors_origin_list(self) -> List[str]:
        raw = (self.CORS_ORIGINS or "*").strip()
        if raw == "*":
            return ["*"]
        return [part.strip() for part in raw.split(",") if part.strip()]

    @property
    def rate_limit_enabled(self) -> bool:
        if self.is_production:
            return True
        return self.RATE_LIMIT_ENABLED

    @property
    def background_jobs_enabled(self) -> bool:
        if self.ENVIRONMENT.lower() == "test":
            return False
        return self.ENABLE_BACKGROUND_JOBS

    def validate_for_environment(self) -> None:
        """Refuse to boot a production process with placeholder secrets or open CORS."""
        if not self.is_production:
            return
        if self.SECRET_KEY in _PLACEHOLDER_SECRETS or len(self.SECRET_KEY) < 24:
            raise RuntimeError("Refusing to start: set a strong SECRET_KEY for production")
        if self.ENCRYPTION_KEY in _PLACEHOLDER_SECRETS or len(self.ENCRYPTION_KEY) < 16:
            raise RuntimeError("Refusing to start: set ENCRYPTION_KEY for production")
        if self.cors_origin_list == ["*"]:
            raise RuntimeError("Refusing to start: CORS_ORIGINS must be a whitelist in production")


settings = Settings()

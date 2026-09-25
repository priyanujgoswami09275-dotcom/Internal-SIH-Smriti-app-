# ARCHITECTURE.md — Smriti Technical Architecture

**Technical Architecture Summary** · Reconciled: 2026-09-25

---

## 1. System Overview

Three user-facing surfaces share one FastAPI backend:

```
┌─────────────────────────┐
│   Patient Mobile App      │  Flutter | Offline-capable
│  (Games, Voice, Reminders)│
└───────────┬──────────────┘
             │ drift SQLite outbox + local caches
             ▼
┌─────────────────────────┐
│   FastAPI Backend         │  Python | PostgreSQL
│  (JWT/RBAC, consent, RAG,  │
│   scoring, compliance)     │
└───────────┬──────────────┘
             │ REST API only; no direct client table access
             ▼
┌─────────────────────────┐
│ Caregiver Dashboard      │  Flutter Web + mobile port
│ (Trends, alerts, logs)     │
└─────────────────────────┘
```

**REST API** (`/api/v1`) connects all surfaces. Mobile/dashboard use JWT bearer
requests; neither embeds a Supabase/Firebase table SDK or privileged database
credential.

**Offline durability:** bundled/generated boards where available, cached level
configuration and public Odd-One-Out board snapshots, a drift-backed replay
outbox scoped to the active account, and scheduled local reminder notifications.
An in-progress game round is memory-only and is not resumed after app death.

**Background jobs:** reminder generation (60s), escalation scan (60s), sync consume (300s), retention (24h).

---

## 2. Component Breakdown

### Backend
- **Language:** Python 3.12 (pinned runtime)
- **Framework:** FastAPI (async-first, Pydantic validation, OpenAPI docs)
- **ORM:** SQLAlchemy 2.0 + Alembic; current single head `0014_reminder_idempotency`
- **Database:** PostgreSQL 16. The compose image includes pgvector, but current RAG vectors use a JSON column and Python cosine scoring rather than a pgvector index.
- **Cache/rate limit:** Redis with in-process fallback
- **Key files:**
  - `app/models/all_models.py` (15 tables: user, compliance, patient, game, reminder, alert, sync, symptom, medical document/chunk, voice_companion_config)
  - `app/services/` (20+ services: auth, compliance, dashboard, game, difficulty_engine, adaptive_shadow, adaptive_training, adaptive_features, content_packs, reminder, routine, sync, notification, language, llm_client, rag, embedding_provider, document_extraction, report, retention, risk_screening, voice_companion, odd_one_out_service)
  - `app/routes/` (auth, patients, games, reminders, compliance, dashboard, language, voice_companion, reports, sync)
  - `app/middleware/rate_limit.py` (Redis-backed with in-process fallback)
  - `app/deps.py` (auth deps, patient-access gates, consent gates, permission tiers)
  - `app/jobs.py` (background job loop)
  - `app/config.py` (Settings, provider keys, validation)
  - `main.py` (app factory, middleware wiring, lifespan)

### Mobile (Patient App)
- **Framework:** Flutter/Dart for Android/iOS
- **Local store:** drift SQLite + committed codegen. The sync outbox is durable and account-scoped; pending items remain across logout/restart and only the active account is replayed.
- **Caches:** server level configuration and public Odd-One-Out board snapshots in `SharedPreferences`; synthesized reminder audio in a temporary text+language keyed cache.
- **Non-durable state:** the active board, moves, timers, and action buffer are widget memory. App death starts a new local/cached round; no exact in-progress resume exists.
- **Key files:**
  - `mobile/lib/main.dart` — auth gate, home shell, profile setup, role routing
  - `mobile/lib/services/` — REST/auth, outbox sync, local reminders/TTS cache, language capability gating
  - `mobile/lib/games/game_analytics_engine.dart` — pure-Dart local metrics/tags/hints; it does not apply difficulty
  - `mobile/lib/games/level_config.dart` — server config cache with bundled fallback
  - `mobile/lib/screens/` — four games, reminders, voice, documents/RAG, caregiver sections, audit viewer, profile/risk flows
  - `mobile/test/` — pure logic, widget, sync-integrity, role/consent, and upload contract tests

**Adaptive flow:** the backend scores durable action rows, evaluates its rule
strategy, and returns `recommended_level`; the client applies that value for the
next online round. Offline completion remains pending server scoring. Shadow ML
metadata is display/logging only.

### Caregiver Dashboard
- **Framework:** Flutter Web plus a role-routed mobile caregiver port; they share the API contract and design tokens, not a Dart model package.
- **Structure:** `dashboard/lib/main.dart` (shell, API client, views), `dashboard/lib/config.dart` (release URL guard), focused risk/RAG widgets, and the Monad theme.
- **Authorization UX:** login/refresh role and each patient's server permission tier drive visible metric/trend/risk/document controls. A `health_data` consent preflight gates screening/upload. Hiding a control is never the security boundary; backend role, link, consent, and tier checks remain authoritative.
- **Features:** roster, honest metric tiles, 14-day all-game trends, alert acknowledgement, clinical insight, risk screening, reminder schedule add/remove, RAG upload, and admin-only audit pagination (50 rows per offset page).
- **Configuration:** `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000` for development. `flutter build web --release --dart-define=API_BASE_URL=https://api.example.org` is required for release because an empty URL fails configuration.

---

## 3. External Integrations Table

| Integration | Provider chain | Graceful-degradation behavior |
|---|---|---|
| **LLM** (companion + RAG answers) | OpenRouter default; Anthropic alternative; `auto` selects from configured key | Canned persona reply or extractive RAG answer |
| **Speech** (ASR/NMT/TTS) | `auto`: Sarvam → AI4Bharat → Bhashini → mock | With no shipped provider credentials, deterministic simulated operations; status response marks them simulated |
| **Embeddings** | `heuristic` default; `local` sentence-transformers; `openai` | Missing/unknown configured backend warns and uses heuristic |
| **Notifications** | `console`; current `fcm` class logs/failed-audits but sends nothing | `delivery_state: not_configured`, zero confirmed deliveries |

NER-relevant speech coverage is operation-specific:

| Provider | ASR/NMT languages | TTS languages | Reality |
|---|---|---|---|
| Sarvam | Assamese, Bengali, Hindi, English, Manipuri/Meitei, Bodo, Nepali | Bengali, Hindi, English | Requires `SARVAM_API_KEY`; Khasi/Mizo/Garo unsupported |
| AI4Bharat | Assamese, Bengali, Bodo, Manipuri/Meitei, Nepali, Hindi, English | Same seven | Client implemented; default HF router lacks these models, so a dedicated endpoint is required |
| Bhashini | Assamese, Bengali, Hindi, English, Manipuri/Meitei, Bodo, Nepali, Mizo, Khasi | Same nine | Requires API key + user ID; Garo unsupported |
| Mock | Picker languages, simulated | Picker languages, simulated | Default; not live speech |

**Hard guard:** `OPENROUTER_FREE_ONLY=true` refuses any model slug not `:free`.
No provider secret is needed for CI; live calls remain operator-configured.

---

## 4. Security & Compliance Architecture

| Component | Implementation | Evidence |
|---|---|---|
| **JWT with refresh rotation** | Access: 15 min; refresh: 7 days, single-use with `users.refresh_jti`; replay/superseded refresh clears the chain | `app/core/security.py`, `app/deps.py`, migration `0003_refresh_rotation` |
| **App-layer RBAC/consent** | JWT resolves the user; patient owner/link/staff access, purpose scope, and `basic`/`clinical` tier checks run in FastAPI dependencies | `app/deps.py`, access/consent suites |
| **API-only client access** | Mobile/dashboard call REST with bearer tokens; no Supabase/Firebase table SDK, anon table credential, or service-role key is present | Flutter `http` clients; dependency manifests |
| **Audit logging** | Broad read plus representative write rows. Most read/write helpers are best-effort; consent changes, document ingest/reindex, and export are fail-closed. Retention excludes rows, but there are no DB immutability controls. | `app/services/compliance_service.py`, audit failure/matrix suites |
| **At-rest encryption** | Fernet protects `SymptomLog.notes`, `MedicalDocument.extracted_text`, and new `DocumentChunk.chunk_text`; plaintext is transient in memory | `app/services/compliance_service.py`, RAG integrity tests |
| **No implicit access** | Unauthorized cross-patient access is rejected; unknown IDs return 404. Covered successful paths create audit rows under the mixed policy above. | access-gate and audit suites |
| **Production posture** | Rate limiting, production CORS/secret refusal, clean-PG migration smoke, frontend build/test gates | config/middleware/workflow |

### RAG provenance, encryption, and migration

Every new document stores provider/model/dimension provenance. Retrieval rejects
missing or mismatched provenance instead of mixing vector spaces. Patient-scoped
maintenance is:

```sh
cd backend && python -m app.services.rag_service reindex \
  --patient-id <patient-uuid> --actor-id <operator-user-uuid>
```

Changed documents are re-embedded, legacy plaintext chunks are rewritten as
Fernet ciphertext, and a `rag_reindex` write row is committed. This is the
implemented plaintext-PHI migration path for chunk rows; arbitrary legacy
plaintext source text still requires a controlled re-ingest/backfill. OCR is not
part of this build, so scanned/image-only PDFs are rejected before persistence.

### Audit and API boundaries

Audit rows are append-oriented application records with actor, action, resource,
time, IP, and details. They are not database-immutable: no trigger, restricted
DB grant, RLS, or update/delete denial policy prevents a privileged SQL actor
from changing them. Database-level append-only controls remain operator/infrastructure
work.

If direct client database access is ever introduced, it needs a new threat model,
publishable-only credentials, table/action RLS, JWT claim propagation,
tenant/patient/consent scoping, revocation/session behavior, migrations and
integration tests, plus proof that no service-role secret reaches a client. The
current clients have none of that access.

**CI verification:** backend pytest + standalone checks, `alembic upgrade head`
on a clean PostgreSQL 16 service, and live `smoke_e2e.py`; mobile deps/codegen/
analyze/unit tests; dashboard deps/analyze/VM tests, Chrome-platform tests, and
an explicit-URL release web build.

---

## 5. ML Architecture — Two Independent Systems

The two systems are **independent**: the risk-screening model is callable but experimental/not clinically validated; the difficulty ML model is shadow-only. Real game level changes come from the server's deterministic rule strategy and its returned `recommended_level`, never from the client calculator or shadow probability.

### Risk-Screening Model (Phase A)
- **Purpose:** Experimental preliminary screening for cognitive decline indicators (not diagnosis)
- **Data:** Symptom checklist (age, education, memory, orientation, judgment, community affairs, home/hobbies, personal care) — **not** gameplay data
- **Architecture:** Logistic regression (seed-42 bootstrap, synthetic patient data for prototyping)
- **Isolation:** Zero gameplay data used; separate consent scope (`health_data`); persistence via `RiskScreening` table (one row per patient, upsert on screen)
- **Validation:** Unit-tested (`test_risk_screening.py`); persistence verified; audit-logged on access
- **Status:** Built + tested, fully functional — experimental and not clinically validated as a screening tool; **not a medical device**
- **Endpoint:** `POST /patients/{id}/risk-screening` (caregiver/staff + `health_data` consent required)
- **Key constraint:** **Binding decision — independent from gameplay.** The model's output never influences game difficulty or any other gameplay element.

### Adaptive Difficulty Model (Phase B-01 — Shadow Only)
- **Purpose:** Research prototype for predicting success probability (not for real decisions)
- **Data:** Gameplay features: accuracy %, session duration, response time, weakness flag, level — extracted from last 3 sessions per patient per game type
- **Architecture:** Logistic regression (seed-42 bootstrap on 100 synthetic patients / 1,200 rows; held-out accuracy 87.9%, ROC-AUC 0.895)
- **Isolation:** Logs predictions but **never used for real decisions** — applied source is always `rule_fallback` (the existing 85/50 rules)
- **Validation:** Unit-tested; bootstrap CLI rerun exit 0; shadow probability rides in nullable shadow_* columns; rules remain sole authority
- **Status:** Built + tested, **shadow mode only** — every returned level comes from the 85/50 rules; shadow probability is separate nullable field for logging only
- **Endpoint:** Lives inside `evaluate_difficulty` (shadow call nullable fields); rules engine unaffected
- **Key constraint:** **Binding decision — independent from gameplay.** The model is explicitly barred from affecting real decisions; difficulty source is always `rule_fallback`.

**Architectural honesty:** Both models are research prototypes. Neither is activated for production decisions without explicit approval. The system is designed so that even if ML models fail or return invalid data, gameplay continues via the rule-based authority.

---

## 6. Known Architectural Limitations

| Limitation | Impact | Status |
|---|---|---|
| **Client calculator is not difficulty authority** | `game_analytics_engine.dart` computes local metrics/tags/hints and has its own streak helper, but online next-level state comes only from server `recommended_level`; offline completion remains pending. | **Reconciled** — do not describe two engines making live difficulty decisions. |
| **No physical-device validation for voice/notifications** | Microphone, speaker, permission, and notification behavior have not been confirmed on a physical phone. The shipped default provider is simulated unless credentials are configured. | **Open** — device checklist in `DEPLOYMENT.md`; opt-in live provider tests need secrets. |
| **No OCR in the document build** | Image-only PDFs have no selectable text and are rejected; users must paste text or upload a text-layer PDF. | **By scope** — scanner + OCR needs separate approval and native dependencies. |
| **No exact active-round resume** | In-progress board/move/timer state is widget memory; app death restarts from bundled or cached data. | **Open product choice** — only completed outbox work is durable. |
| **Audit rows are not database-immutable** | Application retention excludes audit rows, but privileged SQL can still update/delete them. | **Open deployment control** — add DB role/trigger/RLS/storage controls if tamper resistance is required. |
| **Notification delivery unconfirmed** | Current FCM adapter logs/audits failures and returns `not_configured`; it does not deliver. | **Open** — real transport and device validation required. |
| **Level-3 Odd-One-Out content is festivals-pack-only** | Festivals is the sole content group with ≥5 unambiguous items, so L3 majority boards always draw from it (L1/L2 span five groups). Boards remain valid and fully scored; broader content authoring is pending. | **Open** — content task, not a code change. |
| **ML models not activated** | Risk-screening model is experimental/not clinically validated; difficulty model is shadow-mode only. Neither is used for real decisions without explicit approval. | **By design** — requires separate approval for activation. |

These limitations are explicit and scoped. The current build provides tested
game, reminder, API/RBAC, RAG, and caregiver-dashboard paths; it does not claim
live default speech, confirmed push delivery, OCR, exact active-round resume,
clinical efficacy, or database-immutable audit storage.
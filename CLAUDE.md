# Architecture & Decisions — Elder-Care Cognitive Companion Platform

## Project Overview
**SIH26003** — Production-grade AI platform for elderly cognitive health in India's North Eastern Region (NER). Two user-facing surfaces (patient mobile app, caregiver dashboard) sharing one backend. Built for Smart India Hackathon 2026, architected for production: proper layering, migrations, tests, error handling, security/privacy built in from day 1.

---

## Implementation Status (Reconciled 2026-09-06)

The actual repo state is now the phase docs' own source of truth — all 12 roadmap
phases are implemented and tested. Tracker/detail docs that were written *before*
Phases 11–12 landed (`PHASE_1_STATUS.md`, `DEPLOYMENT.md`,
`docs/superpowers/plans/2026-09-05-remaining-roadmap-to-mvp.md`) are stale on
those points; treat the code and this file as authoritative.

| Phase | Scope | Status | Evidence |
|---|---|---|---|
| 1–7 | Backend scaffold, 15 data models, auth/RBAC, games engine, reminders + escalation, dashboard analytics, sync & patient endpoints | ✅ Implemented + tested | Migrations `0001_initial_schema` → `0003_refresh_rotation`; all models/services/routes; gate tests |
| 8 | Real Bhashini (ULCA) speech provider | ✅ Implemented | `language_service.py`; config-driven (`auto\|bhashini\|mock`); live call requires API keys |
| 9 | Voice companion (LLM) | ✅ Implemented | `llm_client.py` (OpenRouter default / Anthropic alt), DB-versioned prompts, auth + config endpoints, canned-reply fallback |
| 10 | RAG pipeline for medical documents | ✅ Implemented | chunking + stable embeddings + cited answers; PDF/text file upload; extractive fallback without LLM keys |
| 11 | Compliance enforcement | ✅ Implemented + tested | consent-scope gates, no-implicit-access, read-audit, Fernet at-rest encryption, data export, retention/deletion jobs |
| 12 | Production hardening | ✅ Implemented | rate limiting (Redis+fallback), CORS whitelist, placeholder-secret refusal, CI, E2E smoke vs real Postgres |
| — | Flutter UIs wired to backend (mobile + caregiver dashboard) | ✅ Compiled in CI | `flutter pub get` + `build_runner` + `flutter analyze` green in `.github/workflows/ci.yml` |
| — | Offline-first mobile layer (drift + sync outbox + local reminders) | ✅ Implemented | `app_database.g.dart` committed; screens use offline fallbacks; local notifications scheduled |
| — | Monad design system across all three surfaces | ✅ Implemented | `DESIGN.md` (token spec) → `{mobile,dashboard}/lib/theme/monad_theme.dart`; Newsreader + JetBrainsMono bundled; `backend/static/` landing page restyled |
| — | Client-side adaptive-difficulty + telemetry engine | ✅ Implemented + tested | `mobile/lib/games/game_analytics_engine.dart` (pure Dart, no Flutter imports) + `mobile/test/game_analytics_engine_test.dart` |

Tests: **130 pytest** pass + 1 skipped (`cd backend && python3 -m pytest app/tests tests -q`,
SQLite, no DB needed) across the API, security gates (phase0/11/12), reminder
engine, retention, sync consumer, RAG, document upload, LLM client, embedding
provider, notification + voice companion. `test_document_upload.py::test_upload_real_pdf`
needs `pypdf` installed (in `requirements.txt`; it is skipped-by-failure in a bare
env). Plus `python3 test_phase2_services.py` (standalone), `python3 smoke_e2e.py`
(live end-to-end walk against a real Postgres — auth → profile → game → reminders
→ dashboard → sync → companion → RAG → consent), and on the Flutter side
`flutter test` (model parsing + analytics engine) plus
`mobile/integration_test/app_flow_test.dart` (on-device, needs an emulator and a
backend at `10.0.2.2:8000`; on physical devices use
`adb -s SERIAL reverse tcp:8000 tcp:8000` plus
`--dart-define=API_BASE_URL=http://localhost:8000` — see DEPLOYMENT.md
"Run — September 30 demo").

---

## Current Architecture

Three surfaces share one FastAPI backend (`/api/v1` prefix, `GET /health` unprefixed):

- **`mobile/`** — Flutter patient app (Android/iOS effective; `dart:io` + drift prevent web builds). Offline-first: drift SQLite outbox, replay sync on reconnect, local reminder notifications.
- **`dashboard/`** — Flutter Web caregiver dashboard. Single-file (`lib/main.dart`): JWT login + auto-refresh, patient roster dropdown, 7-day metric tiles (cognitive accuracy, reminder compliance, response time), 14-day accuracy + response-time trend sparklines (pure `CustomPaint`, no chart dependency; clinical tier), active-alerts acknowledge, clinical-flags insight, reminder-schedule editing (list/add/delete, feeds the generation engine), admin audit-trail viewer (`GET /compliance/audit-logs`), and a basic-tier explanatory banner. Responsive.
- **`backend/`** — FastAPI + SQLAlchemy 2.0 + Alembic + PostgreSQL (pgvector image in compose). Routes: `auth`, `patients`, `games`, `reminders`, `compliance`, `dashboard`, `language`, `companion` (voice_companion), `reports` (RAG + weekly summary), `sync`.

**Access model** (`app/deps.py`): JWT bearer → user; `ensure_patient_access` (owner, active `CaregiverPatientLink`, or staff roles); `ensure_consent` per purpose scope (`game_data`/`health_data`/`voice_companion`); `get_permission_tier` → `basic`/`clinical` (family caregivers get `basic`; clinical detail like RAG docs gated by `ensure_clinical_access`).

---

## Background Jobs

`backend/app/jobs.py` — asyncio periodic loop (no external scheduler), started
from the API lifespan and also runnable standalone, each pass exception-isolated
per patient:

- **Reminder generation** (60s) — materializes PENDING `ReminderEvent`s from schedule cadences (idempotent).
- **Escalation scan** (60s) — PENDING→ESCALATED (10-min reprompt via notification service)→MISSED; 3 missed same-type in 7 days → AlertFlag + fan-out to linked family/ASHA.
- **Sync consume** (300s) — materializes the offline outbox (`offline_symptom` → encrypted `SymptomLog`).
- **Retention** (24h) — DPDP windows + 30-day grace hard-delete after consent revocation.

CLI: `python -m app.jobs` (forever) or `python -m app.jobs --once generate|escalation|consume|retention`. Disabled in `ENVIRONMENT=test`; controlled by `ENABLE_BACKGROUND_JOBS`.

---

## External Integrations (all graceful-degrade)

| Integration | Provider / default | Degradation when unconfigured |
|---|---|---|
| LLM (companion + RAG answers) | OpenRouter free-tier (`minimax/minimax-m3:free`; fallback chain `nemotron-3-*:free`). Anthropic alternative. `LLM_PROVIDER=auto` detects `sk-or-` prefix | Canned persona reply (`LLM_AUTO_FALLBACK`), or extractive RAG answers; never errors on the elder UX |
| Speech (ASR/TTS/NMT) | Bhashini ULCA (`auto\|bhashini\|mock`) | Deterministic local mock |
| Embeddings | `heuristic` default (deterministic md5-TF, 1536-dim); `local` (sentence-transformers e5-small); `openai` | Missing/unknown backends log a warning and return heuristic — RAG always works |
| Notifications | `console` (logs + records deliveries) | — (future: sms, fcm, email) |

Hard guard: `OPENROUTER_FREE_ONLY=true` refuses any model slug that is not
`:free`. Live usage needs the API keys in `.env` (see `.env.example`).

---

## Security & Production Posture (Phase 12)

- **Rate limiting** (`app/middleware/rate_limit.py`) — fixed-window per-IP (100/min), Redis-backed with an in-process fallback (cache outage never takes the API down); auto-on in production; skips `/health`, `/docs`, `/openapi.json`, `/api/v1/language/status`.
- **CORS** — whitelist via comma-separated `CORS_ORIGINS`; production refuses `*`.
- **Secret validation** — `Settings.validate_for_environment()` (run at lifespan boot) refuses placeholder/short `SECRET_KEY`/`ENCRYPTION_KEY` and wildcard CORS when `ENVIRONMENT=production`.
- **No implicit access** — cross-patient access is a 403 at every route; unknown patient IDs return 404 (no existence leak). Regression-tested in `test_phase0_fixes.py` + `test_phase11_gates.py`.
- **Permission tiers** — `basic` (family caregiver: dashboard + game activity) vs `clinical` (asha/clinician/admin: RAG docs, clinical summaries).
- **At-rest encryption** — `EncryptionService` (Fernet, key SHA-256-derived from `ENCRYPTION_KEY`) on `SymptomLog.notes` and `MedicalDocument.extracted_text`; audit tokens verify Fernet `gAAAA` prefix.
- **CI** (`.github/workflows/ci.yml`) — backend: pytest + standalone, `alembic upgrade head` on a clean Postgres 16, live `smoke_e2e.py`; frontend: `flutter pub get` + drift codegen + `flutter analyze` for mobile and dashboard.

---

## Phase 1 Decisions (Confirmed & Locked)

### 1. MVP Cognitive Baseline
**Decision:** Target healthy elderly through Mild Cognitive Impairment (MCI); defer moderate/severe dementia to v2

**Rationale:**
- Focuses UX and game mechanics on the most addressable cohort
- Dementia-specific UI needs (accessibility, behavioral design) warrant separate phase
- Allows faster MVP launch with clinical credibility

**Impact:**
- Difficulty curves assume MCI as upper bound
- Font sizes, interaction patterns designed for clarity (no tiny buttons)
- Reminder escalation built for confusion/forgetfulness, not severe impairment
- v2 will extend to dementia-friendly modes (larger text, simpler interactions, multimedia prompts)

**Difficulty grids (revised 2026-09-06, deliberately gentler than the original spec):**

| Level | Match It (`content_packs.py`) | Routine Sequencing (`routine_service.py`) |
|---|---|---|
| 1 | 2 pairs / 4 cards (2×2) | 3 steps, hints + icons |
| 2 | 4 pairs / 8 cards (4×2) | 4 steps, hints + icons |
| 3 | 6 pairs / 12 cards (4×3) | 6 steps, icons only (no hints) |

Icons now show at every level and hints through level 2 — the earlier
"text-only hard mode" tested as too abrupt for the MCI cohort. Content pool:
festivals, fruits/flora, and heritage packs (4-vernacular labels + region per
item, currently 10 / 10 / 12 items). Default routine is an 11-step Assamese day
(includes `dress_attire` — traditional attire).

---

### 2. Caregiver Dashboard: Flutter Web (Shared Models)
**Decision:** Build caregiver dashboard as Flutter Web, reusing shared Dart models from mobile app

**Rationale:**
- Single frontend codebase (Dart) eliminates model sync bugs
- No separate React team needed; Flutter handles iOS + Android + Web
- Game/session data models live in `lib/models/` — shared namespace

**Alternatives Considered:**
- React dashboard: Equally valid; would require separate API client + model duplication
- Native web framework: Adds backend complexity; Flutter Web is proven for dashboards

**Impact:**
- Mobile and dashboard stay in sync automatically
- Caregiver dashboard is responsive (works on tablets in the field — ASHA workers)
- Single deployment pipeline (Flutter CI for all three platforms)

> Note: today the dashboard is a self-contained single file that draws its trend
> charts with `CustomPaint` (no third-party charting library) and shares only the
> *backend API*, not Dart model files. The shared-models goal is met at the
> API-schema level.

---

### 3. Offline-First Gaming + Sync Queue Architecture
**Decision:** Games fully playable offline; sync to backend on reconnect via SyncQueue

**Implementation:**
- Mobile stores GameSession, GameAction, ReminderEvent, SyncQueue, PatientRoutine in local SQLite via drift (`app_database.dart` + committed codegen)
- `OfflineSyncService` polls every 30s when online; replays game sessions via HTTP and drains the outbox; local reminders scheduled via `flutter_local_notifications`
- Backend `/sync` accepts batched offline events; a consumer job materializes domain rows (idempotent)

**Rationale:**
- NER has spotty connectivity; offline capability is non-negotiable
- Local-first means reminder notifications fire without internet
- Sync queue is conflict-free for MVP: offline-created sessions are fresh INSERTs

**Impact:**
- Rural patients don't lose data or game streaks during connectivity gaps
- Caregiver dashboard shows "syncing" state when patient comes online
- No complex conflict resolution needed (v2 can add last-write-wins)

---

### 4. Voice Companion: Bhashini + LLM
**Decision:** ASR (patient's local language) → LLM (reasoning) → TTS (patient's language)

**Architecture:**
- `LanguageServiceProvider` interface abstracts Bhashini (pluggable for Google/Whisper later)
- System prompt versioned in `voice_companion_config` table (editable, not hardcoded)
- Persona: calm, patient, simple sentences; defers medical questions to caregiver
- LLM via `llm_client.py`: OpenRouter free-tier by default (policy: `:free` slugs only, fallback chain), Anthropic as alternative; provider auto-detected from key prefix

**Rationale:**
- Text-only interface excludes low-literacy elderly; voice is essential
- LLM reasoning > simple NLP for understanding context (memory, gentle redirection)
- Bhashini supports all NER languages; government-backed

**Impact:**
- Mobile voice pipeline is scaffolded; the chat (text) path and TTS/ASR service calls are integrated, mic/TTS playback on-device is pending speech plugins
- Easy to swap LLM provider (OpenRouter ↔ Anthropic ↔ local) if needed (security requirement)
- System prompt updates propagate without code changes

---

### 5. Reminder Escalation Thresholds
**Decision:**
- Unacknowledged: 10 minutes → secondary notification (re-prompt)
- Repeated missing: 3 missed same-type reminders in 7 days → AlertFlag
- Notification recipients: family + ASHA (if linked)

**Rationale:**
- 10min is typical for "did they see the notification?" without over-prompting
- 3 misses in 7 days signals pattern (confusion, resistance, or neglect) — clinical signal
- Family handles immediate response; ASHA is field presence

**Implementation:**
- ReminderEvent tracks: scheduled_at, delivered_at, acknowledged_at, status (pending | acknowledged | missed | escalated)
- AlertFlag generated by the background escalation job evaluating ReminderEvent history
- Escalation logged for caregiver dashboard + audit trail

**Impact:** Caregivers catch medication non-compliance early without false alarms

---

### 6. Multilingual MVP Scope
**Decision:** Ship with Assamese, Bengali, Hindi, English (highest-coverage for NER); companion picker additionally lists Mizo, Meitei (Manipuri), Khasi, Bodo, Garo, Nepali, provider-gated (unsupported entries show "not yet available" and are disabled).

**Future Additions (Config-Only):**
- Manipuri (Meitei), Khasi, Mizo, Nepali, Bodo added purely as Bhashini pipeline IDs
- No code changes needed — just add language_code to config

**Rationale:**
- Assamese: Assam (~31M speakers)
- Bengali: West Bengal, Tripura (~260M speakers, including Indian diaspora)
- Hindi: National, every region has Hindi-speaking elderly
- English: Clinician communication, admin interface

**Implementation:**
- LANGUAGE_SET config lists supported codes
- All API responses accept `?language=assamese` parameter
- Mobile stores preferred_language per user (PatientProfile.preferred_language); companion chat has a 10-language picker (default Assamese; entries the active provider does not cover show "not yet available" and are disabled)

**Impact:** NER coverage from day 1; extensible without rework

---

### 7. Authentication & Authorization
**Decision:** JWT (access + refresh tokens), server-side role-based enforcement

**Tokens:**
- Access: 15 minutes (short-lived, secure), stateless
- Refresh: 7 days, **single-use with rotation** — each token carries a `jti`, and
  `users.refresh_jti` holds the only one currently accepted (migration
  `0003_refresh_rotation`). `/auth/refresh` issues a new pair and rotates the jti;
  presenting a reused or superseded token clears `refresh_jti` outright, killing
  the whole chain (replay defence). Login supersedes any prior token; `/auth/logout`
  revokes by nulling the jti.

**Roles:**
- `patient` — plays games, acknowledges reminders
- `family_caregiver` — manages patient, sees basic activity
- `asha_worker` — field worker, manages multiple patients, sees clinical detail
- `clinician` — healthcare provider, sees raw scores + health data
- `admin` — system administration

**Enforcement:**
- JWT dependency verifies token on every authenticated endpoint
- Role checks injected as dependencies (`require_role`)
- Caregiver access requires active CaregiverPatientLink + ConsentRecord
- **No implicit access** — every caregiver-to-patient access is gated and audited

**Impact:**
- Access tokens stay stateless, so verification scales horizontally; only refresh
  costs one row read (the deliberate trade for replay detection)
- Rural field workers can re-login with refresh token if token expires — but the
  old token dies at that moment, so a copied token is useless
- Audit trail captures who accessed what patient data and when

---

### 8. Compliance (DPDP Act 2023)
**Decision:** Build DPDP compliance as a first-class feature, not a layer

**Core Elements:**

**Consent Capture (ConsentRecord table):**
- Explicit consent BEFORE any health data storage
- Scopes: game_data | health_data | voice_companion
- Consent types: patient_self | guardian | joint (supports cognitively impaired patients)
- Revocation: Either party can revoke; system atomically removes consent

**Audit Logging (AuditLog table):**
- Immutable log: user_id, action (read/write/delete), resource_type, resource_id, timestamp, ip, details
- Every health data access logged (compliance trail)
- Retention: indefinite (audit trail never deleted)

**Encryption:**
- **At-rest:** Fernet field encryption for symptom_notes, medical_document text (key SHA-256-derived from ENCRYPTION_KEY)
- **In-transit:** TLS 1.2+ required (enforce in production)
- Key rotation: Quarterly (production schedule)

**Data Retention:**
- Game sessions: 2 years (clinical value for trends)
- Symptom logs: 1 year (patient history)
- Reminder events: 6 months
- Medical documents: 5 years (+ chunks)
- Sync queue: 7 days (synced rows only)
- On revocation: Soft-delete; hard-delete after 30-day grace period

**Purpose Limitation:**
- ConsentRecord.scope restricts data use (`ensure_consent` in `deps.py`)
- API validation: game_data scope → cannot read SymptomLog / RAG documents
- Violation logs security alert

**Ethical Design for Cognitively Impaired:**
- Patients who cannot consent: Guardian gives consent (scope=guardian)
- Patients who can: Own consent (scope=patient_self)
- Both present: Joint (both must grant; either can revoke)
- UI flags consent status; caregiver dashboard shows revocation option

**Impact:**
- DPDP-compliant from day 1 (not bolted on later)
- Patients own their data; caregivers are trustees
- Compliance audits have a clean paper trail

---

## Tech Stack Rationale

| Component | Choice | Why |
|-----------|--------|-----|
| Backend | FastAPI | Async-first; Pydantic validation; development speed; excellent docs |
| Database | PostgreSQL + pgvector | Single DB for relational + vector (no separate vector store); pgvector for RAG embeddings |
| Cache/Queue | Redis | Session cache; rate limiting (rate-limit key store) |
| Mobile | Flutter (Dart) | Single codebase iOS + Android; strong typing; proven for health apps |
| Dashboard | Flutter Web | Same stack as mobile; no second frontend stack |
| Auth | JWT | Stateless; scales horizontally; standard for REST APIs |
| LLM | OpenRouter (free tier, `:free` slugs) | One key, multiple free models with fallback chain; Anthropic alternative |
| Speech | Bhashini | Government-backed; supports NER languages; pluggable interface |
| Migrations | Alembic | SQLAlchemy native; reversible; audit trail for schema changes |

---

## File Structure

### Backend
```
backend/
├── app/
│   ├── models/           # SQLAlchemy models: user, compliance (ConsentRecord/AuditLog),
│   │                     # all_models (patient, game, reminder, alert, sync, symptom,
│   │                     # medical doc/chunk, voice_companion_config) — 15 tables
│   ├── routes/           # auth, patients, games, reminders, compliance, dashboard,
│   │                     # language, voice_companion, reports, sync
│   ├── services/         # auth, compliance, dashboard, game, difficulty_engine, content_packs,
│   │                     # reminder, routine, sync, notification, language, llm_client,
│   │                     # rag, embedding_provider, document_extraction, report, retention,
│   │                     # voice_companion
│   ├── middleware/       # rate_limit.py (fixed-window per-IP, Redis+fallback); auth shim
│   ├── core/             # security.py (JWT create/verify)
│   ├── deps.py           # auth deps, patient-access gates, consent gates, permission tiers
│   ├── jobs.py           # background job loop (generate/escalation/consume/retention)
│   ├── config.py         # Settings; env validation; placeholder-secret refusal
│   ├── main.py           # app factory, middleware wiring, lifespan (jobs + env validation)
│   └── tests/            # 16+ pytest suites (API, security gates, engines, providers)
├── alembic/              # Alembic migrations (0001_initial_schema)
├── tests/                # test_auth.py, test_models.py
├── test_phase2_services.py  # standalone checks (20)
├── smoke_e2e.py          # live-server E2E walk
└── requirements.txt      # fastapi, sqlalchemy, alembic, jose, bcrypt, cryptography,
                          # redis, pgvector, httpx, pypdf, sentence-transformers, transformers...
```

### Flutter — mobile (patient app)
```
mobile/lib/
├── main.dart                 # auth gate, home shell, profile setup, role-aware routing
├── config/app_config.dart    # API_BASE_URL via --dart-define (defaults: web/desktop :8000,
│                             # Android emulator 10.0.2.2:8000)
├── models/                   # shared_models.dart (358L), game_models.dart (485L)
├── database/                 # app_database.dart (drift) + app_database.g.dart (committed codegen)
├── data/                     # local_content_packs.dart (offline NER packs fallback)
├── games/                    # game_analytics_engine.dart (adaptive difficulty + risk flags,
│                             # pure Dart), game_labels.dart, game_visuals.dart
├── theme/monad_theme.dart    # Monad tokens (see DESIGN.md) — colors, type, spacing, radii
├── widgets/                  # trend_chart.dart (unused; available for dashboard)
├── services/                 # api_service, auth_session, offline_sync_service, reminder_service,
│                             # reminder_scheduler, routine_service, match_it_service
└── screens/                  # auth, match_it, pack_picker, routine, reminders,
                              # voice_companion (text chat, 10-lang picker, provider-gated), caregiver_dashboard (role-gated)

mobile/integration_test/app_flow_test.dart   # on-device flow (emulator + backend at 10.0.2.2:8000)
mobile/android/app/src/debug/                # debug-only cleartext HTTP to 10.0.2.2 + localhost
                                             # (network_security_config.xml); release stays TLS-only
```

### Flutter Web — caregiver dashboard
```
dashboard/
├── lib/main.dart             # single-file app: login, roster, summary tiles, alerts, insights
└── lib/theme/monad_theme.dart  # Monad tokens (copy of mobile's, minus the game tints)
```

### Other
```
DESIGN.md                     # Monad style reference — the token source of truth both
                              # monad_theme.dart files mirror
demo-seed/documents/          # 3 synthetic RAG demo docs (discharge summary, prescription, care plan)
backend/static/               # Monad-styled landing page served at /static
.github/workflows/ci.yml      # backend (tests + PG migration + E2E smoke) + frontend (codegen + analyze)
docker-compose.yml            # pgvector/pg16 + redis + backend (no dashboard container)
```

---

## Testing Strategy

- **Unit:** models, auth (JWT/bcrypt/refresh rotation), providers (language, embeddings, notification), services (reminder engine, retention, sync consumer, RAG, report, compliance) — pytest, SQLite in-memory, `ENVIRONMENT=test`
- **Security gates:** `test_phase0_fixes.py` (5 P0 regressions: encryption config key, report decrypt, auth on `/language/*`, consent-revoke ownership, game-session IDOR), `test_phase11_gates.py` (cross-patient 403/404, read-audit rows, encrypted docs), `test_phase12_gates.py` (consent scoping, permission tiers, production secret/CORS refusal)
- **Integration:** `test_api_routes.py` E2E flows; `smoke_e2e.py` for live-server vs real Postgres (companion-config POST treats a 409 as idempotent pass, so re-runs are clean)
- **Frontend:** mobile `test/game_analytics_engine_test.dart` (difficulty rules + report fields) and `test/widget_test.dart` (model parsing); `test/api_live_test.dart` and `integration_test/app_flow_test.dart` need a running backend/emulator; dashboard single smoke widget test
- **Commands:** `cd backend && python3 -m pytest app/tests tests -q` · `python3 test_phase2_services.py` · `python3 run_tests.py` · `python3 smoke_e2e.py` · `cd mobile && flutter test`
- **Demo runs (2026-09-30):** use `backend/.venv-demo` (Python 3.12) with
  `ENABLE_BACKGROUND_JOBS=false` against the populated Homebrew Postgres
  `localhost:5432/eldercare` (sysid `7681754862742343790`) — **not** the compose
  cluster. Full runbook: DEPLOYMENT.md "Run — September 30 demo". Current source
  (B) requires migration `0009_shadow_difficulty` (not approved/applied; SQLite-only
  tested) before any restart at HEAD, so startup from new HEAD is blocked pending
  backup + explicit approval; the pinned schema-0008 server (PID 51348) remains
  valid until restarted.

---

## Remaining Work (reconciled)

**Shipped since the last reconcile (2026-09-06):** single-use refresh-token
rotation (`0003_refresh_rotation`), Monad design system across mobile +
dashboard + `backend/static/`, client-side `game_analytics_engine.dart` with
tests, gentler difficulty grids (2/4/6 pairs; hints through L2), 5 new NER
content items + an 11th routine step, two game-scoring bug fixes (attempts only
count resolved attempts; `raw_event_log` reassigned so SQLAlchemy persists it),
idempotent companion-config step in `smoke_e2e.py`, and a debug-only Android
cleartext config for `10.0.2.2`/localhost.

**Genuinely open / deferred:**
- Live API keys to activate real integrations (OpenRouter `OPENROUTER_API_KEY`,
  Bhashini `BHASHINI_API_KEY`/`BHASHINI_USER_ID`, Anthropic `ANTHROPIC_API_KEY`)
  — everything degrades gracefully when absent
- Mobile voice companion audio path: on-device mic capture + TTS playback need
  speech plugins (text chat + service-side ASR/TTS are wired); notification
  permission request call and notification-tap handler pending
- Mobile per-action game telemetry: screens queue `actions: []` though the
  `GameAction` table + replay path exist. `game_analytics_engine.dart` computes
  the same metrics client-side but does not yet feed the server telemetry path.
- Game art is unsourced: `mobile/assets/games/` holds only a manifest README —
  32 card PNGs + audio are to be commissioned. Not a blocker: every visual falls
  back to a theme-colored Material icon via `lib/games/game_visuals.dart`, so a
  missing file never crashes the UI (add keys to `GameVisuals.availableImages` to
  activate real art).
- Real notification channels (SMS/email/APNs/FCM) beyond the `console` provider;
  data-export for ransomware-style backup/recovery (Phase 12 checklist)
- `monad_theme.dart` is copied in `mobile/` and `dashboard/` with no shared
  package, and the copies have already diverged — mobile adds a game extension
  (pastel `tint*` card-face colors, never color-alone). Shared token edits must
  land in both files by hand.
- Dashboard reminder-schedule editing and audit-trail viewer are in; deeper
  drill-down (per-event reminder history, alert timelines) is next
- v2: ML-based alert rules, wearable data, dementia-friendly modes

---

## Compliance Verification

**DPDP Act 2023 (implemented + tested):**
- ✅ Consent capture / scope gates (`ensure_consent`)
- ✅ Purpose limitation — game_data scope cannot read clinical data
- ✅ Data retention policy + deletion jobs (`RetentionService`)
- ✅ Audit trail — read/write audit on all patient-data paths; immutable
- ✅ Encryption (Fernet field encryption + bcrypt password hashes)
- ✅ Deletion rights — revoke + 30-day grace hard-delete
- ✅ Data portability — `GET /compliance/patients/{id}/export`

**HIPAA-Adjacent** (not required, but best practice):
- ✅ Access controls (JWT + role-based + no-implicit-access)
- ✅ Audit logging (endpoint-wide read-audit enforced)
- ✅ Encryption
- ✅ Data integrity (SQLAlchemy constraints)
- ⬜ Backup/recovery + TLS enforcement in front of a real deployment

> Implementation is enforced across routes and regression-tested
> (`test_phase11_gates.py`, `test_phase12_gates.py`), not just designed.

---

## Questions / Escalation

- **Architecture:** See this file (CLAUDE.md)
- **Security/Privacy:** `backend/app/services/compliance_service.py` + `docs/superpowers/plans/2026-09-04-phase1-scaffold-data-models.md`
- **Schema/Data:** `backend/app/models/` + `backend/alembic/versions/0001_initial_schema.py`
- **API Endpoints:** `backend/app/routes/` (all mounted under `/api/v1`; interactive docs at `/docs`)
- **Implementation Plan:** `docs/superpowers/plans/2026-09-04-phase1-scaffold-data-models.md`, `docs/superpowers/plans/2026-09-05-remaining-roadmap-to-mvp.md` (roadmap was written at the Phase-10 boundary; Phases 11–12 have since shipped)

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

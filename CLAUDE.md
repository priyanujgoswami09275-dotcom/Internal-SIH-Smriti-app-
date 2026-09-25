# Architecture & Decisions — Elder-Care Cognitive Companion Platform

## Project Overview
**SIH26003** — Production-grade AI platform for elderly cognitive health in India's North Eastern Region (NER). Two user-facing surfaces (patient mobile app, caregiver dashboard) sharing one backend. Built for Smart India Hackathon 2026, architected for production: proper layering, migrations, tests, error handling, security/privacy built in from day 1.

---

## Implementation Status (Reconciled 2026-09-25)

The code and this file are authoritative when older tracker or deployment notes
disagree. All 12 roadmap phases have implementation coverage; test-result counts
are intentionally not duplicated here because they change as suites grow. The ML
track (Phase A experimental risk screening, Phase B-01 shadow-only next-level
prediction) is a separate, later track layered on top of those phases; tracker
docs written before it landed are stale on those points.

| Phase / area | Scope | Status | Evidence |
|---|---|---|---|
| 1–7 | Backend scaffold, data models, auth/RBAC, games, reminders + escalation, dashboard analytics, sync, and patient endpoints | Implemented + tested | Migrations `0001_initial_schema` through `0015_rls_public_tables`; models/services/routes; access-gate tests |
| 8 | Pluggable ASR / NMT / TTS providers | Implemented + contract-tested | `language_service.py`; `auto` selects Sarvam → AI4Bharat → Bhashini → mock. The shipped example configuration has no provider credentials, so its default is deterministic simulated speech, not live speech. |
| 9 | Voice companion (LLM) | Implemented | `llm_client.py` (OpenRouter default / Anthropic alternative), DB-versioned prompts, auth + config endpoints, canned-reply fallback |
| 10 | RAG pipeline for medical documents | Implemented | Text PDF/text upload, chunking, embedding provenance checks, cited answers, encrypted source/chunk text, per-patient reindex command, and extractive fallback without an LLM key. Image-only PDFs are rejected because this build has no OCR. |
| 11 | Compliance enforcement | Implemented + tested | Consent-scope gates, no-implicit-access, broad read/write audit coverage, Fernet field encryption, data export, retention/deletion jobs. Audit rows are append-oriented and retained, but database-level immutability is not enforced. |
| 12 | Production hardening | Implemented | Rate limiting (Redis + fallback), CORS allowlist, placeholder-secret refusal, CI, and E2E smoke against a clean PostgreSQL 16 service |
| 13 | Number/Word Recall game | Implemented + tested | `recall_service.py` + route; mobile `recall_screen.dart` + tests |
| 14 | Language naming/gating (Manipuri canonical, Meitei alias, Garo hard-gated) | Implemented + tested | `test_language_aliases.py` |
| 15 | Spoken reminders (cached server TTS, ack-screen playback) | Implemented + tested | `tts_cache.dart`; `reminder_voice_test.dart` |
| 16 | Level config as difficulty source of truth | Implemented + tested | `game_level_config` table + `level_config_service.py` backend, `level_config.dart` mobile |
| A | Experimental risk screening (separate ML system) | Implemented + tested, **not clinically validated** | `POST` and `GET /patients/{id}/risk-screening`; owner/staff access + `health_data` consent; persistence + read/write audit |
| B-01 | Shadow-only next-level success model | Implemented + tested, **shadow mode only** | Shadow probability rides in nullable `shadow_*` fields; the rule-based difficulty decision is the sole authority and the shadow value never changes it |
| — | Flutter surfaces | Implemented + tested | Mobile and multi-file caregiver dashboard are exercised in CI; dashboard release builds require an explicit API URL |
| — | Offline-capable mobile layer | Implemented | Bundled/generated offline boards where available, cached level config and public Odd-One-Out boards, a drift-backed replay outbox, and local reminder notifications. In-progress game rounds are memory-only and are not resumed after app death. |
| — | Monad design system | Implemented | `DESIGN.md` → `{mobile,dashboard}/lib/theme/monad_theme.dart`; Newsreader + JetBrains Mono bundled; `backend/static/` landing page restyled |
| — | Client game-metrics calculator | Implemented + tested | `mobile/lib/games/game_analytics_engine.dart` computes local metrics/hints. It does not choose the next difficulty; the server's rule-based `recommended_level` is applied after an online completion. |

Canonical verification commands (run from the repository root unless a command
says otherwise):

```sh
cd backend && python3 -m pytest app/tests tests -q
cd backend && python3 test_phase2_services.py
cd mobile && flutter test
cd dashboard && flutter test && flutter test --platform chrome
```

`cd backend && python3 smoke_e2e.py` is the live PostgreSQL-backed smoke walk.
`mobile/integration_test/app_flow_test.dart` remains an on-device check and needs
an emulator/device plus a backend at `10.0.2.2:8000`; for a physical device use
`adb -s SERIAL reverse tcp:8000 tcp:8000` and
`--dart-define=API_BASE_URL=http://localhost:8000` (see `DEPLOYMENT.md`).

---

## Current Architecture

Three surfaces share one FastAPI backend (`/api/v1` prefix, `GET /health` unprefixed):

- **`mobile/`** — Flutter patient app (Android/iOS). The API base URL comes from `--dart-define=API_BASE_URL`; a **release** build additionally requires it to be an explicit public `https://` URL and refuses to compile otherwise (unset, `http://`, loopback, or private-range hosts all fail the build). Debug/JIT builds keep the `localhost` / `10.0.2.2` defaults. The app can start Match It, Routine Sequencing, and Number Recall from bundled offline data; Odd-One-Out requires a previously cached public board. Completed offline sessions/actions and reminder acknowledgments enter a durable drift SQLite outbox. `OfflineSyncService` polls every 30 seconds, scopes queued items to the active account, replays idempotently, and retains failed items for retry. Logout stops replay but does not delete another account's pending rows. Level configuration and public Odd-One-Out board snapshots use `SharedPreferences`; synthesized reminder audio uses a temporary text+language keyed cache. **An in-progress round is not checkpointed: process/app death starts a new board or cached round rather than resuming the exact board.**
- **`dashboard/`** — Flutter Web caregiver dashboard split across `lib/main.dart`, `lib/config.dart`, theme code, and focused widgets. It has JWT login + serialized refresh, roster selection, role/permission-driven metric/trend/risk/document controls, an admin-only audit control with 50-row offset pagination, and a consent preflight before clinical screening or document upload. The server view remains authoritative. A release build **fails to compile** without `--dart-define=API_BASE_URL=<public https URL>`; `http://` and loopback/private hosts are rejected too, because a served web build is itself loaded over HTTPS. Development defaults to `http://localhost:8000`.
- **`backend/`** — FastAPI + SQLAlchemy 2.0 + Alembic + PostgreSQL. Routes: `auth`, `patients`, `games`, `reminders`, `compliance`, `dashboard`, `language`, `voice_companion`, `reports` (RAG + weekly summary), and `sync`. RAG vectors currently use a portable JSON column; pgvector is available in the compose image but is not the active vector index.

**Access model** (`app/deps.py`): clients call the API with JWT bearer tokens; they have no Supabase/Firebase client SDK and no direct table access. The app layer resolves the user, then enforces `ensure_patient_access` (owner, active `CaregiverPatientLink`, or staff role), `ensure_consent` for `game_data`/`health_data`/`voice_companion`, and `get_permission_tier` → `basic`/`clinical`; clinical routes additionally call `ensure_clinical_access`. Enabling direct client database access later would require a new threat model plus publishable-only credentials, per-table/per-operation RLS, authenticated JWT claim propagation, tenant/patient/consent scoping, revocation/session handling, migration and integration tests, and proof that no service-role secret can reach a client. None of that exists in the current build.

---

## Background Jobs

`backend/app/jobs.py` — asyncio periodic loop (no external scheduler), started
from the API lifespan and also runnable standalone, each pass exception-isolated
per patient:

- **Reminder generation** (60s) — materializes idempotent PENDING `ReminderEvent`s from validated daily cadence times.
- **Escalation scan** (60s) — PENDING→ESCALATED (10-min reprompt request)→MISSED; 3 unresolved same-type reminders in 7 days → `AlertFlag` + recipient-resolution attempt.
- **Sync consume** (300s) — materializes queued offline symptoms into encrypted `SymptomLog` rows.
- **Retention** (24h) — DPDP windows + 30-day grace hard-delete after consent revocation.

The default `console`/FCM adapter state is explicit: notification attempts may
be logged and delivery-audit rows may record FAILED, but escalation responses and
job summaries return `delivery_state: not_configured` with zero confirmed
deliveries. `not_configured` means no recipient delivery was confirmed; it must
not be presented as a sent notification.

CLI: `python -m app.jobs` (forever) or `python -m app.jobs --once generate|escalation|consume|retention`. Disabled in `ENVIRONMENT=test`; controlled by `ENABLE_BACKGROUND_JOBS`.

---

## External Integrations (all graceful-degrade)

| Integration | Provider / default | Degradation when unconfigured |
|---|---|---|
| LLM (companion + RAG answers) | OpenRouter free-tier (`minimax/minimax-m3:free`; configured `nemotron-3-*` fallback chain). Anthropic alternative. `LLM_PROVIDER=auto` detects the OpenRouter key prefix | Canned persona reply (`LLM_AUTO_FALLBACK`) or extractive RAG answers |
| Speech (ASR/NMT/TTS) | `auto` selects Sarvam → AI4Bharat → Bhashini → mock by configured credentials | With the shipped empty provider keys, `auto` returns deterministic simulated ASR/NMT/TTS. No live speech provider is configured by default. |
| Embeddings | `heuristic` default (deterministic md5-TF, 1536-dim); `local` (sentence-transformers e5-small); `openai` | Missing/unknown backends warn and return heuristic |
| Notifications | `console` by default; the current FCM adapter records failed/log-only attempts rather than sending | `delivery_state: not_configured`, zero confirmed deliveries |

NER-relevant language coverage implemented per provider:

| Provider | ASR | NMT | TTS | Configuration reality |
|---|---|---|---|---|
| Sarvam | Assamese, Bengali, Hindi, English, Manipuri/Meitei, Bodo, Nepali | Same seven | Bengali, Hindi, English | Live only with `SARVAM_API_KEY`; Khasi, Mizo, and Garo are unsupported by the maps |
| AI4Bharat | Assamese, Bengali, Bodo, Manipuri/Meitei, Nepali, Hindi, English | Same seven | Same seven | Code path exists; the default HF router does not currently serve these models, so a dedicated endpoint is required |
| Bhashini ULCA | Assamese, Bengali, Hindi, English, Manipuri/Meitei, Bodo, Nepali, Mizo, Khasi | Same nine | Same nine | Live only with both `BHASHINI_API_KEY` and `BHASHINI_USER_ID`; Garo is unsupported |
| Mock | Advertised picker languages only | Advertised picker languages only | Advertised picker languages only | Deterministic simulation, not recognition, translation, or intelligible synthesis |

Hard guard: `OPENROUTER_FREE_ONLY=true` refuses any model slug that is not
`:free`. Live providers require operator-supplied environment variables; see
`.env.example`.

---

## Security & Production Posture (Phase 12)

- **Rate limiting** (`app/middleware/rate_limit.py`) — fixed-window per-IP (100/min), Redis-backed with an in-process fallback; auto-on in production; skips health/docs/openapi/status endpoints.
- **CORS** — allowlist via comma-separated `CORS_ORIGINS`; production refuses `*`.
- **Secret validation** — `Settings.validate_for_environment()` refuses placeholder/short `SECRET_KEY`/`ENCRYPTION_KEY` and wildcard CORS when `ENVIRONMENT=production`.
- **No implicit access** — cross-patient access is rejected and unknown patient IDs return 404. Patient-link, consent-purpose, role, and clinical-tier checks happen in the FastAPI app layer.
- **No direct client data access** — mobile and dashboard use only the REST API. They do not embed Supabase/Firebase table SDKs, anon table credentials, or a service-role key.
- **Row-level security (defense in depth)** — migration `0015` enables RLS on every public table and creates **no policies**, so any non-owner role reads zero rows even if it holds a table `GRANT`. The API connects as the table owner, which bypasses RLS because `FORCE ROW LEVEL SECURITY` is deliberately not set. The app layer therefore remains the single authorization point; RLS is a backstop against a leaked anon/publishable key, not a replacement for `app/deps.py`. See **Schema parity and row-level security**.
- **Permission tiers** — `basic` for linked family caregivers by default; `clinical` for ASHA workers, clinicians, admins, patient owners, or an explicitly clinical link. Controls are role/permission-driven, but the server remains authoritative.
- **At-rest encryption** — `EncryptionService` (Fernet, key SHA-256-derived from `ENCRYPTION_KEY`) protects `SymptomLog.notes`, `MedicalDocument.extracted_text`, and every new `DocumentChunk.chunk_text`. Plaintext exists only during processing/retrieval in memory.
- **Audit trail** — broad read coverage plus tested write coverage for consent, reminders, alerts, document ingest/reindex, voice conversations, sync materialization, and other patient-data paths. Most read/write helper calls are best-effort (failure is logged and the request continues); consent grant/revoke, document ingest/reindex, and data export are fail-closed. Retention excludes audit rows. **Database-level immutability is not enforced**: there are no database triggers, grants, or update/delete denial policies, so an actor with database write privileges can alter or remove a row.
- **CI** (`.github/workflows/ci.yml`) — backend pytest + standalone checks, `alembic upgrade head` on a clean PostgreSQL 16 service, and live `smoke_e2e.py`; mobile dependency/codegen/analyze/unit-test gates; dashboard dependency/analyze/VM-test, Chrome-platform test, and release web build gates. No provider secret is required because live integrations are not part of CI.

### RAG integrity and maintenance

Every new `MedicalDocument` records embedding provider, model, and dimensions.
Retrieval refuses a document whose provenance is missing or differs from the
active provider/model/dimension instead of comparing incompatible vectors. The
maintenance command is:

```sh
cd backend && python -m app.services.rag_service reindex \
  --patient-id <patient-uuid> --actor-id <operator-user-uuid>
```

Reindex is patient-scoped and idempotent: it recomputes vectors with the active
provider, backfills provenance, rewrites legacy plaintext chunk text as Fernet
ciphertext, and records a `rag_reindex` write-audit row for changed documents.
That is the implemented plaintext-PHI migration path for legacy chunk rows. It
does not claim to rewrite an arbitrary plaintext `MedicalDocument.extracted_text`
row; operators must re-ingest/backfill such source rows under a controlled
process. Upload currently extracts selectable PDF text and text-family files;
there is no OCR, so image-only PDFs fail before persistence.

### Migrations

The single Alembic head is `0015_rls_public_tables`. The canonical migration
test is part of `cd backend && python3 -m pytest app/tests tests -q`; CI also
runs `alembic upgrade head` against a clean PostgreSQL 16 service. Never run
`alembic upgrade head` casually against the populated demo database: back it up,
verify the exact database/system identifier and current revision, review the
migration, and obtain explicit approval first. `smoke_e2e.py` also writes
synthetic records and is not a read-only check.

### Schema parity and row-level security

Two opt-in suites compare the ORM models to the migration-built schema and
assert the database security posture. Both run in CI against the freshly
migrated service and skip cleanly elsewhere:

```sh
cd backend
SCHEMA_PARITY_POSTGRES_URL="$DATABASE_URL" python3 -m pytest tests/test_model_schema_parity.py -q
RLS_MIGRATION_POSTGRES_URL="$DATABASE_URL" python3 -m pytest tests/test_migrations.py -q
```

`test_model_schema_parity.py` asserts the model metadata and the migrated
schema agree on table set, columns, nullability, and unique
constraints/indexes — so a column that exists in only one of them fails the
build rather than a request. `test_migrations.py` additionally asserts every
public table has RLS enabled, that **zero** policies exist, and that the owner
role (the API's connection) still reads its rows.

Migration `0015` is what makes RLS reproducible. It enables RLS on every
public table discovered from the live catalog and creates **no policies**, so a
non-owner role reads zero rows even if it holds a table GRANT. It is idempotent,
so applying it to a project that was fixed by hand is safe. Its downgrade
disables RLS; that is a deliberate security regression kept only for a
reversible chain and should not be run against a deployed database. Do not add
permissive policies: the FastAPI app layer is the single authorization point
(see **Access model**), and a second, weaker path is a regression.

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

Number Recall is a **digit-sequence** game at levels 1/2/3 (3/4/6 digits). Word
Recall is not implemented in this scope.

**Adaptive flow:** online play starts a server session, buffers/sends action
rows, and completes through the idempotent session endpoint. The server scores
the actions, applies its rule strategy (3 consecutive sessions above 85% may
bump; 2 below 50% may drop), and returns `recommended_level`, source, reason,
and shadow-model metadata. The client uses that server value for the next round.
`game_analytics_engine.dart` computes local performance scores/tags and in-round
hints and can emit an offline result, but its local streak calculator does not
promote an in-progress/offline round. Shadow-model output never controls level.

Icons now show at every level and hints through level 2 — the earlier
"text-only hard mode" tested as too abrupt for the MCI cohort. Content pool:
festivals, fruits/flora, and heritage packs (4-vernacular labels + region per
item, currently 10 / 10 / 12 items). Default routine is an 11-step Assamese day
(includes `dress_attire` — traditional attire).

---

### 2. Caregiver Dashboard: Flutter Web
**Decision:** Build the caregiver dashboard as Flutter Web and keep authorization
in the FastAPI app layer.

**Current implementation:**
- The web app is multi-file: `dashboard/lib/main.dart` owns the shell/client and
  views, `dashboard/lib/config.dart` owns release API URL validation, and focused
  widgets cover risk screening and RAG upload.
- JWT login/refresh/logout persists the web session; refresh requests are
  single-flight. The current role and selected patient's server-provided
  permission tier drive visible controls, but never replace server checks.
- Selecting a clinical patient preflights `health_data` consent before enabling
  risk screening or document upload. A failed/uncertain preflight disables the
  control and explains the state.
- The audit control is admin-only in the UI and uses 50-row offset pagination.
  Trend charts remain dependency-free `CustomPaint` widgets.
- Release builds must receive an absolute
  `--dart-define=API_BASE_URL=https://...`; there is no implicit release URL.

Run locally from `dashboard/`:

```sh
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
flutter test
flutter test --platform chrome
flutter build web --release --dart-define=API_BASE_URL=https://api.example.org
```

The original goal of sharing Dart model files was not reached; the two clients
share the API schema and authorization contract, not a Dart package.

---

### 3. Offline-Capable Gaming + Durable Sync Outbox
**Decision:** Preserve useful play/reminder behavior through connectivity gaps,
but do not describe the app as a fully offline-first client.

**Durable scope:**
- The drift schema defines game session/action, reminder event, sync queue, and
  routine tables. The live gameplay path durably queues **completed** offline
  sessions/actions and reminder acknowledgments; it does not checkpoint every
  move from a currently active round.
- The sync outbox stores patient ID plus account ID. `OfflineSyncService` selects
  only rows for the active account, so a newly logged-in account cannot replay a
  prior account's pending item. Logout stops the timer; it does not destroy the
  durable queue.
- Replay uses stable idempotency keys. Failed items remain pending with an
  incremented retry count and visible failure state; synced rows are removed
  after seven days.
- Level configuration and public Odd-One-Out board snapshots survive restarts in
  `SharedPreferences`; synthesized reminder audio is cached by text + language in
  a temporary file. Session tokens and the small user profile are also persisted
  for restore.
- Scheduled local notifications continue without a network. Reminder
  acknowledgments made while the API is unavailable enter the durable outbox.

**Non-durable scope:** an in-progress Match It, Routine Sequencing, Number Recall,
or Odd-One-Out round lives in widget memory. App/process death does not restore
the exact board, moves, timers, or server session. Match It/Routine/Number Recall
can start a new local round; Odd-One-Out needs a compatible cached public board
and otherwise shows a connect-to-download state.

Backend `/sync` accepts batched offline operations, and the consumer materializes
eligible domain rows idempotently. Document uploads and clinical API reads are
not queued offline.

---

### 4. Voice Companion: Pluggable Speech + LLM
**Decision:** Support ASR → LLM → TTS behind provider interfaces while keeping
text conversation usable when speech is unavailable.

**Architecture:**
- `LanguageServiceProvider` implementations are Sarvam, AI4Bharat via a dedicated
  Hugging Face endpoint, Bhashini ULCA, and deterministic mock.
- `LANGUAGE_SERVICE_PROVIDER=auto` chooses by configured credentials in that
  order. The shipped `.env.example` has empty credentials, so default execution
  is simulated speech. The UI uses `/language/status` operation capabilities to
  disable unsupported language/action combinations; it does not infer live
  capability from the language picker alone.
- The system prompt is versioned in `voice_companion_config`; persona copy is
  calm and concise and defers medical decisions.
- `llm_client.py` supports OpenRouter and Anthropic, with canned-reply/extractive
  fallbacks.

**Verification boundary:** provider clients have mock-transport contract tests;
opt-in live tests require explicit provider secrets. Physical-device mic,
speaker, and notification behavior has not been validated. A mock transcript,
translation, or base64 WAV must never be presented as live-provider evidence.

---

### 5. Reminder Cadence, Escalation, and Delivery State
**Cadence grammar:** `[daily|everyday|every day][@|at|:]? HH:MM[,HH:MM;HH:MM]...`
(case-insensitive, 24-hour wall clock in `REMINDER_TIMEZONE`). Legacy
`HH:MM AM|PM Daily` is accepted. Free text such as "after lunch" is rejected;
duplicate times collapse to one daily occurrence.

**Lifecycle and thresholds:**
- Unacknowledged for 10 minutes → `ESCALATED` + reprompt attempt.
- Still unresolved for 60 minutes → `MISSED`.
- 3 unresolved same-type reminders in 7 days → `AlertFlag` and a linked
  family/ASHA recipient-resolution attempt.
- `ReminderEvent` tracks schedule/occurrence time, delivery/acknowledgment
  timestamps, method, and status.

**Delivery honesty:** `console` and the current FCM adapter do not confirm
recipient delivery. They log/audit the attempt and return
`delivery_state: not_configured`, `confirmed_deliveries: 0`, and an explicit
message. This state is distinct from `sent`, `failed`, `no_recipients`,
`not_applicable`, or `mixed`.

---

### 6. Multilingual and Speech Scope
**Product picker (10):** Assamese, Bengali, Hindi, English, Mizo, Meitei
(Manipuri), Khasi, Bodo, Garo, and Nepali. `meitei` is an alias of canonical
`manipuri`. Garo has no backend provider mapping and is always disabled.

Provider capability is operation-specific, not a single language list. The exact
NER-relevant ASR/NMT/TTS coverage and the default simulated state are recorded in
**External Integrations** above. Khasi/Mizo are unavailable on Sarvam and
AI4Bharat; Sarvam TTS is narrower than its ASR/NMT set; AI4Bharat's default
serverless router does not currently host the selected models. Mobile stores the
preferred language on the user and gates controls from the status endpoint.

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
- **No implicit access** — every caregiver-to-patient request is gated; covered successful operations write audit rows under the best-effort/fail-closed policy documented below

**Impact:**
- Access tokens stay stateless, so verification scales horizontally; only refresh
  costs one row read (the deliberate trade for replay detection)
- Rural field workers can re-login with refresh token if token expires — but the
  old token dies at that moment, so a copied token is useless
- Audit rows identify actor, action, resource, and time for covered paths; audit persistence itself is not database-immutable

---

### 8. Compliance (DPDP Act 2023)
**Decision:** Build DPDP compliance as a first-class feature, not a layer

**Core Elements:**

**Consent Capture (`ConsentRecord`):**
- Active purpose scopes are `game_data`, `health_data`, and `voice_companion`
  (plus the broader `all` scope). Routes enforce the required scope before
  protected operations.
- The currently enforced grant policy accepts `patient_self` consent only.
  `guardian` and `joint` remain enum/schema values but are rejected by
  `validate_consent_policy`; do not claim verified guardian/joint workflows.
- Revocation records `revoked_at`; retention removes revoked consent and linked
  risk-screening rows after the 30-day grace period.

**Audit Logging (`AuditLog`):**
- Rows contain actor, action (`read`/`write`/`delete` enum), resource identity,
  timestamp, IP, and details. Current automated coverage is broad for reads and
  tested across representative write paths; it is not a mathematical proof that
  every future route writes a row.
- `log_read_access` and low-risk `log_write_access` are best-effort: an audit
  failure is logged, the session is restored, and the request/write continues.
  Consent grant/revoke, document ingest/reindex, and patient export are
  fail-closed. Notification-delivery audit is separately best-effort.
- Retention code excludes `audit_logs`, so the application does not purge them.
  They are not database-immutable: no trigger, grant, RLS, or database policy
  prevents a privileged SQL actor from updating/deleting a row.

**Encryption and transport:**
- Fernet field encryption protects symptom notes, medical-document source text,
  and document chunk text. `ENCRYPTION_KEY` is SHA-256-derived into a Fernet
  key; plaintext is used only in memory during allowed processing/retrieval.
- TLS 1.2+ is a deployment requirement, not enforced by FastAPI itself. A
  production deployment must terminate TLS at its trusted proxy/load balancer.
  Key rotation remains an operator process; no quarterly rotation is automated.

**Data Retention:**
- Game sessions: 2 years; symptom logs: 1 year; reminder events: ~6 months;
  medical documents + chunks: 5 years; synced backend sync rows: 7 days.
- Revoked consents and linked screening rows: hard-delete after 30 days.
- The maintenance job is idempotent; pending sync rows are not purged.

**Purpose and ethical controls:**
- `ensure_consent` limits route data use to active scopes.
- Patient ownership, active caregiver links, role checks, and clinical tiers are
  separate gates; a role alone does not bypass consent.
- The UI exposes consent state, but enforcement and audit guarantees come from
  the server—not from hiding a button.

---

## Tech Stack Rationale

| Component | Choice | Why |
|-----------|--------|-----|
| Backend | FastAPI | Async-first; Pydantic validation; OpenAPI docs |
| Database | PostgreSQL | Relational store for users, consent, clinical data, and audit rows. The compose image includes pgvector, but current RAG embeddings are stored in a JSON column and scored in Python. |
| Cache | Redis | Conversation cache and rate-limit backing, with in-process fallback |
| Mobile | Flutter (Dart) | iOS + Android client with drift/SQLite offline support |
| Dashboard | Flutter Web | Same language ecosystem, separate app and API client |
| Auth | REST JWT + app-layer RBAC | No direct client database credentials or table SDK |
| LLM | OpenRouter default / Anthropic alternative | Configurable free-model fallback chain and deterministic fallback |
| Speech | Sarvam / AI4Bharat / Bhashini / mock | Operation-specific language gating; default is simulated without credentials |
| Migrations | Alembic | SQLAlchemy-native chain; current head `0015_rls_public_tables` |

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
│   ├── services/         # auth, compliance, dashboard, game/difficulty, reminders,
│   │                     # routine, sync, notification, language, LLM/RAG/embeddings,
│   │                     # document extraction, reports, retention, voice companion
│   ├── middleware/       # fixed-window per-IP rate limiting (Redis + fallback); auth shim
│   ├── core/             # security.py (JWT create/verify)
│   ├── deps.py           # JWT user, patient-access, consent, and permission-tier gates
│   ├── jobs.py           # generate/escalation/consume/retention loop
│   ├── config.py         # Settings, environment loading, production secret/CORS refusal
│   ├── main.py           # app factory, middleware, lifespan jobs + validation
│   └── tests/            # pytest API/security/service/provider coverage
├── alembic/              # migration chain 0001_initial_schema → 0015_rls_public_tables
├── tests/                # auth, models, migrations, model/artifact tests
├── test_phase2_services.py  # standalone service checks
├── smoke_e2e.py          # live-server E2E walk (writes synthetic records)
└── requirements.txt      # FastAPI/SQLAlchemy/Alembic, crypto/httpx, ML, pypdf, test deps
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
├── games/                    # game_analytics_engine.dart (pure Dart metrics/hint calculator;
│                             # server owns difficulty), game_labels.dart, game_visuals.dart
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
├── lib/main.dart             # shell, API client, role/permission-driven views, audit pagination
├── lib/config.dart           # API_BASE_URL validation; explicit URL required in release
├── lib/widgets/              # risk screening/intake, RAG upload/picker, Monad components
└── lib/theme/monad_theme.dart  # Monad tokens (copy of mobile's, minus game tints)
```

### Other
```
DESIGN.md                     # Monad style reference — the token source of truth both
                              # monad_theme.dart files mirror
demo-seed/documents/          # 3 synthetic RAG demo docs (discharge summary, prescription, care plan)
backend/static/               # Monad-styled landing page served at /static
.github/workflows/ci.yml      # backend gates + mobile tests/analyze/codegen + dashboard VM/Chrome tests + web build
docker-compose.yml            # pgvector/pg16 + redis + backend (no dashboard container)
```

---

## Testing Strategy

- **Backend unit/API/security:** canonical command is
  `cd backend && python3 -m pytest app/tests tests -q` (`backend/pytest.ini`
  defines `app/tests tests`). It includes migration-head checks, access/consent
  matrices, audit success/failure behavior, RAG provenance/encryption/reindex,
  providers, games, reminders, retention, and sync.
- **Standalone:** `cd backend && python3 test_phase2_services.py`.
- **Live PostgreSQL smoke:** CI starts the API on a clean PostgreSQL 16 database
  after `alembic upgrade head` and runs `cd backend && python3 smoke_e2e.py`.
  The script creates synthetic records and does not clean them up.
- **Mobile:** `cd mobile && flutter test` after `flutter pub get`,
  `dart run build_runner build --delete-conflicting-outputs`, and
  `flutter analyze`. Live/integration tests remain opt-in and require a reachable
  backend/device.
- **Dashboard:** `cd dashboard && flutter test` for the VM suite,
  `flutter test --platform chrome` for browser-platform tests, and
  `flutter build web --release --dart-define=API_BASE_URL=https://api.example.org`
  for the release web build.
- **Counts:** do not copy pass totals into architecture documentation. CI output
  and the canonical commands are the reproducible source of truth.

**Demo database rule (2026-09-30 runbook):** the populated Homebrew database is
not a test fixture. Verify the documented system identifier and current revision,
take a fresh backup, and obtain explicit approval before any migration or source
restart. Never substitute the empty compose cluster for that preflight, and do
not casually run `alembic upgrade head` against the demo database.

---

## Remaining Work (reconciled 2026-09-25)

**Genuinely open / deferred:**
- Configure and validate real LLM/speech providers. The shipped default remains
  canned replies, heuristic embeddings, and simulated ASR/NMT/TTS.
- Complete physical-device validation for microphone capture, audio playback,
  notification permissions, and app lifecycle behavior.
- Implement a real notification transport. The current FCM class is an
  explicit log/failed-audit adapter and confirms no delivery; SMS/email are not
  implemented.
- Add in-progress game checkpoint/restore if exact resume after app death is a
  product requirement. Today only completed rounds/outbox items are durable.
- Add OCR only as a separately approved scope. Current uploads require selectable
  PDF text or a text-family file, and the scanned-PDF error says so explicitly.
- Add database-level audit immutability controls (restricted DB role plus
  trigger/grant/RLS policy and an operational append-only storage design) if
  tamper resistance is required. Application retention exclusion is not enough.
- Operate the RAG reindex workflow for legacy/provenance-mismatched documents and
  establish a controlled backfill for any legacy plaintext source text.
- Commission game art/audio where desired; existing Material/icon fallbacks keep
  the games usable.
- Keep `monad_theme.dart` copies synchronized manually or introduce a shared
  package; mobile includes game-only tint extensions.
- Deeper dashboard drill-down (per-event reminder history, alert timelines),
  v2 ML activation, wearables, and dementia-friendly modes remain future work.

---

## Compliance Verification

**Implemented and tested:**
- Active consent scope gates (`ensure_consent`) and patient-owner consent grants.
- Patient-link, role, and clinical-tier enforcement with no direct client table
  access.
- Retention maintenance and revoked-consent deletion after the grace period.
- Broad read-audit and representative write-audit rows, with explicit best-effort
  and fail-closed tests. Rows are retained by application policy but are **not
  database-immutable**.
- Fernet field encryption for symptom/document/chunk PHI plus bcrypt password
  hashing.
- Patient export with a fail-closed export-audit precondition.
- Medical-document ingest/reindex with encrypted chunks, embedding provenance
  checks, and an audited plaintext-chunk migration path.

**Deployment responsibilities still open:**
- TLS termination, encrypted backups/restores, key rotation, database credential
  hardening, database-level audit append-only controls, and monitoring/alerting
  are infrastructure/operator work; FastAPI does not enforce them by itself.
- Guardian/joint consent workflows are not implemented even though related enum
  values exist.

Implementation is enforced across routes and regression-tested in the access,
consent, audit-failure, migration, RAG-integrity, and provider suites.

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

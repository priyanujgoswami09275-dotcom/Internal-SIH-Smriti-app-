# Smriti — Cognitive Gaming and Memory Assistance Platform

**SIH26003** — an experimental cognitive-care platform for elderly patients,
families, ASHA workers, and clinicians in India's North Eastern Region (NER).

Smriti combines four cognitive games, multilingual text/voice flows, health
reminders, document-grounded RAG, and a role-aware caregiver dashboard on one
FastAPI backend. It is a research prototype, not a diagnostic device, and makes
no claim to diagnose, treat, cure, or prevent dementia.

## Implemented surfaces

### Patient mobile app (`mobile/`)

- **Match It** — NER-themed memory matching with server-configured 2/4/6-pair
  levels.
- **Routine Sequencing** — 3/4/6-step daily-routine ordering.
- **Number Recall** — 3/4/6-digit sequences. Word Recall is not implemented.
- **Odd-One-Out** — server-scored semantic-category boards with an offline cached
  public-board path.
- Online completions return an authoritative rule-based `recommended_level`.
  The client analytics engine computes metrics/tags/hints but does not choose the
  next difficulty.
- Local notifications schedule reminder times. A completed offline round or
  reminder acknowledgment can enter an account-scoped durable replay outbox.

An in-progress round is not checkpointed. After app/process death, play restarts
from bundled/generated data or a compatible cached board rather than resuming
the exact board and moves.

### Caregiver dashboard (`dashboard/`)

Flutter Web, separate from the mobile app and split across `lib/main.dart`,
`lib/config.dart`, theme code, and focused widgets. It provides:

- JWT login, single-flight refresh, persisted web session, and logout revocation.
- Patient roster and role/permission-tier-driven metric, trend, alert, risk, and
  document controls; the backend remains authoritative.
- A `health_data` consent preflight before risk screening or document upload.
- Reminder schedule add/remove and risk-screening intake for permitted roles.
- An admin-only audit viewer with 50-row offset pagination.
- A release configuration guard: release builds require an explicit absolute
  `API_BASE_URL`; debug/development defaults to `http://localhost:8000`.

### Backend and document RAG (`backend/`)

FastAPI, SQLAlchemy 2, Alembic, and PostgreSQL expose the only data path used by
the clients. Current Alembic head: `0014_reminder_idempotency`.

Medical-document support includes selectable-text PDF and text-family upload,
overlapping chunks, embedding provider/model/dimension provenance checks, cited
retrieval, extractive fallback without an LLM, and Fernet encryption of source
text and every new chunk. If a stored document has missing or mismatched
embedding provenance, retrieval refuses to score it and directs an operator to:

```sh
cd backend && python -m app.services.rag_service reindex \
  --patient-id <patient-uuid> --actor-id <operator-user-uuid>
```

Reindex is patient-scoped and idempotent, backfills provenance, recomputes
vectors, converts legacy plaintext chunk rows to ciphertext, and writes a
`rag_reindex` audit row for changed documents.

**OCR is not available in this build.** A scanned/image-only PDF is rejected
before persistence with guidance to paste the content into a text file or use a
text-layer PDF. A scanner plus OCR would require a separately approved mobile
scope and new native dependencies.

## Connectivity and durability

The app is offline-capable, not universally offline-first:

- Match It, Routine Sequencing, and Number Recall can start from bundled/local
  data; Odd-One-Out needs a previously cached compatible board.
- Level config and public Odd-One-Out board snapshots persist in
  `SharedPreferences`.
- Completed offline sessions/actions and reminder acknowledgments use a drift
  SQLite outbox. Rows carry patient and account IDs; replay selects only the
  active account. Logout stops replay but does not delete pending rows.
- Failed replay remains pending with retry/error state. Document upload and
  clinical reads are not queued offline.
- Reminder audio is cached by text + language in temporary files; the cache is a
  performance aid, not a clinical record.

## Language and speech

The product picker lists Assamese, Bengali, Hindi, English, Mizo, Meitei
(Manipuri), Khasi, Bodo, Garo, and Nepali. Garo has no provider mapping and is
always disabled. `meitei` aliases canonical `manipuri`.

| Provider | ASR | NMT | TTS | Notes |
|---|---|---|---|---|
| Sarvam | Assamese, Bengali, Hindi, English, Manipuri/Meitei, Bodo, Nepali | Same seven | Bengali, Hindi, English | Requires `SARVAM_API_KEY`; Khasi/Mizo/Garo unsupported |
| AI4Bharat | Assamese, Bengali, Bodo, Manipuri/Meitei, Nepali, Hindi, English | Same seven | Same seven | Requires a dedicated Hugging Face endpoint; default router does not serve these models |
| Bhashini ULCA | Assamese, Bengali, Hindi, English, Manipuri/Meitei, Bodo, Nepali, Mizo, Khasi | Same nine | Same nine | Requires `BHASHINI_API_KEY` and `BHASHINI_USER_ID`; Garo unsupported |
| Mock | Picker languages, simulated | Picker languages, simulated | Picker languages, simulated | Default when no provider credentials are configured |

The shipped `.env.example` contains no speech-provider credentials, so `auto`
selects deterministic mock speech by default. Mock ASR/NMT/TTS is not live speech
validation. Physical-device microphone, speaker, and notification behavior is
not yet validated.

Reminder schedules use daily wall-clock grammar:
`[daily|everyday|every day][@|at|:]? HH:MM[,HH:MM;HH:MM]...`; legacy
`HH:MM AM|PM Daily` is accepted. Notification transport is not configured by
default. Escalation APIs explicitly return `delivery_state: not_configured` and
zero confirmed deliveries rather than claiming a recipient was notified.

## Access model

Clients use REST requests with JWT bearer tokens. There is no Supabase client,
Firebase table SDK, client-side anon table credential, or service-role key in
the mobile/dashboard apps. The FastAPI app layer enforces:

- active patient ownership or caregiver/staff access;
- consent purpose scope (`game_data`, `health_data`, `voice_companion`);
- role checks and `basic`/`clinical` permission tiers;
- fail-closed consent grant/revoke, document ingest/reindex, and export-audit
  paths.

Direct client database access is not part of this design. Enabling it later
would require publishable-only credentials, per-table/per-operation RLS,
authenticated JWT claim propagation, tenant/patient/consent scoping, session and
revocation handling, new migrations/tests, and proof that no privileged service
secret can reach a client.

## Architecture

```text
Flutter mobile (drift/offline outbox) ─┐
                                        ├─ HTTPS/REST + JWT ─ FastAPI ─ PostgreSQL
Flutter caregiver dashboard (web) ─────┘                     └─ optional providers
```

| Layer | Current technology |
|---|---|
| Mobile | Flutter/Dart, drift/SQLite, local notifications, `http` |
| Dashboard | Flutter Web/Dart, `shared_preferences`, `http` |
| Backend | FastAPI, SQLAlchemy 2, Alembic, Pydantic settings |
| Database | PostgreSQL; RAG vectors currently use a JSON column |
| Cache/rate limit | Redis with in-process fallback |
| Auth | Short-lived access JWT + 7-day single-use rotating refresh token |
| LLM | OpenRouter default, Anthropic alternative, deterministic fallback |
| Speech | Sarvam / AI4Bharat / Bhashini / mock |
| Embeddings | Deterministic heuristic default, local sentence-transformers, OpenAI |

## Local development

Prerequisites:

- Flutter stable with Dart 3 support
- Python 3.12
- PostgreSQL 16 (a clean disposable database for tests/migrations)
- Chrome for dashboard browser tests

Install and run the backend from `backend/`:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m uvicorn app.main:app --reload
```

The repository-root `.env` and optional `backend/.env` are operator-managed.
Never commit or print them. Start from `.env.example` and supply real secrets
outside version control.

Run the dashboard from `dashboard/`:

```sh
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
flutter build web --release --dart-define=API_BASE_URL=https://api.example.org
```

Run the mobile app from `mobile/`:

```sh
flutter pub get
flutter run -d SERIAL --dart-define=API_BASE_URL=http://localhost:8000
```

For an Android emulator without `adb reverse`, use
`--dart-define=API_BASE_URL=http://10.0.2.2:8000`. See `DEPLOYMENT.md` for the
demo-database preflight and migration warning.

## Verification commands

```sh
cd backend && python3 -m pytest app/tests tests -q
cd backend && python3 test_phase2_services.py
cd mobile && flutter test
cd dashboard && flutter test
cd dashboard && flutter test --platform chrome
```

`cd backend && python3 smoke_e2e.py` is a live smoke walk that writes synthetic
records. Never point it or `alembic upgrade head` casually at the populated demo
or production database. CI applies migrations to a clean PostgreSQL 16 service
before running the smoke walk.

## Compliance boundaries

The audit trail has broad read coverage and tested representative write rows.
Most read/write helpers are best-effort; consent changes, document
ingest/reindex, and export are fail-closed. Application retention excludes audit
rows, but **database-level immutability is not enforced**—a privileged SQL actor
can currently update or delete an audit row. TLS termination, encrypted
backups/restores, key rotation, database-role hardening, and append-only database
controls remain deployment/operator responsibilities.

See `CLAUDE.md` for the reconciled source of truth and `DEPLOYMENT.md` for the
authoritative demo and deployment runbook.

# Smriti — AI-Powered Cognitive Gaming and Memory Assistance Platform

**SIH26003** — an experimental cognitive-care platform for elderly patients,
families, ASHA workers, and clinicians in India's North Eastern Region (NER).
It is a research prototype, not a diagnostic device, and makes no claim to
diagnose, treat, cure, or prevent dementia.

**Empowering elderly dementia patients in the North Eastern Region through adaptive cognitive care.**

Smriti — Reviving Memories, Restoring Smiles.

---

## 🧠 About the Project

The North Eastern Region (NER) is witnessing a gradual rise in age-related cognitive disorders such as dementia and memory loss among the elderly population. Many families in remote and rural areas face challenges accessing specialized neurological care and cognitive therapy due to limited healthcare infrastructure and geographical barriers.

**Smriti** is an AI-powered cognitive gaming and memory assistance platform built specifically for elderly dementia patients in NER. It combines adaptive cognitive games, a voice-guided multilingual companion, health reminders, document-grounded RAG, and a caregiver monitoring dashboard — all designed to work reliably even in low-connectivity, remote environments.

Our goal is to make cognitive care accessible, affordable, and culturally familiar for elderly users who have historically been left out of digital healthcare solutions.

---

## ✨ Key Features

### 1. Cognitive Games
- **Match It** — A memory-matching card game themed with NER-relevant imagery (local festivals, food, attire, animals) instead of generic visuals
- **Daily Routine Sequencing** — Patients arrange everyday activities in correct order, doubling as both engagement and an early cognitive assessment tool
- **Number/Word Recall** — Patients remember and sequence numbers/words
- **Odd-One-Out** — A culturally themed board where the odd item is held server-side so the answer never reaches the client
- Difficulty is assigned by the server's rule-based authority (`game_level_config` is the single source of truth across backend and mobile); the app never promotes a patient on its own. Accuracy bands (85% → bump, 50% → drop) are evaluated server-side and returned as `recommended_level`.

### 2. Caregiver Dashboard
- Flutter Web: real-time view of patient activity, game scores, and performance trends
- Reminder compliance tracking (medicine, water, food, exercise)
- Risk alerts for signs of cognitive decline or missed routines
- Multi-patient support for ASHA/health workers managing several patients
- `basic` (family) and `clinical` (ASHA/clinician/admin) permission tiers; clinical detail is server-gated

### 3. Reminders
- Scheduled reminders for medicine, hydration, meals, and exercise, with voice playback on the acknowledgment screen
- On-device notifications are scheduled locally and reconciled against the server schedule on every fetch
- Acknowledgment is honest about where it was stored: saved to the care record, queued for sync, or not saved
- Escalation APIs return `delivery_state: not_configured` and zero confirmed deliveries while no notification transport is configured — the app never claims a relative was notified

### 4. Voice Companion
- Friendly conversational assistant guiding patients through the app
- Daily emotional wellbeing check-ins ("How are you feeling today?")
- Reduces reliance on reading/typing for navigation
- 10-language picker (provider-gated): assamese, bengali, hindi, english, mizo, manipuri, khasi, bodo, nepali; garo always renders as "not yet available"
- ASR (server-side) → LLM (reasoning) → TTS (patient's language); speech chain degrades gracefully when providers are unconfigured

### 5. Text-to-Speech & Speech-to-Text
- Converts app content into spoken audio and accepts voice input
- Powered by a multi-provider chain: Sarvam AI primary, AI4Bharat/Bhashini fallback
- Unsupported languages surface as "not yet available" — the UI never offers a language that fails when selected
- With no provider credentials configured, `auto` selects deterministic mock speech; that is simulated speech, not live-speech validation

### 6. Multilingual Support (NER Languages)
- Companion picker with 10 NER languages (assamese, bengali, hindi, english, mizo, manipuri, khasi, bodo, nepali, garo)
- Provider chain gating: some entries render "not yet available" when the active provider does not cover them
- All API responses accept `?language=assamese` parameter
- Mobile stores preferred_language per user; companion chat uses provider-gated 10-language picker
- Cultural content tied to selected language

### 7. Offline Support
The app is offline-capable, not universally offline-first. See
[Connectivity and durability](#connectivity-and-durability) for the exact
guarantees; the short version:

- Match It, Routine Sequencing, and Number Recall can start from bundled/local data; Odd-One-Out needs a previously cached compatible board
- Completed offline sessions/actions and reminder acknowledgments use a drift SQLite outbox and replay on reconnect, scoped to the signed-in account
- Document upload and clinical reads are not queued offline; failed replay stays pending with retry/error state
- In-progress game rounds are memory-only and are not resumed after app death

---

## 🏗️ System Architecture

```
┌─────────────────────────┐
│   Patient Mobile App      │  Flutter | Offline-capable
│  (Games, Voice, Reminders)│
└───────────┬──────────────┘
            │ Local storage (drift SQLite)
            ▼
┌─────────────────────────┐
│   FastAPI Backend         │  Python | PostgreSQL
│  (REST API, risk-screening, difficulty, compliance)│
└───────────┬──────────────┘
            │ REST API
            ▼
┌─────────────────────────┐
│   Caregiver Dashboard      │  Flutter Web
│ (Trends, alerts, logs)     │
└─────────────────────────┘
```

Flutter clients never hold database credentials: they talk only to the FastAPI
API over HTTPS with a JWT.

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Patient App** | Flutter (Dart) |
| **Local Storage** | drift SQLite (offline store) |
| **Backend** | FastAPI + SQLAlchemy + Alembic + PostgreSQL |
| **AI/ML** | Python — OpenRouter (free-tier) for language reasoning; scikit-learn risk-screening baseline (experimental, separate from gameplay decisions) |
| **Speech** | Sarvam AI primary, AI4Bharat/Bhashini fallback, deterministic mock when unconfigured |
| **Auth** | JWT (access + refresh with single-use rotation and token typing) |
| **Notifications** | console (logs + records delivery attempts) |
| **Offline Sync** | drift SQLite outbox + HTTP replay |
| **RAG Embeddings** | heuristic (deterministic md5-TF) by default, with embedding provenance checks |

---

## 📱 Target Users

- **Elderly dementia patients** in rural and remote NER areas
- **Family caregivers** seeking remote visibility into a loved one's cognitive health
- **ASHA and health workers** managing multiple elderly patients across villages
- **Healthcare institutions** in NER looking to extend cognitive care to underserved populations

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK >= 3.x
- Python >= 3.12
- PostgreSQL 16 (Homebrew `localhost:5432/eldercare`, system identifier `7681754862742343790`)
- Android Studio / Xcode for mobile builds (optional; CI builds in container)

### Running locally (September 30 demo)

**Do not use `docker compose up` for the demo.** The demo backend runs against
the populated Homebrew PostgreSQL at `localhost:5432/eldercare` (system
identifier `7681754862742343790`) — not the separate, empty compose cluster. Do
not reseed or reset the demo database.

Full runbook — including the `.venv-demo` Python 3.12 environment, the cluster
preflight check, and the `ENABLE_BACKGROUND_JOBS=false` baseline — is in
**[DEPLOYMENT.md → "Run — September 30 demo"](DEPLOYMENT.md)**. Mobile:
`cd mobile && flutter pub get`, then on a device/emulator run
`adb -s SERIAL reverse tcp:8000 tcp:8000` and
`flutter run --debug -d SERIAL --dart-define=API_BASE_URL=http://localhost:8000`
(Android emulators reach the host via `http://10.0.2.2:8000` instead).

To point the backend at Supabase Cloud Postgres instead, set `DATABASE_URL` in
the gitignored root `.env` (see `.env.example` for the pooler/session-mode
shape) and export it for Alembic, which reads the process environment rather
than the file.

### Release builds (both clients)

A release build must be told where the API lives, and it must be a real public
HTTPS address:

```sh
# mobile
cd mobile && flutter build apk --release --dart-define=API_BASE_URL=https://api.example.org
# dashboard (web)
cd dashboard && flutter build web --release --dart-define=API_BASE_URL=https://api.example.org
```

Both clients **refuse to compile** a release build when the URL is missing, uses
`http://`, or points at loopback/a private address. Debug and `flutter run`
keep their localhost defaults. A public tunnel (Cloudflare/ngrok) works for a
demo because it is HTTPS, but its URL is temporary — pass it at build time for
the session you need and never bake it into the source.

Android release signing reads `mobile/android/key.properties` when present
(gitignored). Without it the APK is signed with the Android debug key, which is
fine for sideloading a demo but not for a store upload.

---

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
default.

## Database and access model

The backend persists to PostgreSQL, in production a managed Supabase project
reached over the pooler. The schema is built **only** by
`alembic upgrade head`; there is no hand-applied DDL. The current head is
`0015_rls_public_tables`, which enables row-level security on every application
table and creates no policies — so a role that somehow obtained a table
`GRANT` still reads zero rows. The API connects as the table owner and is the
single authorization point.

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

## Document RAG

Text PDF and plain-text documents upload per patient with `health_data` consent
and staff role. Chunks are embedded with a recorded provider/model/dimension
provenance, source and chunk text is encrypted at rest, and answers cite their
chunks. Uploading a document whose embedding space differs from the configured
one is rejected (HTTP 409) rather than silently mixed. `python -m
app.services.rag_service reindex` re-embeds an existing corpus; it does not
re-chunk legacy documents. Image-only PDFs are rejected because this build has
no OCR.

---

## 📊 Project Status

- [x] Problem research and requirement analysis
- [x] Tech stack finalization
- [x] Cognitive games (Match It, Daily Routine Sequencing, Number/Word Recall, Odd-One-Out) — built + tested
- [x] Voice companion + multilingual pipeline — built + tested (emulator/macOS only; physical-device validation pending)
- [x] Multilingual support (10 NER languages in companion picker, provider-gated) — built + tested
- [x] Offline sync implementation (drift SQLite outbox + HTTP replay) — built + tested
- [x] Caregiver dashboard (Flutter Web, JWT-gated, permission tiers) — built + tested
- [x] Server-authoritative game integrity (answer secrecy, server scoring, idempotent start/actions/complete, rule-based difficulty progression) — built + tested
- [x] Document-grounded RAG with embedding provenance and encrypted chunks — built + tested
- [ ] Physical-device voice validation — emulator/macOS only, outstanding
- [ ] Live API keys for Sarvam / AI4Bharat / Bhashini / OpenRouter — everything degrades gracefully when absent
- [ ] Risk-screening model: experimental / not clinically validated (separate ML system from gameplay decisions)
- [ ] Difficulty model remains shadow-mode only; rules sole authority for real decisions
- [ ] OCR for scanned documents — out of MVP scope; image-only PDFs are rejected honestly
- [ ] Real notification transport (SMS/FCM/email) and resumable in-progress rounds

---

## Verification commands

```sh
cd backend && python3 -m pytest app/tests tests -q
cd backend && python3 test_phase2_services.py
cd mobile && flutter test
cd dashboard && flutter test
cd dashboard && flutter test --platform chrome
```

`cd backend && smoke_e2e.py` is a live smoke walk that writes synthetic
records. Never point it or `alembic upgrade head` casually at the populated demo
or production database. CI applies migrations to a clean PostgreSQL 16 service
before running the smoke walk.

## Compliance boundaries

The audit trail has broad read coverage and tested representative write rows.
Most read/write helpers are best-effort; consent changes, document
ingest/reindex, and export are fail-closed. Application retention excludes audit
rows, but **database-level immutability is not enforced** — a privileged SQL actor
can currently update or delete an audit row. TLS termination, encrypted
backups/restores, key rotation, database-role hardening, and append-only database
controls remain deployment/operator responsibilities.

---

## 🌍 Impact

- Improves cognitive well-being and quality of life for elderly dementia patients in remote NER areas
- Reduces caregiver burden through remote monitoring
- Supports early intervention research; the risk-screening model is experimental and not a claim about Smriti's outcomes
- Strengthens digital healthcare accessibility in an underserved region
- Low-cost, hardware-independent solution deployable on existing family devices

---

## 🎯 Smart India Hackathon 2026

This project is being developed for **Smart India Hackathon (SIH)** under the problem statement issued by the **Ministry of Development of North Eastern Region (MDoNER)**.

---

## 🙏 Acknowledgements

- Ministry of Development of North Eastern Region (MDoNER) for the problem statement
- Sarvam AI, AI4Bharat, Bhashini (National Language Translation Mission, Govt. of India) for multilingual voice infrastructure
- Smart India Hackathon for the platform and opportunity

See `CLAUDE.md` for the reconciled source of truth and `DEPLOYMENT.md` for the
authoritative demo and deployment runbook.

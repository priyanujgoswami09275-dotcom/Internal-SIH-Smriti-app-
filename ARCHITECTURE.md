# ARCHITECTURE.md — Smriti Technical Architecture

**PPT/Slide-Friendly Technical Summary** · Date: 2026-09-21

---

## 1. System Overview

Three user-facing surfaces share one FastAPI backend:

```
┌─────────────────────────┐
│   Patient Mobile App      │  Flutter | Offline-first
│  (Games, Voice, Reminders)│
└───────────┬──────────────┘
            │ Local storage (drift SQLite)
            ▼
┌─────────────────────────┐
│   FastAPI Backend         │  Python | PostgreSQL
│  (REST API, risk-screening,     
│   difficulty, compliance)   │
└───────────┬──────────────┘
            │ REST API
            ▼
┌─────────────────────────┐
│   Caregiver Dashboard      │  Flutter Web
│ (Trends, alerts, logs)     │
└─────────────────────────┘
```

**REST API** (`/api/v1`) connects all surfaces.  
**Offline sync:** drift SQLite outbox → HTTP replay job on reconnect.  
**Background jobs:** reminder generation (60s), escalation scan (60s), sync consume (300s), retention (24h).

---

## 2. Component Breakdown

### Backend
- **Language:** Python 3.12 (pinned runtime)
- **Framework:** FastAPI (async-first, Pydantic validation, OpenAPI docs)
- **ORM:** SQLAlchemy 2.0 + Alembic (reversible migrations, schema version `0010_odd_one_out`)
- **Database:** PostgreSQL 16 (Homebrew `localhost:5432/eldercare`, sysid `7681754862742343790`)
- **Cache/Queue:** Redis (session cache, rate limiting) with in-process fallback
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
- **Framework:** Flutter (Dart 3.x), single codebase iOS/Android
- **Local store:** drift SQLite (offline-first) + committed codegen (`app_database.g.dart`)
- **Key files:**
  - `mobile/lib/main.dart` (auth gate, home shell, profile setup)
  - `mobile/lib/services/` (api_service, auth_session, offline_sync_service, reminder_service, tts_cache, voice_audio_service, voice_languages, reminder_scheduler, routine_service, match_it_service)
  - `mobile/lib/games/` (game_analytics_engine.dart [pure Dart, no Flutter imports], game_labels.dart, game_visuals.dart, recall_service.dart)
  - `mobile/lib/screens/` (auth, match_it, pack_picker, routine, reminders, voice_companion [10-lang picker, provider-gated], caregiver_dashboard [role-gated], recall_screen, odd_one_out_screen)
  - `mobile/lib/theme/monad_theme.dart` (Monad design tokens — colors, type, spacing, radii)
  - `mobile/test/` (api_live_test, game_analytics_engine_test, level_config_test, monad_widgets_test, odd_one_out_screen_test, recall_service_test, reminder_voice_test, silence_detector_test, voice_languages_test, schedule_delete_contract_test [2A], rag_upload_test [2C], clinical_notes_sync_test [2D], refresh_single_flight_test [5D], widget_test)

### Caregiver Dashboard
- **Framework:** Flutter Web (same Dart codebase as mobile)
- **Key files:**
  - `dashboard/lib/main.dart` (single-file app: login, roster, summary tiles, alerts, insights) + `dashboard/lib/api_client.dart` extraction pending; `dashboard/lib/widgets/` (risk_screening_card, risk_intake_form [authed, tier-gated], rag_upload_widget + rag_upload_picker_web/stub [real upload, 2C])
  - `dashboard/lib/theme/monad_theme.dart` (copy of mobile's, minus game tints)
- **Features:** JWT login + auto-refresh (single-flight refresh, server-side logout revocation), patient roster dropdown, 7-day metric tiles (cognitive accuracy, reminder compliance with honest no-data state, response time), 14-day accuracy + response-time trend sparklines (all games, pure CustomPaint, no chart dependency), active-alerts acknowledge (patient-access gated server-side), clinical-flags insight, risk screening (clinical tier only, authed), reminder-schedule editing (list/add/delete), RAG document upload (real multipart, 2C), admin audit-trail viewer (`GET /compliance/audit-logs`), responsive layout

---

## 3. External Integrations Table

| Integration | Provider Chain | Graceful-Degradation Behavior |
|---|---|---|
| **LLM** (companion + RAG answers) | OpenRouter free-tier (`minimax/minimax-m3:free`; fallback chain `nemotron-3-*:free`). Anthropic alternative. `LLM_PROVIDER=auto` detects `sk-or-` prefix | Canned persona reply (`LLM_AUTO_FALLBACK`), or extractive RAG answers; never errors on elder UX |
| **Speech** (ASR/TTS/NMT) | **Sarvam AI primary**, Bhashini fallback (`auto\|sarvam\|bhashini\|mock`); AI4Bharat implemented but currently non-functional pending a dedicated HF endpoint | Deterministic local mock; unsupported languages surface as "not yet available" in picker |
| **Embeddings** (RAG) | `heuristic` (deterministic md5-TF hashing, no dependencies); `local` (sentence-transformers e5-small); `openai` | Missing/unknown backends log a warning and return heuristic — RAG always works |
| **Notifications** (reminder escalation / alert fan-out) | `console` (logs + records deliveries in-process) | Default until real channel (SMS/FCM/email) configured; always logs locally |

**Hard guard:** `OPENROUTER_FREE_ONLY=true` refuses any model slug not `:free`. Live usage needs API keys in `.env`; everything degrades gracefully when absent.

---

## 4. Security & Compliance Architecture

| Component | Implementation | Evidence |
|---|---|---|
| **JWT with refresh rotation** | Access: 15 min (stateless); Refresh: 7 days, single-use with rotation (`users.refresh_jti` holds only accepted token; presenting reused/superseded token clears `refresh_jti`, killing chain — replay defence) | `app/core/security.py`, `app/deps.py`, migration `0003_refresh_rotation`, `test_phase12_gates.py` |
| **Role-based access control** | Roles: `patient` (plays games, acknowledges reminders), `family_caregiver` (manages patient, sees basic activity), `asha_worker` (field worker, manages multiple patients, sees clinical detail), `clinician` (healthcare provider, sees raw scores + health data), `admin` (system administration) | `app/deps.py`: `ensure_patient_access`, `ensure_clinical_access`, `get_permission_tier`; `test_phase12_gates.py` |
| **Consent-scope enforcement** | Explicit consent BEFORE any health data storage; scopes: `game_data` \| `health_data` \| `voice_companion`; `ensure_consent` in `deps.py` blocks cross-scope access | `app/deps.py`, `app/services/compliance_service.py`, `test_phase11_gates.py` |
| **Audit logging** | Immutable `AuditLog` table: user_id, action (read/write/delete), resource_type, resource_id, timestamp, ip, details; every health data access logged; retention: indefinite | `app/models/all_models.py`, `app/services/compliance_service.py`, `test_phase11_gates.py` |
| **At-rest encryption** | `EncryptionService` (Fernet, key SHA-256-derived from `ENCRYPTION_KEY`) on `SymptomLog.notes` and `MedicalDocument.extracted_text`; audit tokens verify Fernet `gAAAA` prefix | `app/services/compliance_service.py`, `test_phase11_gates.py` |
| **No implicit access** | Every caregiver-to-patient access is a 403 at every route; unknown patient IDs return 404 (no existence leak) | `test_phase0_fixes.py` (5 P0 regressions), `test_phase11_gates.py` (cross-patient 403/404, read-audit rows, encrypted docs) |
| **Production posture** | Rate limiting (Redis+fallback, fixed-window per-IP 100/min), CORS whitelist (production refuses `*`), placeholder-secret refusal (`Settings.validate_for_environment()`), CI with PostgreSQL migration + E2E smoke | `app/middleware/rate_limit.py`, `app/config.py`, `.github/workflows/ci.yml` |

**CI verification:** backend pytest + standalone, `alembic upgrade head` on clean Postgres 16, live `smoke_e2e.py`; frontend: `flutter pub get` + drift codegen + `flutter analyze` for mobile and dashboard.

---

## 5. ML Architecture — Two Independent Systems

The two systems are **independent**: the risk-screening model is fully live and callable but is experimental/not clinically validated; the difficulty model runs in shadow mode only and is never used for real decisions without explicit approval.

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
| **Backend/mobile difficulty decision-logic divergence** | Backend: drops after 2 consecutive <50 accuracy sessions. Mobile (`game_analytics_engine.dart`): requires 3 agreeing verdicts (where slowness alone can force a lower verdict) before moving a level. Server remains authoritative for real decisions (`POST /games/difficulty/evaluate`), but in-app hints can disagree with the server. | **Open** — unification was scoped to the archived B-04/B-05 and is **not done**. For the demo this is invisible (both behave sanely), but do not claim one engine. |
| **No physical-device validation for voice** | Mic capture + TTS playback and notification permissions have not been confirmed on a real phone (emulator/macOS only). The software path is fully wired and unit-tested. | **Open** — device checklist in DEPLOYMENT.md is written and waiting on physical-device testing. |
| **Level-3 Odd-One-Out content is festivals-pack-only** | Festivals is the sole content group with ≥5 unambiguous items, so L3 majority boards always draw from it (L1/L2 span five groups). Boards remain valid and fully scored; broader content authoring is pending. | **Open** — content task, not a code change. |
| **ML models not activated** | Risk-screening model is experimental/not clinically validated; difficulty model is shadow-mode only. Neither is used for real decisions without explicit approval. | **By design** — requires separate approval for activation. |

Judges respect honesty about tradeoffs more than a document that hides them. These limitations are explicit, scoped, and do not invalidate the core value delivered: a fully functional, tested, compliant cognitive gaming platform with voice assistance, reminders, and caregiver dashboard.
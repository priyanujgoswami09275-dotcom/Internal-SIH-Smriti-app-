# Deployment — SIH26003 Elder-Care Companion (2026-09-06)

## Status
- All 12 phases implemented (CLAUDE.md reconciliation).
- 130 pytest pass + 1 skipped (pypdf env); 21/21 standalone service tests.
- CI: pytest + alembic + smoke_e2e (Postgres 16) + flutter pub/get/analyze.
- Production posture: secret/CORS refusal (config.py:149-158), rate limit (Redis+fallback), Fernet encryption, audit logs.

## Pre-deploy checklist (must complete before flip to production)
1. Generate real SECRET_KEY (>=24 chars) and ENCRYPTION_KEY (>=16 chars).
2. Set CORS_ORIGINS to real origins (not *); ENVIRONMENT=production.
3. Add OPENROUTER_API_KEY / BHASHINI_API_KEY / ANTHROPIC_API_KEY (opt-in).
4. Provision managed Postgres (pgvector) + run `alembic upgrade head`.
5. Set TLS 1.2+ in front (load balancer / reverse proxy).
6. Configure real notification channel (SMS/FCM/APNs) beyond console.
7. Clean build artifacts (mobile/build, .dart_tool; backend/.venv) and refresh graph (`graphify update .`).

## Run
```
docker-compose up -d  # dev shape; swap to managed DB + TLS for prod
python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Source of truth: CLAUDE.md (reconciled 2026-09-06); the Phase 6 results below supersede the historical test counts above.

## Upgrade regression checkpoint — 2026-09-17

- Backend: `python3 -m pytest app/tests tests -q` — 184 passed, 3 skipped, 8 warnings.
- Standalone services: `python3 test_phase2_services.py` — 21 passed.
- Mobile: `flutter test` — 54 passed, 5 live-API tests skipped.
- Mobile: `flutter analyze` — 45 findings (5 warnings, 40 informational, 0 errors); not a clean analyzer gate.
- Live API: `NO_PROXY=localhost,127.0.0.1 python3 smoke_e2e.py` — 50 passed, 0 failed against the local PostgreSQL-backed server.
- Backend warnings include a scikit-learn serialized-estimator version mismatch; passing tests do not establish clinical model validity.
- Physical microphone, speaker, notifications, and visual walkthrough remain unverified. This checkpoint is not production or clinical sign-off.

### Migration recovery and repeatable commands

The local database was stamped at `0003`, had `clinical_features` already, and lacked notification and level-config tables. Revision `0005` was shortened to `0005_clinical_intake` to fit Alembic's 32-character version column; its upgrade now preserves an existing clinical-features column. Regression tests cover revision-chain resolution, revision length, column creation, and preservation of existing JSON data.

An initial stamp skipped notification DDL; the failed downgrade rolled back. Recovery then applied the missing `0004` notification DDL transactionally and reconciled the version to `0007_number_recall`, retaining existing patient and level-config data. Do not reproduce the blind stamping/downgrade attempts. Inspect actual schema before reconciling a drifted database. Databases with an expanded version column that previously stored the old long revision need explicit reconciliation before using this renamed chain. On the standard 32-character column, that stamp fails transactionally; inspect the retained version rather than assuming an empty row. Downgrading through `0005` drops `clinical_features`, including data that predated the migration: do not use that downgrade on a drifted database without a backup and explicit data-loss approval.

Run from `backend/` to use the same database settings as the application without printing credentials:

```sh
python3 -c 'import os; from app.config import settings; from alembic.config import Config; from alembic import command; os.environ["DATABASE_URL"] = settings.DATABASE_URL; command.current(Config("alembic.ini"))'
python3 -c 'import os; from app.config import settings; from alembic.config import Config; from alembic import command; os.environ["DATABASE_URL"] = settings.DATABASE_URL; command.upgrade(Config("alembic.ini"), "head")'
python3 -m pytest app/tests tests -q
python3 test_phase2_services.py
NO_PROXY=localhost,127.0.0.1 python3 smoke_e2e.py
```

Back up a populated database before applying migrations. The smoke script creates synthetic accounts, patients, consent and game records, and activates companion configuration `1.1.0`; use a disposable/demo database, never production. It does not clean up those records. It does not test Number Recall gameplay, ASR/TTS playback, real notification delivery, or device offline replay. A clean-database upgrade was not exercised in this local checkpoint.

### Manual walkthrough — pending device execution

Use synthetic data only, an attached Android device, a reachable backend, and an authenticated patient with consent plus a linked caregiver.

- [ ] Login and confirm patient/caregiver navigation and language preference.
- [ ] Match It: verify levels 1/2/3 use 2/4/6 pairs; finish a session and inspect persisted history.
- [ ] Routine: verify 3/4/6 steps and icons at every level. Known limitation: level 2 advertises hints but items lack hint text.
- [ ] Number Recall: verify 3/4/6 digits, timed display, correct and incorrect taps, completion, and persisted session results.
- [ ] Voice: record two Assamese and two English phrases; verify permission handling, silence stop, transcription, reply audio, stop control, and navigation cleanup. Do not present mock responses as real speech-provider validation.
- [ ] Reminders: create a due event; verify one automatic playback per screen opening, replay/stop, no replay on refresh, and stop on acknowledgment/navigation.
- [ ] Replay a cached reminder offline; try an uncached phrase offline and confirm readable text with no crash.
- [ ] Check caregiver roster/history reflects the patient actions; verify restricted clinical information is not exposed to a basic caregiver.
- [ ] Revoke consent on a disposable test patient and confirm subsequent health/game operations are rejected.

### Five-minute demo script

1. **0:00–0:30 — Context:** “Smriti supports elder routines, cognitive activities, and caregiver visibility; it is not a diagnostic tool.” Show the patient home screen.
2. **0:30–1:30 — Activities:** Play a short Match It round, show routine icons, and demonstrate Number Recall. Explain that server configuration controls levels and promotion requires three qualifying sessions.
3. **1:30–2:30 — Voice:** Use one rehearsed Assamese phrase, then English. Show transcription and audible reply only after real-device validation; otherwise explicitly demonstrate the text fallback.
4. **2:30–3:30 — Reminders:** Open a due reminder, hear it once, replay/stop, acknowledge, then show cached playback or graceful text fallback without connectivity.
5. **3:30–4:30 — Caregiver:** Switch to the linked caregiver and show the resulting activity and reminder state. Do not claim unverified push/SMS delivery.
6. **4:30–5:00 — Boundaries:** Explain consent controls, provider/network fallbacks, and remaining device checks. Keep multiplayer, family media upload, PDF export, personalization, snooze, quiet hours, and adherence timing out of this demo.
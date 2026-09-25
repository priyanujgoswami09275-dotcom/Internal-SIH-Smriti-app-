# Deployment — SIH26003 Elder-Care Companion (reconciled 2026-09-25)

## Status
- All 12 phases have implementation coverage; `CLAUDE.md` is the reconciled source of truth for current behavior and limitations.
- Canonical backend verification (run from `backend/`): `python3 -m pytest app/tests tests -q`. Do not copy a historical pass count into the runbook; use the current command/CI output.
- Standalone services: `python3 test_phase2_services.py`.
- CI keeps the backend pytest/standalone gates, applies `alembic upgrade head` to a clean PostgreSQL 16 service, and runs `smoke_e2e.py` against that service. It also runs mobile dependency/codegen/analyze/unit-test gates and dashboard VM tests, Chrome-platform tests, and a release web build.
- Production posture: app-layer JWT/RBAC/consent, production secret/CORS refusal, Redis-backed rate limiting with fallback, Fernet field encryption, and broad audit coverage. Audit rows are retained by application policy but database-level immutability is not enforced.

## Pre-deploy checklist (must complete before flip to production)
1. Generate real SECRET_KEY (>=24 chars) and ENCRYPTION_KEY (>=16 chars).
2. Set CORS_ORIGINS to real origins (not *); ENVIRONMENT=production.
3. Add OPENROUTER_API_KEY / BHASHINI_API_KEY / ANTHROPIC_API_KEY (opt-in).
4. Provision managed PostgreSQL, take/verify a backup, inspect the current revision, review the migration plan, and obtain approval before `alembic upgrade head`. The current single head is `0014_reminder_idempotency`.
5. Set TLS 1.2+ in front (load balancer / reverse proxy).
6. Configure real notification channel (SMS/FCM/APNs) beyond console.
7. Clean build artifacts (mobile/build, .dart_tool; backend/.venv) and refresh graph (`graphify update .`).

## Remote HTTPS access (cloud DB + real phones) — 2026-09-24

Target architecture: `Flutter → HTTPS → FastAPI → Supabase PostgreSQL`.
The backend is fully env-configured — no source changes are needed to expose it
remotely. Two supported paths:

### A. Quick tunnel (verified working 2026-09-24)

Runs the existing local uvicorn behind a public HTTPS URL; zero account, zero
cost. Chosen because the repo already anticipates it (`app_config.dart`
documents a tunnel `API_BASE_URL`) and no cloud-host credentials were available.

```sh
# 1. Backend must be running (Supabase DATABASE_URL from repo-root .env):
ENABLE_BACKGROUND_JOBS=false python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
# 2. Public HTTPS endpoint:
cloudflared tunnel --url http://localhost:8000 --no-autoupdate
#    → prints https://<random-words>.trycloudflare.com
```

Verified through the tunnel against Supabase: /health, CORS preflight,
register/login, patient access (consent + clinical link), game session +
complete, history, stats, adaptive shadow (`insufficient_history → predicted`),
risk screening POST/GET (38/38 checks). Flutter connects with
`--dart-define=API_BASE_URL=https://<random-words>.trycloudflare.com`
(HTTPS, so release builds work TLS-only; no cleartext flag needed).

Limits: URL rotates per tunnel start; uptime tied to this machine/process.
Good for phone testing and the demo; not a durable production host.

### B. Durable host (Docker) — ready, needs an account/service

`backend/Dockerfile` is deployment-ready: python:3.12-slim, pinned deps
(incl. `scikit-learn==1.6.1` matching the shadow artifact, `joblib==1.6.0`),
uvicorn on 0.0.0.0:8000, `ml_models/` ships in the image. Works on any
Docker-capable host (Render/Railway/Fly/VPS). Required environment variables:

- `DATABASE_URL` — Supabase pooler, `postgresql+psycopg://postgres.<ref>:<pw>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require` (percent-encode the password)
- `SECRET_KEY`, `ENCRYPTION_KEY` — real values (≥24 / ≥16 chars)
- `ENVIRONMENT=production` — enables rate limiting; refuses placeholder secrets
- `CORS_ORIGINS` — comma-separated whitelist (required, `*` refused in production); native Flutter needs no CORS, Flutter **web** dashboard origin must be listed
- `ADAPTIVE_SHADOW_MODEL=bootstrap.joblib` (keep shadow-only; rules stay authoritative)
- Optional provider keys (OPENROUTER/BHASHINI/…) as needed
- Run `python -m alembic upgrade head` once with `DATABASE_URL` exported (process env, not .env)

UTC handling (`options=-c timezone=UTC`, naive-UTC writes) is env-independent
and unchanged on any host.

## Run — September 30 demo (authoritative)

The demo runs against the **populated Homebrew PostgreSQL cluster on the host**:
`localhost:5432/eldercare`, system identifier `7681754862742343790`, holding the
existing **13 patients and 10 documents**. Do **not** run
`docker compose up` for the demo — the compose Postgres (`192.168.23.25:5432`,
system id `7682040204916105254`) is a separate, empty cluster. Do **not** reseed
or reset the demo database.

### One-time environment setup (from `backend/`)

Create a durable Python 3.12 virtualenv named `.venv-demo` (do not reuse the
existing `.venv`, which is Python 3.14 and for tests):

```sh
python3.12 -m venv .venv-demo
.venv-demo/bin/pip install -r requirements.txt
.venv-demo/bin/pip check
```

### Configuration

If an operator-managed repo-root `.env` exists, pydantic loads it; an optional
`backend/.env` and exported environment variables override it (precedence:
exported variables > `backend/.env` > root `.env`). Never commit `.env`, source
it in shared logs/CI, or print/echo its contents. Start from `.env.example` and
inject real secrets through the deployment secret manager.

### Preflight — verify the target cluster before starting anything

Run from `backend/` using the demo venv. This asserts host/port/db and the actual
system identifier via SQLAlchemy, and reports row **counts only (no PHI)**:

```sh
.venv-demo/bin/python - <<'PY'
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from app.config import settings

url = make_url(settings.DATABASE_URL)
assert (url.host, url.port, url.database) == ("localhost", 5432, "eldercare"), (
    f"wrong cluster: host={url.host} port={url.port} db={url.database}")
engine = create_engine(settings.DATABASE_URL)
with engine.connect() as conn:
    sysid = conn.execute(text("SELECT system_identifier FROM pg_control_system()")).scalar()
    assert sysid == 7681754862742343790, f"wrong cluster sysid: {sysid}"
    patients = conn.execute(text("SELECT count(*) FROM patients")).scalar()
    docs = conn.execute(text("SELECT count(*) FROM medical_documents")).scalar()
print(f"OK: eldercare sysid={sysid} patients={patients} documents={docs}")
PY
```

Expected output: `OK: eldercare sysid=7681754862742343790 patients=13 documents=10`.
If the system identifier differs, you are pointed at the wrong cluster — stop.

### Start the backend (demo baseline)

```sh
ENABLE_BACKGROUND_JOBS=false .venv-demo/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
```

`ENABLE_BACKGROUND_JOBS=false` is the explicit demo baseline: no reminder
generation/escalation jobs fire against the demo data. Enabling them later is a
separate, explicit choice.

### Dashboard (caregiver web app)

From `dashboard/`, install dependencies and run the development web app with an
explicit local API URL:

```sh
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Run both the VM suite and the browser-platform suite locally:

```sh
flutter test
flutter test --platform chrome
```

For deployment, set the real HTTPS API origin and pass the required release
define:

```sh
export API_BASE_URL=https://api.your-domain.example
flutter build web --release --dart-define=API_BASE_URL="$API_BASE_URL"
```

A release build without `--dart-define=API_BASE_URL` fails during configuration;
the development default remains `http://localhost:8000`. The CI build uses a
non-secret placeholder URL because it validates compilation, not connectivity.

### Mobile (patient app)

From the `mobile/` directory:

```sh
flutter pub get
flutter devices                      # find SERIAL of the attached device/emulator
adb -s SERIAL reverse tcp:8000 tcp:8000
flutter run --debug -d SERIAL --dart-define=API_BASE_URL=http://localhost:8000
```

With the `adb reverse` tunnel, the app reaches the host backend as
`http://localhost:8000`. On an **Android emulator** (no reverse needed), the
address is the explicit host loopback `http://10.0.2.2:8000`:

```sh
flutter run --debug -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Both hosts are covered by the debug-only cleartext whitelist
(`mobile/android/app/src/debug/` → `network_security_config.xml`); release builds
stay TLS-only. The `API_BASE_URL` flag is defined in
`mobile/lib/config/app_config.dart`. Physical-device behavior (mic, speaker,
notifications, visual walkthrough) is **not verified** — do not claim on-device
validation.

### Migration safety for the populated demo database

The source chain now has one head: `0014_reminder_idempotency`. The historical
`0009`-only gate below has been superseded; do not use old process IDs, schema
stamps, or approval notes as current state.

The populated demo database is a live synthetic-data fixture, not a disposable
migration target. Before changing its schema or restarting current source:

1. Re-run the host/port/database/system-identifier preflight above.
2. Inspect the actual `alembic_version`; do not infer it from an old note.
3. Take a fresh verified backup.
4. Review every pending migration and obtain explicit operator approval.
5. Run `alembic upgrade head` only from `backend/` with the verified
   `DATABASE_URL`, then run the canonical backend test command and the approved
   smoke procedure.

Do **not** casually run `alembic upgrade head` against the demo database, hand-
patch schema versions, substitute the empty compose cluster, or let a startup
failure trigger ad-hoc DDL. If the preflight or revision differs, stop.

The canonical migration regression is included in
`cd backend && python3 -m pytest app/tests tests -q`. CI independently proves a
clean PostgreSQL 16 `alembic upgrade head` before its live smoke walk; that clean
service is not evidence that the populated demo database was migrated.

### Old migration history

The migration-recovery notes below are **historical record only**. They describe
the earlier `0003` stamp, `0005` rename, and `0004` DDL recovery. They do not
establish the demo database's current revision; inspect the live database. The
source-of-truth chain currently ends at `0014_reminder_idempotency`, and
`CLAUDE.md` was reconciled on 2026-09-25.

## Upgrade regression checkpoint — 2026-09-23 (fix-it waves 1-6)

These counts describe that dated checkpoint only; they are not the current suite
size. Reproduce current status with the canonical commands above.

- Backend: `python3 -m pytest app/tests tests -q` from `backend/` — 509 passed, 7 skipped. All tests pass under the CI invocation (working-directory: backend); the earlier adaptive-CLI failure was an invocation-directory artifact, now resolved.
- Standalone services: `python3 test_phase2_services.py` — 21 passed.
- Mobile: `flutter test` — 102 passed, 5 live-API tests skipped; `flutter analyze` — 43 pre-existing informational findings, 0 errors.
- Dashboard: `flutter test` — 15 passed; `flutter analyze` — 33 pre-existing informational findings.
- Migrations: full-chain round-trip proven on a THROWAWAY PG 16 container (`smriti-mig-w4`, removed after proof; demo DB untouched): upgrade head → downgrade base → upgrade head all green; 12 seed rows across 4 game types verified; 0004 orphan enum types now dropped in downgrade; 0007/0010 `ALTER TYPE` existence-guarded; 0001 enum-name typo fixed (`symptomentrysourceenum`, matches the model-derived name); 0005 downgrade symmetric. Full-chain SQLite support is PG-only by design (runtime is PG; per-revision SQLite tests cover the compatible revisions).
- Fix-it highlights: schedule/event cross-checks (404/422), offline Odd-One-Out replay fetches a fresh server board, sync failures stay pending + retryable (never silently dropped), clinical notes ride the offline_symptom outbox, RAG upload wired on both clients (staff-only), single-flight token refresh (mobile + dashboard), FCM audit records FAILED (a real bug made it record nothing at all), consent-gated alert/weekly job passes, honest dashboard widgets.
- Not verified: physical-device play-test (deferred), live provider calls (keys absent by design).

## Historical checkpoint — 2026-09-17

- Backend: `python3 -m pytest app/tests tests -q` — 184 passed, 3 skipped, 8 warnings.
- Standalone services: `python3 test_phase2_services.py` — 21 passed.
- Mobile: `flutter test` — 54 passed, 5 live-API tests skipped.
- Mobile: `flutter analyze` — 45 findings (5 warnings, 40 informational, 0 errors); not a clean analyzer gate.
- Live API: `NO_PROXY=localhost,127.0.0.1 python3 smoke_e2e.py` — 50 passed, 0 failed against the local PostgreSQL-backed server.
- Backend warnings include a scikit-learn serialized-estimator version mismatch; passing tests do not establish clinical model validity.
- Physical microphone, speaker, notifications, and visual walkthrough remain unverified. This checkpoint is not production or clinical sign-off.

### Migration recovery and repeatable commands

Historical recovery note: a local database was once stamped at `0003`, already
had `clinical_features`, and lacked notification/level-config tables. Blind
stamping and downgrade attempts caused drift. Do not reproduce them. Inspect the
actual schema and `alembic_version` before any reconciliation; a downgrade
through `0005` can remove pre-existing `clinical_features` and requires a backup
plus explicit data-loss approval.

Run the **non-destructive** current-revision check and canonical test command from
`backend/`:

```sh
python3 -c 'import os; from app.config import settings; from alembic.config import Config; from alembic import command; os.environ["DATABASE_URL"] = settings.DATABASE_URL; command.current(Config("alembic.ini"))'
python3 -m pytest app/tests tests -q
python3 test_phase2_services.py
```

Only after the demo preflight, fresh backup, migration review, and explicit
approval may an operator run:

```sh
python3 -c 'import os; from app.config import settings; from alembic.config import Config; from alembic import command; os.environ["DATABASE_URL"] = settings.DATABASE_URL; command.upgrade(Config("alembic.ini"), "head")'
```

Then re-run the canonical tests and the approved smoke procedure. The smoke
script creates synthetic accounts, patients, consent, game records, and companion
configuration `1.1.0`; it does not clean up. Use it only on the explicitly
approved demo/disposable database, never production. It does not test Number
Recall gameplay, live ASR/TTS playback, real notification delivery, physical
offline replay, or OCR.

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
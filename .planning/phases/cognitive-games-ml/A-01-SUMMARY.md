# Phase A — A-01 implementation summary (2026-09-17)

**Binding decision, 2026-09-17:** Risk screening and difficulty are fully independent.
Phase B uses only session accuracy/time/error/current-level features; game/config/support
metadata is allowed. No risk input, prior, risk-based calibration, risk missingness,
screening joins or screening reads in training, inference or policy. This is not an
optional future approval decision. Screening is not clinically validated.

**Superseded history only:** An earlier instruction enabled the screening score by
default for Phase B. That instruction is no longer in force and does not authorize
any risk coupling. Phase B has not been approved; the user requested a report first.

This summary consolidates earlier execution evidence supplied for this documentation
reconciliation. No code, DB operations or tests were run during this docs-only edit.
Implementation and final main-agent closure verification are complete; A-02 report
review and explicit B start approval remain pending. Today's populated-host and pinned
server proof below supersedes earlier unmigrated/unrestarted statements.

## What changed (uncommitted on chore/deployment-readiness)

- `app/services/risk_screening_service.py` — startup init (`initialize_risk_screening`,
  once per worker PID, lock-guarded), 32-name schema/guide agreement, scaler
  `n_features_in_`/finite-parameter checks, model IO shape `(None,32)->(None,1)`,
  guide-range + finite input validation, finite scaled/output checks, out-of-range
  predictions rejected (never clamped), composite sha256 `model_version`.
- `app/main.py` — lifespan calls initialization once per worker.
- `app/routes/patients.py` — screening requires patient access, clinical role,
  active `health_data` consent selected `with_for_update()`, transactional audit
  (audit failure fails closed); persists latest successful screening.
- `app/routes/compliance.py` + `compliance_service.py` — export omits screening
  from basic-tier callers; screening disclosure in export fails closed if audit fails.
- `app/models/all_models.py` + `alembic/versions/0008_risk_screening.py` — additive
  `risk_screenings` table (one row per patient, probability/score/model_version/
  consent FK, check constraints, 18-char revision id, no raw feature vector).
- `retention_service.py` — consent-grace erasure covers screenings.
- Tests: `app/tests/test_risk_screening.py` (real-artifact HTTP gate + defensive
  contracts), `tests/test_migrations.py` (head-resolution guard kept, 0008 explicit).

## Historical initial RED → GREEN evidence (not latest counts)

- Initial focused RED: 36 failed / 7 passed; migration RED 1 failed / 3 passed.
- Final focused: 44 passed, no skips. **Full suite: 242 passed, 3 skipped, 13
  warnings** (freshly re-run by the main agent, unfiltered).
- Two subprocess workers each loaded artifacts exactly once.
- Real-artifact HTTP results: probability 0.1598 / score 15.98 and probability
  0.1245 / score 12.45 — finite, in-range; latest row overwritten on repeat.

## Reconciliation answers

1. **Risk endpoint implemented and tested?** Endpoint exists (commit `d417460`);
   real Keras/scaler inference over HTTP with auth/consent/audit/persistence was
   verified in tests. Today's separate pinned local server HTTP proof is recorded below;
   test results alone are not deployment evidence.
   `backend/app/ml_models/` never existed; artifacts live in
   `backend/ml_models/alzheimers_risk/` (a misspelled `alzeiheimers_risk` duplicate
   also exists — untouched).
2. **One adaptive engine or two?** Three exist: backend rules
   (`difficulty_engine.py:48`, active), archived Stage 2
   (`backend/archived/ml_models/adaptive_engine/`, unreferenced), and a divergent
   mobile engine (`game_analytics_engine.dart:207`, active on-device). Not unified;
    authority unification is excluded from bounded B and deferred to a separate optional
    user-approved task.
3. **Needs fixing before B:** items below.

## Follow-up remediation and closure evidence

The following gaps were remediated earlier in this task; they are not outstanding authorization blockers. Final main-agent verification is recorded below; A report acceptance remains pending.

RESOLVED 2026-09-17 (same day, follow-up execution):

- **Grant authorization repaired.** `deps.require_patient_owner`/`ensure_patient_owner`
  (patient-role owner matched to `patient.user_id`, FOR UPDATE) is the sole authority
  for caregiver-link delegation and consent grant/revoke; staff read rights no longer
  imply consent/delegation power; guardian/joint grants hard-rejected (422) until a
  verified-guardian workflow exists; consent scope allowlist enforced; grant/revoke
  and caregiver links are atomic fail-closed audits; duplicate active links rejected
   (row-locked, no uniqueness schema change); profile binding restricted to patient
   self-binding. Grantor identity is persisted; basic versus clinical grant boundaries
   are enforced. These repairs do not establish authority for legacy rows: that review
   remains pending, as does database-level uniqueness hardening.
- **Public registration restricted** to `patient`/`family_caregiver`; staff roles are
  403 at `/auth/register` and must be provisioned via trusted DB process. Smoke now
  requires `SMOKE_CLINICIAN_PHONE`/`SMOKE_CLINICIAN_PASSWORD` for a pre-provisioned
  clinician and fails fast without them. Frontend has no privileged signup selector;
  mobile's generic register helper may still send staff roles and would now be
  rejected server-side.
- **ML runtime compatibility established:** Python 3.12.14 + TF 2.16.2 +
  sklearn 1.6.1 + NumPy 1.26.4 loads the committed scaler/model with **no
  InconsistentVersionWarning** and produces byte-identical probabilities to the
  3.13/TF 2.21 runtime on synthetic inputs (0.9642 / 0.9921, deterministic across
  repeats and fresh processes). Pins are now applied:
  `tensorflow==2.16.2 scikit-learn==1.6.1 numpy==1.26.4 keras==3.13.2 joblib==1.6.0`.
  A full fresh Python 3.12.14 environment installed all backend requirements;
   `pip check` passed. Dockerfile targets Python 3.12. At that earlier checkpoint the
   app had not restarted on pins; today's verified pinned local runtime supersedes
   that limitation. No production deployment claim follows.
- **Migration 0008 verified on real PostgreSQL 16.15** in a disposable
  socket-isolated cluster (`tests/test_risk_migration_postgres.py`, opt-in via
  `RUN_RISK_MIGRATION_POSTGRES=1`): populated upgrade/downgrade/re-upgrade
  preserves pre-existing data, FK cascades independent, check constraints enforce
  bounds, single 19-char head.

Historical intermediate full suite: **380 passed, 7 skipped, 13 warnings**.
Supplied final main-agent full suite: **387 passed, 7 skipped, 13 warnings**;
focused risk suite: **57 passed**, with `InconsistentVersionWarning` treated as an
error. `pip check` and earlier `git diff --check` passed. No checks were rerun in this
docs-only edit. Separate populated PostgreSQL migration tests: **4 passed**,
non-skipped, in the disposable cluster.

## Compose database closure evidence (earlier execution)

- Actual Compose PostgreSQL version: **16.15**, initially empty. Applied full chain
  **0001–0008**: **21 tables**, **9 level-config rows + 1 version row = 10 total rows**.
- Container system identifier **7682040204916105254** matches verified endpoint
   **192.168.23.25:5432**. `localhost` is a different host cluster, untouched by that
   Compose operation but now separately migrated as recorded below. Compose has no
   patients/documents.
- Backup: `/var/folders/p6/skhrv32s2nl4mtknn7s6mj9c0000gn/T/opencode/eldercare_backup_20260917_155701.dump`, mode **0600**.
- Second upgrade was a no-op; before/after snapshots were identical.
- Because Compose started empty, this is not nonvacuous preservation proof for
  pre-existing Compose data. Separate populated migration coverage passed **4 tests**;
  today's actual populated-host preservation evidence is recorded below.

## Verified populated host and pinned runtime — supplied main-agent evidence

- Host **localhost:5432 / eldercare**, system identifier **7681754862742343790**:
  migration **0008_risk_screening APPLIED** after private backup. Retained before/after
  hashes prove original rows preserved: **39 users, 13 patients, 10 documents,
  54 sessions, 13 consents**.
- Backup: `/var/folders/p6/skhrv32s2nl4mtknn7s6mj9c0000gn/T/opencode/host-runtime-proof-20260917.dump`, mode **0600**.
  Hashes are retained by main, not invented here. The authorized risk smoke added
  **one risk row** and audit **215→216**; the entire post-smoke DB is not unchanged.
- Pinned Python **3.12.14** app **PID 51348** remains at **127.0.0.1:8000** with
  verified **`ENABLE_BACKGROUND_JOBS=false`**. Health **HTTP 200**, real risk endpoint
  **HTTP 200**, probability **0.15980100631713867**, score **15.98**.
- Prior Python 3.13 process environment was inferred, not proven. Current host migration
  and pinned runtime proof supersede the earlier unmigrated/unrestarted checkpoint.
  This is local runtime evidence, not clinical validation or full production readiness.

## Remaining limitations and approval gates

- Database uniqueness constraint remains pending; application row-lock/duplicate
  checks are not a substitute for that constraint.
- Legacy-data authority review remains outstanding; no claim legacy rows were reviewed.
- Backend lint/typecheck commands remain unspecified and **were not run**.
- Final fresh main-agent rerun is confirmed: **387 passed, 7 skipped, 13 warnings**;
  focused risk **57 passed**. A report acceptance and explicit B start approval remain
  pending; passing verification does not authorize B.
- Risk screening and difficulty remain fully independent under the binding decision;
  the earlier enabled-by-default decision is superseded, not a future optional prior.

## Next

Main presents the A evidence/report for user review; final rerun and count updates
are confirmed above. **Do not start B without explicit user approval after the report.**

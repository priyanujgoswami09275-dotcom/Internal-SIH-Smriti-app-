# Cognitive games / ML — state

## Current status (2026-09-17)

- **A implementation and requested closure verification completed; A-02 report review is the next step.** B-01 executed within its 6-hour cap (shadow-only, rules always applied); B-REPORT.md is the single B deliverable. B-02–B-06 remain superseded archives. C remains unapproved/replan-required.
- B is now **one working day / 6-hour hard cap**, solely B-01, with three 2-hour blocks and one final B-REPORT.md. B-02–B-06 are **SUPERSEDED / INACTIVE / NEVER AUTOEXECUTE**; their research, calibration, authority and activation gates no longer apply.
- C remains **UNAPPROVED / REPLAN REQUIRED** after the single B report. Existing C plans assume superseded B integration and must not autoexecute.
- Binding independence: no risk input, prior, risk-based calibration, risk missingness, screening reads or joins in difficulty extraction, training, inference or policy.
- This reconciliation changes existing planning docs only. No B implementation, tests, database operations, source changes, graph updates, staging or commits; main handles graph and requested commits.

## Verified local runtime today — supplied main-agent evidence

- Pinned Python **3.12.14**, TensorFlow **2.16.2**, scikit-learn **1.6.1**, NumPy **1.26.4**, Keras **3.13.2**, joblib **1.6.0**; all backend requirements installed and `pip check` passed. Dockerfile targets Python 3.12.
- Final suite **436 passed, 7 skipped** (includes 48 adaptive + consent-gate tests); focused risk **57 passed**, both with `InconsistentVersionWarning` treated as an error. `git diff --check` passed. Remaining warnings are deprecations/scaler feature names.
- Current host database: **localhost:5432**, database **eldercare**, system identifier **7681754862742343790**. Migration **0008_risk_screening is now APPLIED on this populated host**, after backup; retained before/after hashes prove all original rows preserved.
- Existing seed data retained: **39 users, 13 patients, 10 documents, 54 sessions, 13 consents**. The authorized risk test added **one risk row** and audit increased **215→216**; do not describe the entire post-smoke database as unchanged.
- Private host backup: `/var/folders/p6/skhrv32s2nl4mtknn7s6mj9c0000gn/T/opencode/host-runtime-proof-20260917.dump`, permissions **0600**. Original-row hashes retained by main; no hashes invented here.
- Pinned Python 3.12 server **PID 51348 remains on 127.0.0.1:8000**, with **verified `ENABLE_BACKGROUND_JOBS=false`**. Health **HTTP 200**, real risk endpoint **HTTP 200**, probability **0.15980100631713867**, score **15.98**. Prior Python 3.13 process environment was **inferred, not proven**; current runtime proof is verified.
- Compose remains a **separate** PostgreSQL **16.15** cluster, system identifier **7682040204916105254**, verified endpoint **192.168.23.25:5432**; 0001–0008 applied, **21 tables**, 9 level-config rows + 1 version row, **no patients/documents**. Empty Compose evidence must not be substituted for populated host preservation.
- Earlier Compose backup `/var/folders/p6/skhrv32s2nl4mtknn7s6mj9c0000gn/T/opencode/eldercare_backup_20260917_155701.dump`, mode 0600; second upgrade was a no-op with identical snapshots. Separate disposable populated PostgreSQL migration coverage: **4 passed**.
- This is local runtime and preservation evidence, not clinical validation or full production readiness. Backend lint/typecheck commands remain unspecified and **not run**; no fresh mobile/device validation.

## A remediation and residual limitations

Screening startup/lifecycle, real-artifact HTTP inference, validation, consent/access/audit, persistence and retention were implemented; see A-01-SUMMARY.md. Earlier authorization gaps were repaired: owner-only grant/revoke and caregiver delegation, persisted grantor, unsupported guardian/joint authority rejection, basic-versus-clinical boundaries, no public staff signup and fail-closed audit.

Database uniqueness hardening and legacy-data authority review remain outstanding. Preserving old rows does not establish historical grant authority. Earlier statements that the host was unmigrated or pinned server unrestarted are superseded by today's verified runtime proof. Backend/mobile authority remains divergent, not unified by A or by planned shadow B.

## Active B scope and stop rule

1. **Hours 0–2:** fixed last 3 completed real patient/game sessions strictly predecision; mean accuracy/response time, fixed category-rate vector `[mismatch, sequence_position, recall_position]`, current level, explicit missing telemetry. Actual first observed completed next-level outcome within 30 days: accuracy >=85% and within target; missing outcomes excluded. Synthetic bootstrap clearly labeled assumption conformity.
2. **Hours 2–4:** one LogisticRegression seed 42; one 80/20 patient-disjoint group shuffle split using real/synthetic patient IDs, train-only preprocessing. No validation split/calibration/GB/research. Accuracy plus ROC-AUC when test has both classes. Manual real retrain reuses extractor/split and refuses unless >=100 labeled transitions, >=10 patients, >=10/class overall and both classes in train/test; demo support only, not clinical evidence.
3. **Hours 4–6:** reuse backend evaluate and existing log; optional shadow only. **Every returned level uses exact rules** (three strictly >85 raise, two strictly <50 lower, existing window/bounds), including <3 histories. Applied source always `rule_fallback`; log reason/rule version/current/result, optional separate `shadow_probability` / `shadow_model_version`, never false applied `ml_model`. Minimal additive fields; migration 0009 after verified 0008 only if needed. Simple checks and one final report.

**Hard stop at 6 hours:** report incomplete work and unrun checks, do not extend scope. No mobile overhaul, authority unification, calibration/promotion/rollback UI or tooling, cohort research, or activation. Authority unification and later activation are separate optional user-approved tasks, not B completion requirements.

## Dependency chain and next step

**A-01 → A-02 [present A report, one explicit B approval/start] → B-01 [6-hour maximum] → one B report → C replan [unapproved].**

## A-02 approval record (2026-09-21)

- User decision: **approve** — A evidence and B-01 report accepted as-is.
- Scope: acceptance only. No new work authorized. B-01 already executed (`B-REPORT.md`, commits `7f650ac`/`fabec76`); this approval does not authorize activation, calibration, promotion tooling, or C implementation.
- Next gated step: C replan, still **unapproved**. No C execution without a separate explicit approval.

## C replan record (2026-09-21)

- User approved starting the C replan (docs-only). Delivered: `C-REPLAN.md`.
- Key corrections vs old C-01..C-04: next migration is `0010_odd_one_out` (0009 taken by
  shadow difficulty); B-06-gated numbers demoted to proposed defaults pending gate R0;
  nonexistent B-03/B-04/C-01 summary references dropped; semantic-category errors never
  folded into the 3-category B extractor (fallback reasons instead); board endpoint must
  carry the B-01 patient-access + `game_data` consent gate.
- C implementation remains **unapproved**. Next: user picks replan §5 option 1 or 2.

## C implementation record (2026-09-21)

- User approved C implementation (replan §5 option 1). Built all slices in one session
  under SDD (ledger: `.superpowers/sdd/C-REPLAN/progress.md`, git-ignored):
  `d82490e` C-01' domain/config/migration, `daa64b8` C-02' integration,
  `78b172c` C-03' mobile. Per-task reviews clean (two fix rounds, all closed).
- Deliverables: `C-REPORT.md`, `C-01/C-02/C-03-SUMMARY.md` (this directory).
- First-hand verification: backend **469 passed / 7 skipped** (pinned 3.12.14);
  mobile `flutter test` all-pass, analyze zero new findings; `git diff --check` clean.
- Migration 0010 applied nowhere (host/compose untouched); device checkpoint pending
  (no isolation approval for manual play against any backend).
- R0 Option A applied as recommended default (user authorized full build without
  selecting A/B/C) — recorded in final report rulings.
- Next: user acceptance (accept / accept-with-deferred-validation / hold).

## C acceptance (2026-09-21)

- User decision: **accept-with-deferred-validation**. Code, tests, and review accepted as
  solid; the device play-test is genuinely outstanding, not a formality — deferred
  explicitly, not waived. No activation/calibration/promotion authorized.

Next: perform the documentation-only A-02 report review. No research-contract ratification gate; the bounded defaults are already written in B-01. Do not start B without explicit approval after the A report. No automatic old B gates, C implementation, activation or commits. Future report/artifact names describe planned outputs, not existing evidence.

## Historical planning record (inactive)

The original twelve-plan A/B/C chain, five-file budgets, rolling 3–5 features, chronological train/validation/test methodology and B-06 gates are superseded. B-02–B-06 retain archival methodology only; old C dependencies require replan. Earlier graph/source reconnaissance and dirty-workspace observations are historical, not current status; preserve all user-owned changes.

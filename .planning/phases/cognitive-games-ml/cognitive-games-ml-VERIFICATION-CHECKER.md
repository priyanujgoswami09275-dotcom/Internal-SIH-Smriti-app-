# Documentation-only plan checker

Original planning review: 2026-09-17. This reconciliation checks existing documentation against the supplied main-agent evidence and binding scope; it is **not a fresh application verification or permission to execute**. No models, tests, migrations or runtime operations were run in this edit. A implementation and final main-agent rerun are complete; A-02 report review and explicit B start approval remain pending.

## Authoritative active path

**A-01 → A-02 [A report review + one explicit B start approval] → B-01 [one working day / six-hour hard cap] → one B-REPORT.md → C replan [unapproved].**

- **B-01-PLAN.md is the sole active B plan:** three two-hour blocks, one final report, no intermediate approvals or B-06 checkpoint. B has not started.
- **B-02–B-06 are SUPERSEDED / INACTIVE / NEVER AUTOEXECUTE.** Their research, calibration, authority, replay, promotion and activation gates, outputs and five-file budgets impose no current requirement.
- **C-01–C-04 are UNAPPROVED / REPLAN REQUIRED / NEVER AUTOEXECUTE.** Their old full-stack B dependencies are historical proposals, not implemented prerequisites or executable approval. Replan after the single B report, then seek explicit C approval.
- At six hours stop and report incomplete items and unrun checks. No automatic activation, scope extension, C execution or commits. Main handles graph updates and any separately requested commits.

## Active requirement trace

| Requirement | Authoritative document / check |
|---|---|
| A lifecycle, 32-feature schema, real-artifact HTTP inference, dependency compatibility and authorization/consent/audit remediation | A-01-SUMMARY.md and STATE.md record completed main-agent evidence; A-02 presents the report and limitations. Imports, mocked inference and direct calls are not substitutes for HTTP proof. |
| Binding risk/difficulty independence | ROADMAP, STATE, A-02 and B-01: no risk input, prior, risk-based calibration, risk missingness or screening reads/joins in extraction, training, inference or policy. There is no optional risk-prior decision to reopen. |
| Fixed session-only extractor | B-01 block 1: exactly last 3 completed real sessions for the same patient/game, strictly predecision; mean accuracy/time, ordered error-rate vector `[mismatch, sequence_position, recall_position]`, current level and explicit missing telemetry with train-fitted imputation. No rolling 3–5 window or feature research. |
| Observed label without future leakage | B-01 block 1: first actually observed completed next-higher-level outcome within 30 days; accuracy >=85% and within configured target is success. Exclude missing/unevaluable outcomes and top-level decisions; target-session data is not a feature. Synthetic bootstrap means assumption conformity, not patient performance. |
| One fit and one split | B-01 block 2: preprocessing plus LogisticRegression seed 42; one 80/20 patient-disjoint GroupShuffleSplit using real/synthetic patient IDs; train-only preprocessing and actual row/group counts. Accuracy and ROC-AUC when held-out data has both classes, otherwise ROC-AUC undefined. No GB comparison, validation split, calibration, tuning or cohort research. |
| Bounded manual real retrain | Same extractor and fixed split; >=100 labeled transitions, >=10 patients, >=10/class overall, both classes in train/test. Refuse without artifact write/overwrite if unsupported; no seed search. Demo thresholds are not clinical evidence; command existence does not authorize patient-data execution. |
| Exact applied rules for every returned level | B-01 block 3: three strictly >85 raise, two strictly <50 lower, existing rule window/bounds 1–3. Fewer than 3 histories skips shadow only; two-low-session lowering still applies. No shadow probability, threshold or error veto changes applied levels. |
| Honest minimal backend shadow/logging | Reuse `evaluate_difficulty` and `DifficultyAdjustmentLog`; every new evaluation including hold uses applied `source=rule_fallback`, reason, rule version, current/resulting level and result. Optional nullable `shadow_probability` / `shadow_model_version` are separate, never applied `ml_model`, confidence or raw-feature logging. |
| Additive persistence only if needed | Minimal fields; migration 0009 after verified 0008_risk_screening only if needed, original rows preserved with nullable legacy metadata. No historical migration rewrite or implicit host/production mutation. |
| Simple checks and one report | B-01 blocks 1–3 cover isolation/missingness/labels, split/preprocessing, fit/refusal, strict rule boundaries and unchanged rule results/provenance. One B report records completed/incomplete items, assumptions, metrics/support/exclusions, command evidence and actual limitations within six hours. |
| Explicit exclusions | No mobile overhaul, offline replay redesign, backend/mobile authority unification, calibration, promotion/rollback tooling or UI, cohort research or model activation. Unification and later activation are separate optional user-approved tasks, not B gates. Backend/mobile progression remains divergent. |
| Future C proposal only | Four games proposed: Match It, Routine Sequencing, existing Number Recall and new Odd-One-Out; word mode is not a fifth game. Config/taxonomy, integration, migration and device checks require replan. No B-03/B-04 integration or B-06 research gate is assumed complete or required by active B. |

## Confirmed A evidence — supplied main-agent results

- Final fresh main-agent full suite **387 passed, 7 skipped, 13 warnings**; focused risk **57 passed**, both with `InconsistentVersionWarning` treated as an error. These are confirmed supplied reruns, not tests performed during this documentation edit. Earlier intermediate counts are historical only.
- Pinned **Python 3.12.14**, TensorFlow **2.16.2**, scikit-learn **1.6.1**, NumPy **1.26.4**, Keras **3.13.2**, joblib **1.6.0**; full backend requirements installed, `pip check` passed; Dockerfile targets Python 3.12. Earlier main-agent `git diff --check` passed.
- Populated host **localhost:5432 / eldercare**, system identifier **7681754862742343790**: **0008_risk_screening APPLIED after private backup**. Retained before/after hashes prove original rows preserved: **39 users, 13 patients, 10 documents, 54 sessions, 13 consents**. Authorized risk smoke added **one risk row** and audit **215→216**; do not call the entire post-smoke DB unchanged.
- Host backup: `/var/folders/p6/skhrv32s2nl4mtknn7s6mj9c0000gn/T/opencode/host-runtime-proof-20260917.dump`, mode **0600**. Main retains original-row hashes; none are invented here.
- Pinned Python 3.12 app **PID 51348** remains on **127.0.0.1:8000**, verified **`ENABLE_BACKGROUND_JOBS=false`**. Health **HTTP 200**, real risk endpoint **HTTP 200**, probability **0.15980100631713867**, score **15.98**. Prior Python 3.13 process environment was inferred, not proven; current pinned-runtime proof is verified.
- Compose is a **separate** PostgreSQL **16.15** cluster, system identifier **7682040204916105254**, verified endpoint **192.168.23.25:5432**. Initially empty; 0001–0008 applied, **21 tables**, **9 level-config rows + 1 version row**, **no patients/documents**. Private mode-0600 backup and identical no-op second-upgrade snapshots are recorded in STATE. Empty Compose evidence is not populated-host preservation proof; separate populated migration tests also passed **4 tests**.
- Earlier host-unmigrated/app-unrestarted statements are superseded by the current proof above. This establishes local runtime and preservation, not clinical validation, full production readiness, historical grant authority, real-data difficulty validation or device success.

## Remaining limits and approval status

A report review and one explicit B approval/start remain pending; final verification and count updates do not. Database uniqueness hardening and legacy-data authority review remain outstanding. Backend lint/typecheck commands are unspecified and **not run**; no fresh mobile/device validation is claimed. These limitations must remain visible, not become invented B calibration/research gates.

A-01-SUMMARY.md is existing implementation evidence. Future A/B/C reports, candidates and summaries named in plans are planned outputs, not present evidence. Approval of this documentation reconciliation is not B or C start permission. No application tests or DB operations are needed to perform this documentation-only correction.

## Historical original-plan structure — inactive, not a current checklist

The original review recorded twelve serialized plans, 25 tasks and five-file implementation budgets. Its structure findings describe that old revision only, not the rewritten active documents. The dependency table below is retained solely as history; none of its B-02–B-06 or old C dependencies supplements B-01.

| Historical plan | Historical wave | Historical dependency |
|---|---:|---|
| A-01 | 1 | — |
| A-02 | 2 | A-01 |
| B-01 | 3 | A-02 |
| B-02 | 4 | B-01 |
| B-03 | 5 | B-02 |
| B-04 | 6 | B-03 |
| B-05 | 7 | B-04 |
| B-06 | 8 | B-05 |
| C-01 | 9 | B-06 |
| C-02 | 10 | C-01 |
| C-03 | 11 | C-02 |
| C-04 | 12 | C-03 |

The former LR/GB comparison, chronological train/validation/test calibration, subgroup support research, localized-error ML veto, unified online/mobile authority, transactional replay, promotion/rollback and B-06 activation gates are archived methodology only. B-02's old 0008_adaptive_decisions and C's proposed migration IDs are stale historical assumptions, not instructions to execute or required scope corrections before bounded B.

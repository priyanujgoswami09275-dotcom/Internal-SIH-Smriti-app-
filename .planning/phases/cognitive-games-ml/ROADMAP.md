# Cognitive games / ML milestone

**A implementation and final pinned-runtime verification completed; A-02 report review is the current next step.** Runtime evidence supplied by the main agent is recorded in A-01-SUMMARY.md and STATE.md; no tests or DB operations were performed in this documentation edit. B has not started and needs one explicit approval/start after the A report. C remains unapproved and requires replanning, not automatic execution.

## Default path and scope

**A-01 → A-02 [A report review + one explicit B start approval] → B-01 [one working day, 6-hour hard cap] → one B-REPORT.md → C replan [unapproved].**

| Stage | Active outcome |
|---|---|
| A-02, next | Present A evidence and limitations; request one bounded B approval. No research-contract gate. |
| B-01, not yet approved | Three 2-hour blocks: fixed extractor/bootstrap; one LR fit/manual retrain command; existing backend shadow/log checks and one final report. |
| B-02–B-06 | **SUPERSEDED / INACTIVE / NEVER AUTOEXECUTE.** Retained only as archival methodology; old gates, outputs and full-stack requirements do not apply. |
| C | Replan after the single B report; old C plans assume superseded full-stack B and are not executable approval. |

At six hours stop, report incomplete work and unrun checks, and do not expand scope. No intermediate B approvals, B-06 checkpoint, automatic activation or commits. Approval of this documentation rewrite is not B start approval.

## Binding B contract

- **Risk and difficulty are independent.** No risk inputs, priors, risk-based calibration, risk missingness, screening reads or joins in extraction, training, inference or policy.
- Runtime history: exactly the last **3 completed real sessions for the same patient/game**, strictly before decision time. Features: mean accuracy, mean response time, fixed ordered category error-rate vector `[mismatch, sequence_position, recall_position]`, and current level. Missing telemetry is explicit, never zero error; fixed missingness mask and train-fitted imputation. No variable windows, trends or feature research.
- Labels use the first actually observed completed next-higher-level session after the decision within 30 days: accuracy **>=85%** and completion within the configured target is success; observed evaluable failure is failure. Missing outcomes/required measurements and top-level cases are excluded, not counterfactually labeled. No future outcome features.
- One preprocessing + **LogisticRegression, seed 42**. Exactly one **80/20 GroupShuffleSplit**, patient-disjoint using real or synthetic patient IDs; preprocessing fitted on train only. Record actual row/group counts. No validation split, calibration, GradientBoosting, tuning, repeated split search or research study.
- Synthetic bootstrap is labeled **assumption conformity**, not patient performance or clinical evidence. Report held-out accuracy and ROC-AUC when both held-out classes exist, otherwise ROC-AUC undefined, plus simple behavior checks.
- Manual real retrain reuses the extractor/split. Minimum **100 labeled transitions, 10 patients, 10 per class overall, both classes in each train/test partition**. Refuse without writing/overwriting an artifact if unsupported; no seed search. These are demo thresholds, not clinical evidence. Real-data execution requires authorization/consent, not just a command's existence.
- **All returned backend levels ALWAYS use exact existing rules**, including when shadow inference is available: three consecutive values strictly >85 raise; two strictly <50 lower; existing rule history/window semantics and bounds 1–3. Fewer than 3 real histories skips shadow, not the two-low-session lowering rule. No probability threshold or localized-error veto alters applied levels.
- Reuse current `evaluate_difficulty` and `DifficultyAdjustmentLog`. Every new evaluation row, including holds, carries applied `source=rule_fallback`, reason, rule version, current/resulting level and result. Optional nullable `shadow_probability` / `shadow_model_version` are separate from applied provenance; no falsely applied `ml_model` label, confidence claim or raw-feature logging.
- Only minimal additive log/response fields. If necessary, migration **0009 after 0008_risk_screening**, verifying the actual head and preserving original rows with nullable legacy metadata. No historical migration rewrite or implicit host/production DB mutation.

B-01-PLAN.md is the sole active detailed B plan. One final B-REPORT.md states completed/incomplete items, synthetic assumptions, metrics/support/exclusions, command/check evidence and actual shadow limitations. Future reports and artifacts are not present evidence.

## Explicitly outside the timebox

No mobile overhaul, offline replay redesign, backend/mobile authority unification, calibration, promotion/rollback tooling or UI, cohort research or model activation. Backend and mobile remain divergent; do not claim unified authority. Authority unification and later activation are separate optional user-approved tasks, neither automatically queued nor required to finish bounded B.

C still proposes exactly four games: Match It, Routine Sequencing, existing Number Recall and new Odd-One-Out. Its config/taxonomy and dependencies need a new scope review after the B report; no B-06 research gate. Word mode is not a fifth game. Do not autoexecute existing C-01–C-04.

## A evidence and remaining limits

- Pinned Python **3.12.14**, TF **2.16.2**, sklearn **1.6.1**, NumPy **1.26.4**, Keras **3.13.2**, joblib **1.6.0**. Supplied final suite **387 passed, 7 skipped, 13 warnings**; focused risk **57 passed**, version warnings treated as errors; `pip check` passed. These are main-agent results, not runs during this edit.
- Host **localhost:5432 / eldercare**, system identifier **7681754862742343790**: migration **0008 APPLIED** after private backup and retained before/after hashes proving original rows preserved. Seed data: **39 users, 13 patients, 10 documents, 54 sessions, 13 consents**. One risk-test row added; audit **215→216**.
- Current pinned Python 3.12 server **PID 51348**, **127.0.0.1:8000**, verified `ENABLE_BACKGROUND_JOBS=false`; health **200**, risk **200**, probability **0.15980100631713867**, score **15.98**. The prior Python 3.13 process environment was inferred, not proven; current runtime proof is verified. This is local runtime proof, not clinical or production-readiness evidence.
- Host backup: `/var/folders/p6/skhrv32s2nl4mtknn7s6mj9c0000gn/T/opencode/host-runtime-proof-20260917.dump`, mode **0600**. Compose is a separate cluster, also at 0008, with no patients/documents; it is not the populated host.
- Database uniqueness hardening and legacy-data authority review remain outstanding. Backend lint/typecheck commands remain unspecified/unrun. No fresh mobile/device validation claimed.

## Historical source context and inactive methodology

The original reconnaissance described separate backend rules, archived Stage2 and divergent mobile progression, not a unified implementation. Canonical risk artifacts are `backend/ml_models/alzheimers_risk/`; the misspelled duplicate is untouched. Number Recall already exists; do not recreate it. Existing NER geographic categories are not a semantic Odd-One-Out taxonomy; future C must replan using existing assets/config. The stats endpoint pools game types; this does not prove separate per-game series or completed-only filtering.

B-02–B-06 preserve the former full-stack/promotion methodology **only as inactive history**. Their 3–5 windows, calibration/support gates, old migration assumptions, mobile authority and replay deliverables do not supplement or override B-01. The verification checker distinguishes this inactive chain from the authoritative single B-01 plan.

## Future approved execution only

Backend suite: from `backend`, `python3 -m pytest app/tests tests -q`; use focused checks in B-01 within its hard cap. Ask for backend lint/typecheck commands rather than inventing success. Disposable DB/smoke mutations require explicit permission. Keep full command output/exit status; report incomplete checks at the stop. The main agent handles graph updates and any separately requested commits; this edit changes existing planning docs only, with no tests, graph, source, DB or git-index changes.

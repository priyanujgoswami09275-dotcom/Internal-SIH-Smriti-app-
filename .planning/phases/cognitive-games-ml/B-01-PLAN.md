---
phase: cognitive-games-ml
plan: B-01
type: execute
wave: 3
depends_on: [A-02]
autonomous: false
status: pending_explicit_start_approval
timebox: 1 working day / 6-hour hard cap
---

# B-01 — single time-boxed hackathon B

This replaces the B-01 through B-06 execution chain. B-02–B-06 are inactive archives and must never autoexecute. This is a plan only, not approval or B implementation. One explicit approval/start after the A-02 report review opens B; one final B-REPORT.md closes the timebox. No intermediate research-contract, calibration, promotion or B-06 gates.

## Objective and hard boundary

Fit one honest synthetic-bootstrap LogisticRegression and attach optional shadow inference to the current backend evaluation path. **Every returned level ALWAYS comes from the existing rules; shadow is the default and the only mode in this task.** Model activation is not included. Stop at six hours within one working day, report incomplete items and do not expand scope or continue into archived plans.

## Block 1 — hours 0–2: fixed extractor, labels and bootstrap

- Reuse the current backend session records and level configuration. Runtime inputs are exactly the last **3 completed real sessions for the same patient/game**, with completion timestamps strictly before decision time (`completed_at < decision_time`); stable timestamp/ID ordering. Incomplete, synthetic runtime and future sessions never count. Fewer than 3 skips shadow inference and uses the exact existing rules.
- Fixed feature schema: mean accuracy, mean response time, error rates in the fixed ordered category vector `[mismatch, sequence_position, recall_position]`, plus current level. Derive category rates from recorded errors/opportunities. Missing response-time/category telemetry or zero opportunities is explicitly missing, not zero error; preserve a fixed missingness mask and use train-fitted imputation. Missing aggregate accuracy/invalid timestamps gives a reason-coded no-shadow result. No trends, variable 3–5 window, extra feature research or new telemetry collection.
- No risk values, priors, risk-based calibration, risk missingness, screening reads or joins anywhere in extraction, training, inference or policy.
- Real label: the **first actually observed completed next-higher-level session** after the decision, within 30 days. Label 1 only for accuracy **>=85%** and completion within that level's configured target time; an observed evaluable failure is 0. Exclude missing outcomes, missing outcome accuracy/duration/target, invalid timestamps and top-level decisions; never label an unplayed level or substitute a later successful attempt. Target-session data is never a feature. Report exclusion counts and observed-outcome selection bias.
- Generate a deterministic bootstrap dataset with synthetic patient IDs and seed 42. Use the same feature schema/extractor with explicit synthetic origin in offline training only. Generated labels describe assumed next-level outcomes, not labels copied from the difficulty rules. Mark dataset, artifact and metrics **synthetic bootstrap — assumption conformity**, not patient performance or clinical evidence.

## Block 2 — hours 2–4: one fit and bounded manual retrain

- One sklearn preprocessing + `LogisticRegression(random_state=42)` pipeline; no alternative estimator. Use exactly one `GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)` with real or synthetic **patient IDs** as groups. This is an 80/20 group shuffle split, not a promise of exact row proportions; record group/row counts and disjointness. Fit all preprocessing on training rows only.
- No validation split, calibration, GradientBoosting, hyperparameter search, model comparison or cohort/subgroup research. Do not search seeds or resplit to obtain better class support or scores.
- Report held-out accuracy and ROC-AUC when the held-out set has both classes; otherwise mark ROC-AUC undefined. Training requires both classes. Save a fitted versioned shadow candidate with schema, seed, origin, split identity and metrics; no live-artifact replacement.
- Planned manual commands from `backend`: `python3 train_adaptive.py --mode synthetic --seed 42 --output ml_models/adaptive_success/bootstrap.joblib` and `python3 train_adaptive.py --mode real --seed 42 --output ml_models/adaptive_success/real-candidate.joblib`. Real mode reuses the exact extractor and split procedure, reads only authorized/consented real data, and excludes synthetic rows. Building the command does not authorize running it against patient data.
- Real demo eligibility: **at least 100 labeled transitions, 10 patients, 10 examples per class overall, and both classes present in each of train and test** after the one fixed patient-disjoint split. Otherwise return `insufficient_data` with counts/reason and write/overwrite no artifact. These straightforward demo thresholds are not clinical evidence; no additional cohort study or support gate.

## Block 3 — hours 4–6: backend shadow, simple checks and final report

- Reuse `evaluate_difficulty` and the existing `DifficultyAdjustmentLog`, not a second engine or new session/replay architecture. Preserve exact backend rules: three consecutive accuracies strictly **>85** raise, two strictly **<50** lower, existing rule history/window semantics, bounds 1–3. This applies to **all** returned levels, including eligible shadow predictions; no probability threshold or error veto changes applied rules. In particular, two low sessions can still lower with fewer than 3 sessions.
- Keep applied `source = rule_fallback` for every result, including hold. Each new evaluation log row records applied source, reason, rule version, current/resulting level and result (raise/hold/lower), reusing existing patient/game/time fields. A model prediction must never produce a falsely applied `ml_model` label.
- Optional `shadow_probability` and `shadow_model_version` are separate nullable fields; probability means estimated next-level success, not decision confidence. Missing/bad artifact, invalid features, top level or inference failure leaves shadow probability null with an explicit shadow reason and the rule result intact. Do not put a shadow probability/version into applied-policy fields or log raw patient features.
- Only minimal additive log/response fields if needed. If persistence requires migration, use **0009 after 0008_risk_screening**, inspect the actual head before execution and never rewrite historical migrations. Preserve original rows with nullable legacy metadata rather than invented provenance. No production/host migration implicit in B approval; use explicitly authorized disposable data for migration checks.
- Simple behavior checks: fixed last-3/predecision patient/game isolation; missing telemetry not zero; missing outcomes excluded; one split patient-disjoint and train-only preprocessing; fitted finite probability; real-data refusal without overwrite; 0/1/2 histories and strict 85/50 boundaries; rule result unchanged by any shadow probability/error; log applied source always `rule_fallback` and separate shadow fields. No research evaluation suite.
- Run available focused tests and, if the timebox permits, the existing backend suite (`python3 -m pytest app/tests tests -q`). Backend lint/typecheck commands remain unspecified: request them, do not invent success. At the hard stop report checks not run or incomplete; no extension to clear a gate.

## Explicitly deferred

No mobile overhaul, screen/UI work, offline replay redesign, backend/mobile authority unification, calibration, promotion/rollback tooling or UI, cohort research, automatic retraining or activation. Existing backend/mobile progression remains divergent; **do not claim it is unified**. Authority unification and later activation each require a separate optional user-approved task, not a hidden B prerequisite or automatic follow-up.

## One final report and next step

Within the six-hour cap, produce only one B-REPORT.md covering completed/incomplete items, synthetic assumptions, split/class/exclusion counts, accuracy/ROC-AUC (or undefined), candidate identity, manual retrain eligibility/command, simple check evidence and actual shadow/log limitations. No report is created by this planning edit and no successful implementation is implied. No B-02–B-06 summaries or separate gates.

Default path: **A-02 report review + one explicit B start approval → B-01 (6 hours maximum) → one B report → C replan**. C remains unapproved; old C dependencies on full-stack B must be revised before any C execution. Stop and await user direction. No automatic activation or commits.

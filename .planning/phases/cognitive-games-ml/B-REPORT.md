# B-REPORT — single time-boxed hackathon B (shadow-only)

Scope: approved B-01, 1 working day / 6-hour hard cap (started 2026-09-17T16:37:10Z).
B-02–B-06 are superseded archives. **Every returned difficulty level comes from the
existing rules; the model runs in shadow only and is never activated in this task.**

## Completed

- Fixed extractor: exactly the last 3 completed real sessions per patient/game with
  `completed_at < decision_time`; features = mean accuracy, mean response time,
  fixed category-rate vector `[mismatch, sequence_position, recall_position]` +
  current level, explicit missingness mask with train-fitted imputation. No risk
  input, prior, screening read or join anywhere (binding independence, verified by
  forbidden-access tests).
- Real label: first observed completed next-level session within 30 days,
  accuracy >= 85% and within that level's `target_seconds`; missing outcomes
  excluded with reason counts, never counterfactually labeled.
- One `LogisticRegression(random_state=42)` pipeline (imputer + scaler +
  classifier), one 80/20 patient-disjoint `GroupShuffleSplit` (seed 42),
  preprocessing fit on train only.
- Manual retrain CLI (`backend/train_adaptive.py`): `--mode synthetic` and
  `--mode real` (explicit allowlist + consent + window + env URL required);
  real mode refuses unless >= 100 transitions, >= 10 patients, >= 10/class
  overall and both classes in train and test, never overwriting on refusal.
- Shadow integration in `evaluate_difficulty`: default rules path computes an
  optional shadow prediction; applied `source` is always `rule_fallback`
  (custom strategies keep truthful `custom_strategy` provenance and bypass
  shadow). Every evaluation — including holds — is logged with source,
  rule version, result, and separate nullable shadow fields.
- Review fixes applied after the build: `POST /difficulty/evaluate` now enforces
  patient access + active `game_data` consent (was staff-role-only); label
  `target_seconds` actually used are recorded per artifact (`label_targets` +
  staleness note) instead of silently depending on current config.
- Migration `0009_shadow_difficulty` (additive, nullable columns, 19-char
  revision id): SQLite upgrade/downgrade/re-upgrade preserves legacy rows.
  **Not applied to any real database; source restart at this HEAD requires
  deploying 0009 first (backup + explicit approval).**

## Fitted candidate (synthetic bootstrap — assumption conformity, NOT patient evidence)

`backend/ml_models/adaptive_success/bootstrap.joblib`,
version `adaptive-synthetic-v1-20260917T230923130209Z`.

| Split | Patients | Rows | Class 0 | Class 1 |
|---|---|---:|---:|---:|
| Overall | 100 | 1,200 | 951 | 249 |
| Train | 80 | 960 | 754 | 206 |
| Held-out | 20 | 240 | 197 | 43 |

Patient groups disjoint (split identity recorded in artifact).
Held-out **accuracy 87.92%**, **ROC-AUC 0.8952**. Synthetic exclusions: 0
(generator always produces evaluable outcomes by construction).
Localized-weakness behavior confirmed on the fitted artifact: high aggregate
accuracy with a weak category predicts substantially lower next-level success
(mismatch 0.84 → 0.31, sequence 0.86 → 0.18, recall 0.84 → 0.34).

## Verification evidence

- Focused adaptive suites: **48 passed** (features, shadow, training, artifact,
  CLI), RED→GREEN recorded for the endpoint consent gate and label-target
  provenance.
- Full backend suite in pinned Python 3.12 with `InconsistentVersionWarning`
  as error: **436 passed, 7 skipped**. `git diff --check` clean.
- Bootstrap CLI rerun from scratch: exit 0, `status: fitted`, metrics above.

## Incomplete / explicitly deferred (hard stop — not expanded)

- 0009 not deployed to host or compose databases; running demo server stays on
  schema 0008 until backup + approval.
- Mobile/backend authority still divergent; no mobile changes in this task.
- No calibration, promotion/rollback tooling, cohort research, or activation —
  each needs a separate user-approved task.
- Real-data retrain never executed against patient data (command built and
  refusal-tested only).
- Session store has no real/synthetic origin column; historical/demo rows are
  indistinguishable automatically (runtime extractor filters by explicit
  synthetic markers, real CLI filters by consent-bounded window).
- Backend lint/typecheck commands remain unspecified and unrun.

## Demo line (honest)

Rules still decide everything; the model only whispers a shadow probability
beside each decision, and every whisper is logged with its model version.
Activation is a separate, explicitly approved step — not part of this report.

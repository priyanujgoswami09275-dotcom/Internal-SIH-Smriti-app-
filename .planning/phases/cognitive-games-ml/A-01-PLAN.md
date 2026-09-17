---
phase: cognitive-games-ml
plan: A-01
type: tdd
wave: 1
depends_on: []
files_modified:
  - backend/app/services/risk_screening_service.py
  - backend/app/main.py
  - backend/app/routes/patients.py
  - backend/app/tests/test_risk_screening.py
  - backend/requirements.txt
autonomous: false
must_haves:
  truths:
    - Authorized consented clinical callers receive real finite screening output through HTTP.
    - Each worker loads compatible artifacts at startup rather than import or request time.
    - Missing artifacts or invalid inputs cannot appear as successful screening.
  artifacts:
    - path: backend/app/services/risk_screening_service.py
      provides: Explicit initialization and validated inference contract
    - path: backend/app/tests/test_risk_screening.py
      provides: Non-skipping real-artifact HTTP gate and defensive contract tests
  key_links:
    - from: backend/app/main.py
      to: backend/app/services/risk_screening_service.py
      via: lifespan invokes idempotent initialize_risk_screening once per worker
    - from: backend/app/routes/patients.py
      to: backend/app/deps.py
      via: clinical access includes patient access and active health_data consent precedes inference
---

<objective>Make existing screening verifiable and defensive, not a clinical validation claim.</objective>
<context>
@.planning/phases/cognitive-games-ml/ROADMAP.md
@.planning/phases/cognitive-games-ml/STATE.md
@backend/app/tests/conftest.py
@backend/app/services/compliance_service.py
@backend/ml_models/alzheimers_risk/feature_names.json
@backend/ml_models/alzheimers_risk/model_input_guide.json
@backend-verify/test_endpoint.py
</context>

**Historical implementation plan:** A implementation and follow-up remediation have occurred; see A-01-SUMMARY.md and STATE.md for completed final main-agent closure verification (387 passed, 7 skipped; focused risk 57 passed) and verified populated-host/pinned-server evidence. Tasks below preserve the original implementation specification, not current outstanding work. Risk screening and difficulty are fully independent; no risk input/prior/calibration/missingness or screening reads/joins are permitted in B. A report review and explicit user approval still gate B.

<tasks>
<task type="auto">
<name>1. Initialize compatible real artifacts in worker lifespan</name>
<files>backend/app/services/risk_screening_service.py; backend/app/main.py; backend/app/tests/test_risk_screening.py; backend/requirements.txt</files>
<action>Write failing lifecycle/schema tests, then remove module-level artifact deserialization and expose initialize_risk_screening() with per-process initialized/available/error state, called before lifespan yield. No retries per request; expose unavailable explicitly. Keep lightweight 32-name JSON schema accessible without stale imported-list bindings. Validate unique ordered names against request/guide, scaler n_features_in_ and feature_names_in_ when present, model input width 32/output scalar shape, and finite scaler parameters. Validate finite raw/transformed arrays and scalar probability before any clamp; reject out-of-range outputs rather than disguising them. Use canonical alzheimers_risk assets unchanged. In an approved isolated environment resolve the reported sklearn serialization-version mismatch and Keras compatibility; only pin proven compatible dependency versions in requirements, never guess or suppress warnings as evidence. If assets cannot be made compatible without replacement, stop and report. Test repeated initialization and repeated requests do not deserialize again; subprocess/worker-local test establishes once per worker, not globally across workers. Do not add new comments.</action>
<verify>In backend after approval: python3 -m pytest app/tests/test_risk_screening.py -q. Record lifecycle load count, schema dimensions, dependency versions and compatibility errors without sensitive inputs.</verify>
<done>Import has no Keras/scaler load; one explicit initialization attempt per worker lifespan state; schema width is 32 and failures remain unavailable. No clinical assets rewritten.</done>
</task>
<task type="auto">
<name>2. Guard HTTP screening and prove actual inference</name>
<files>backend/app/routes/patients.py; backend/app/services/risk_screening_service.py; backend/app/tests/test_risk_screening.py</files>
<action>Use existing ensure_clinical_access (which calls ensure_patient_access), ensure_consent(..., "health_data") and ComplianceService.log_audit_access for this processing action; retain role dependency, return no sensitive features, log minimal resource/status/version only. Treat audit persistence failure as a failed processing response rather than unaudited success. Validate missing/null/non-numeric/non-finite inputs, guide ranges and unexpected fields; retain explicit status contract for model_unavailable/validation_failed, never status ok on error. Build a synthetic 32-feature fixture in the test from guide-compatible values, no named patient data. Use real HTTP request/response through AsyncClient/ASGITransport with explicit app.router.lifespan_context(app), test DB override and disposable authorized clinical patient/consent fixtures; conftest client alone does not run lifespan. Assert HTTP 200, body status == "ok", feature_count == 32, math.isfinite(probability/score), 0 <= probability <= 1, 0 <= risk_score <= 100 and score approximately probability*100 (rounding). The success test must load the committed Keras/scaler, without a mock model, monkeypatched predictor, skip, xfail or direct inference substitute. Add isolated policy/validation tests for allowed/denied fixture roles, revoked consent, invalid feature/output handling and one audit entry without clinical-vector fields; these unit tests do not substitute for the real test. Keep risk independent of game difficulty.</action>
<verify>In backend: python3 -m pytest app/tests/test_risk_screening.py -q; then python3 -m pytest app/tests tests -q. Capture full outcomes; missing real dependencies blocks the real gate. Inspect sanitized audit rows in the isolated test database.</verify>
<done>HTTP real-artifact gate passes with finite bounded results, authorization/consent/audit contract is covered, and no claim that model output is clinically validated or live in progression is made.</done>
</task>
</tasks>
<verification>Run commands unfiltered only after A approval. Ask for backend lint/typecheck commands if still unspecified. No live demo DB smoke without isolation approval.</verification>
<success_criteria>Both tasks evidenced with current output; A remains incomplete until A-02 review.</success_criteria>
<output>Record sanitized implementation/test evidence in .planning/phases/cognitive-games-ml/A-01-SUMMARY.md. Do not commit or auto-start B.</output>

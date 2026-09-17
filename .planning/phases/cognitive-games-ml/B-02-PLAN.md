# SUPERSEDED — inactive archival methodology; NEVER AUTOEXECUTE

Replaced by the single 1-working-day / 6-hour B-01 plan. Everything below is historical, including gates, migration IDs, policy and outputs; it imposes no current requirement. Optional future work requires a separate user-approved task.

---
phase: cognitive-games-ml
plan: B-02
type: tdd
wave: 4
depends_on: [B-01]
files_modified:
  - backend/app/models/all_models.py
  - backend/alembic/versions/0008_adaptive_decisions.py
  - backend/app/services/difficulty_engine.py
  - backend/app/tests/test_adaptive_policy.py
  - backend/app/tests/test_adaptive_migration.py
autonomous: false
must_haves:
  truths:
    - Fewer than three completed real patient/game sessions always use exact existing backend rules.
    - Model errors never remove a usable rule result or fabricate a probability.
    - Every decision including hold can be linked to its session with provenance.
  artifacts:
    - path: backend/alembic/versions/0008_adaptive_decisions.py
      provides: Additive populated-safe decision/session and idempotency schema
    - path: backend/app/services/difficulty_engine.py
      provides: One rule/ML policy with finite probability and localized-error guard
  key_links:
    - from: backend/app/services/difficulty_engine.py
      to: backend/app/services/adaptive_features.py
      via: Identical versioned pre-decision feature extraction
    - from: backend/app/models/all_models.py
      to: backend/alembic/versions/0008_adaptive_decisions.py
      via: Matching nullable historical metadata and uniqueness constraints
---

<objective>Provide additive provenance storage and a bounded, fail-safe policy implementation.</objective>
<context>
@.planning/phases/cognitive-games-ml/ROADMAP.md
@.planning/phases/cognitive-games-ml/A-REPORT.md
@.planning/phases/cognitive-games-ml/B-01-SUMMARY.md
@backend/alembic/versions/0007_number_recall.py
@backend/app/services/game_service.py
</context>
**PROVISIONAL:** Explicit B approval required; policy stays rules/shadow until thresholds/calibration and activation are approved in B-06. No code or DB changes this turn.
<tasks>
<task type="auto">
<name>1. Add safe decision/session schema without rewriting history</name>
<files>backend/app/models/all_models.py; backend/alembic/versions/0008_adaptive_decisions.py; backend/app/tests/test_adaptive_migration.py</files>
<action>Inspect current source and run alembic heads before authoring; historical plan assumption of down_revision 0007_number_recall is stale after implemented 0008_risk_screening — stop/replan against the verified current head instead. New revision identifier <=32 chars, not the colliding 0008_adaptive_decisions name. Extend DifficultyAdjustmentLog with nullable historical session link, source, probability, artifact_version, policy_version, result (raise/hold/lower), fallback_reason, real_session_count, decision_time and stable decision_key; reuse patient/game/old/new fields. Add session decision_id/provenance JSON snapshot, original device timestamps/origin, unique nullable (patient_id, client_session_id) replay identity, and board snapshot/config version for server scoring; keep action IDs in existing JSON event log with transactional deduplication. Null historical metadata means unknown legacy, not invented ML/rule provenance. Avoid cyclic insertion by allowing nullable links then linking in one transaction. Unique per-session decision key prevents repeated audit. Backfill only mechanically inferable values; preserve populated rows. Tests use isolated PostgreSQL, including populated 0007 fixture, upgrade, legacy nulls, new checks for probability/source and uniqueness, downgrade data preservation limitations explicitly documented; no old migration edits and no user-owned test_migrations.py changes.</action>
<verify>Future backend cwd on explicitly disposable PostgreSQL: alembic heads; python3 -m pytest app/tests/test_adaptive_migration.py -q. Fixture provisions its own pre-0008 schema, verifies populated upgrade and <=32-char revision identifiers. Never point at demo/production DB.</verify>
<done>One additive migration extends the observed head, old sessions/logs survive with honest null provenance, replay and decision uniqueness are enforced.</done>
</task>
<task type="auto">
<name>2. Route candidate inference through exact fallback and bounded policy</name>
<files>backend/app/services/difficulty_engine.py; backend/app/tests/test_adaptive_policy.py</files>
<action>Write parameterized failing tests then extend evaluate_difficulty with explicit decision_time, linked session identity, policy mode/version and return metadata. Preserve existing RuleBasedDifficultyStrategy thresholds strictly >85 for 3-session raise and strictly <50 for 2-session lower, no new timing requirement in fallback, bounds 1–3. Count completed real sessions for this patient/game only; 0/1/2 always fallback, 3 enables eligibility not guaranteed promotion, use rolling 3–5 pre-decision histories and existing 30-day rule window. Cache trusted local fitted artifact by version, validate schema/class order/shape and finite predict_proba output; missing/bad artifact, version mismatch, invalid telemetry, unsupported game/error strata or inference exception produce reason-coded rule_fallback with null probability. No network artifact loading or archived engine import. ML output is next-higher-level probability, not confidence. Implement configurable candidate promotion threshold and supported calibrated policy only; missing/unapproved policy means rule_fallback reason policy_unapproved, with candidate outputs restricted to report/shadow evidence. At level 3 use bounded hold/rule lowering, not a fictional level-4 prediction. Apply A-approved localized-error veto (proposed >=50% error in a category with >=4 opportunities) and insufficient-support veto to ML promotion. Good aggregate accuracy cannot bypass it; low next-level probability alone cannot justify lowering. Return source, nullable probability, artifact/policy versions, old/new levels, result, reason, count, game, time and stable decision key; caller owns transaction, eliminate internal commits/adjustment-only audit semantics. Cold-start and unavailable/invalid-model paths retain exact rule fallback. In the eligible ML path, a localized-error veto returns an ml_model hold with its valid probability and veto reason, rather than falling through to a rule raise; this distinction must be explicit in tests and audit.</action>
<verify>In backend: python3 -m pytest app/tests/test_adaptive_policy.py app/tests/test_adaptive_migration.py -q. Include 0/1/2 vs3 sessions, 85/50 boundaries, unrelated patient/game, duplicates, future sessions, max/min, known localized weakness, artifact errors and real fitted model prediction. Then python3 -m pytest app/tests tests -q.</verify>
<done>Exact cold-start fallback and explicit error reasons are proved; probability never mislabeled confidence; localized weakness blocks ML promotion; all decisions have a persistable envelope.</done>
</task>
</tasks>
<verification>Migration/runtime tests occur only after approval in isolated data. No artifact is activated by this plan; B-06 decides activation.</verification>
<success_criteria>Schema and policy behavior tests pass with fresh evidence; legacy rows preserved and future integration has one contract.</success_criteria>
<output>.planning/phases/cognitive-games-ml/B-02-SUMMARY.md with schema, API envelope, fallback matrix, policy proposal and populated-upgrade proof. No commit.</output>

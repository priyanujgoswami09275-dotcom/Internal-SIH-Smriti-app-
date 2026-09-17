# SUPERSEDED — inactive archival methodology; NEVER AUTOEXECUTE

Replaced by the single 1-working-day / 6-hour B-01 plan. Everything below is historical, including authority/replay work, gates and outputs; it imposes no current requirement. Optional future work requires a separate user-approved task.

---
phase: cognitive-games-ml
plan: B-03
type: tdd
wave: 5
depends_on: [B-02]
files_modified:
  - backend/app/services/game_service.py
  - backend/app/routes/games.py
  - backend/app/services/game_engine_service.py
  - backend/app/tests/test_adaptive_sessions.py
  - backend/app/tests/test_adaptive_reconciliation.py
autonomous: false
must_haves:
  truths:
    - Session creation/completion and explicit evaluation share one backend policy and persisted decision identity.
    - Online and replayed sessions cannot create duplicate decisions or action counts.
    - Served boards use the assigned level and config snapshot rather than an unrelated client level.
  artifacts:
    - path: backend/app/services/game_service.py
      provides: Transactional decision/session linkage and idempotent replay
    - path: backend/app/routes/games.py
      provides: Backward-compatible session/decision response and session-bound board API
    - path: backend/app/tests/test_adaptive_reconciliation.py
      provides: Partial replay and repeated completion audit proofs
  key_links:
    - from: backend/app/services/game_service.py
      to: backend/app/services/difficulty_engine.py
      via: Single evaluate_difficulty call and caller-owned transaction
    - from: backend/app/routes/games.py
      to: backend/app/services/level_config_service.py
      via: Server-selected session level and saved board/config snapshot
---

<objective>Wire the B contract into live session routes, including honest offline reconciliation.</objective>
<context>
@.planning/phases/cognitive-games-ml/ROADMAP.md
@.planning/phases/cognitive-games-ml/B-02-SUMMARY.md
@backend/app/services/recall_service.py
@backend/app/services/content_packs.py
@backend/app/services/routine_service.py
@backend/app/deps.py
</context>
**PROVISIONAL:** A report and B approval required. No implementation this turn. The archive remains inactive; policy remains shadow/rules pending B-06.
<tasks>
<task type="auto">
<name>1. Make the live backend path authoritative and auditable</name>
<files>backend/app/services/game_service.py; backend/app/routes/games.py; backend/app/services/game_engine_service.py; backend/app/tests/test_adaptive_sessions.py</files>
<action>Test first, then make start/complete/evaluate share evaluate_difficulty and decision lookup instead of independent recalculation. Return a decision object containing decision_id, source, probability (nullable), artifact_version, policy_version, old/new level, result, reason, real_session_count, game_type and decision_time; completed summaries retain existing fields plus decision. Persist every decision including hold and cold start, linked to the originating completed session and snapshot metadata; initial zero-history start gets its own uniquely keyed decision. On next start consume the latest applicable recommendation and return assigned difficulty_level, board/config version and decision; treat client level as a request, not authority. Do not count incomplete/new session as history. Adapt GameEngineService wrappers to this result, with no second engine or misleading generic reason. Add optional owned session_id to existing Match It/Routine/Recall board routes, resolve canonical level through level_config_service and save generated board snapshot for future scoring; retain preview compatibility but never let a preview alter session assignment. At explicit evaluate route resolve owned/authorized patient, consent and stable decision identity; repeat requests return same stored result, not another adjustment audit. Remove nested commits; transaction persists session, decision and linkage together. Test HTTP contracts, hold/raise/lower, bounds, shared config override, current-level assignment, completion-to-next-start and unchanged legacy summary fields.</action>
<verify>Future backend cwd: python3 -m pytest app/tests/test_adaptive_sessions.py -q. Assert stored source/version/probability matches returned decision and one row exists for every unique decision, including holds.</verify>
<done>All public session/evaluation wrappers use one backend decision contract; boards agree with assigned server level and no unsupported risk/ML-live claim is introduced.</done>
</task>
<task type="auto">
<name>2. Reconcile offline sessions without duplicate audit or future leakage</name>
<files>backend/app/services/game_service.py; backend/app/routes/games.py; backend/app/tests/test_adaptive_reconciliation.py</files>
<action>Extend existing session/action endpoints, not generic sync routing: accept stable client_session_id and action_id, original started/completed times, board/config snapshot identity and offline decision metadata. Use B-02 uniqueness and transaction/row locking to make retries reuse a session, deduplicate action IDs and return stored completion/decision. Validate ownership, game_data consent, bounded levels/timestamps and snapshot schema using existing helpers; never treat client source=ml_model as trusted evidence. Offline source is rule_fallback with probability null and reason offline; preserve original chosen level and timestamp, then link a separately identifiable authoritative reconciliation result if needed without overwriting played history. Do not score historical features with sessions after original decision time, and do not increase real session counts on retry. Partial online failure carries the known server session ID so replay resumes rather than creating another session. Recompute next online recommendation only when appropriate, keep distinct decision keys for distinct actual decisions and never duplicate logs for retries. Tests cover partial start/action/complete failure, identical retry, differing payload conflict, out-of-order arrival, original time filtering, source spoof rejection by schema/policy fixtures and a single audit/session link after reconciliation. Use synthetic local fixtures only; no vulnerability reproduction procedure.</action>
<verify>In backend: python3 -m pytest app/tests/test_adaptive_sessions.py app/tests/test_adaptive_reconciliation.py -q; python3 -m pytest app/tests tests -q. Assert database counts, per-action deduplication, event order, nullable fallback probability and original/reconciled provenance explicitly.</verify>
<done>Offline retries yield one real session and one row per logical decision, preserve offline truth, and never leak replay-time future data into historical decisions.</done>
</task>
</tasks>
<verification>All tests are future approved isolated-fixture runs. Full unfiltered output; ask for backend lint/typecheck rather than inventing one.</verification>
<success_criteria>Authoritative API and replay contract are independently evidenced before mobile consumes them.</success_criteria>
<output>.planning/phases/cognitive-games-ml/B-03-SUMMARY.md with exact JSON contracts, stable-ID protocol and linked audit proof. No commits.</output>

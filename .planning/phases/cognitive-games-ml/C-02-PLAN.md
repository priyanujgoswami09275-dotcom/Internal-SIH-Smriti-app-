# UNAPPROVED — REPLAN REQUIRED; NEVER AUTOEXECUTE

The single six-hour B-01 plan and one final B report replace the former B chain. Everything below preserves the old C proposal, including full-stack B authority, scoring and replay assumptions; these are not active requirements or approved dependencies. Replan C after the B report and obtain explicit approval before execution. Risk/difficulty independence remains binding.

---
phase: cognitive-games-ml
plan: C-02
type: tdd
wave: 10
depends_on: [C-01]
files_modified:
  - backend/app/routes/games.py
  - backend/app/services/game_service.py
  - backend/app/tests/test_four_game_sessions.py
  - backend/app/tests/test_phase5_game_stats.py
  - backend/app/tests/test_level_config_matrix.py
autonomous: false
must_haves:
  truths:
    - Four games use the same session/action/scoring/audit shape and B policy.
    - Stored board snapshots determine scoring, not client-declared correctness.
    - Each of four game types contributes to existing pooled aggregation without dashboard changes.
  artifacts:
    - path: backend/app/services/game_service.py
      provides: Four-game action registry and snapshot-based scoring integration
    - path: backend/app/tests/test_four_game_sessions.py
      provides: Per-game scoring, progression, audit and replay contract coverage
    - path: backend/app/tests/test_phase5_game_stats.py
      provides: Four-game pooled aggregation proof
  key_links:
    - from: backend/app/routes/games.py
      to: backend/app/services/odd_one_out_service.py
      via: Session-bound board endpoint and selection scoring
    - from: backend/app/services/game_service.py
      to: backend/app/services/difficulty_engine.py
      via: Existing B authoritative decision, unknown ML strata use explicit fallback
---

<objective>Integrate the fourth game and prove cross-game analytics through existing backend paths.</objective>
<context>
@.planning/phases/cognitive-games-ml/ROADMAP.md
@.planning/phases/cognitive-games-ml/B-03-SUMMARY.md
@.planning/phases/cognitive-games-ml/C-01-SUMMARY.md
@backend/app/services/recall_service.py
@backend/app/services/routine_service.py
@backend/app/services/content_packs.py
</context>
**PROVISIONAL:** B report/C approval required. No implementation this turn. Dashboard implementation and archived engine remain unchanged.
<tasks>
<task type="auto">
<name>1. Extend the common action/session path to all four games</name>
<files>backend/app/routes/games.py; backend/app/services/game_service.py; backend/app/tests/test_four_game_sessions.py; backend/app/tests/test_level_config_matrix.py</files>
<action>Add GET /games/odd-one-out/board for an owned session, using B assignment, level_config_service and C-01 generator; save answer in existing B board snapshot. Implement explicit action registry in game_service for Match It flip_card, Routine place_step, existing Recall show_sequence/recall_tap (verify actual RecallActions strings before editing), and Odd-One-Out select_odd_item. Resolved attempts update shared metrics; informational events remain metric-free. Derive correctness from stored board/session state (pair identity, expected step/position, sequence digit or odd item), not is_correct/expected fields from client; preserve envelope and legacy history, reject or explicitly classify unscorable legacy events rather than invent validated errors. Attach standardized category/opportunity metadata for B extractor. Reuse existing scorers when compatible; keep small adapters in game_service, no new engine. Validate timing/order/session completion and deduplicate via B protocol for online and replay. Four-game boards and decisions obey B source/probability bounds/config version; Odd-One-Out with no trained support uses reason unsupported_game/category rather than forcing model prediction. Test shared config overrides, server correctness, invalid action types, informational counts, scoring accuracy/time and audit linkage for all four.</action>
<verify>Future backend cwd: python3 -m pytest app/tests/test_four_game_sessions.py app/tests/test_level_config_matrix.py app/tests/test_number_recall.py -q. Include all 4 games x 3 levels and an unknown ML-stratum fallback case; no fabricated learned support for Odd-One-Out.</verify>
<done>All four games use server scoring and the shared B decision/audit contract; existing Number Recall behavior is retained and extended, not duplicated.</done>
</task>
<task type="auto">
<name>2. Prove pooled dashboard contribution and replay stability</name>
<files>backend/app/tests/test_four_game_sessions.py; backend/app/tests/test_phase5_game_stats.py</files>
<action>Use local consented clinical fixtures to complete one session per game through common HTTP routes and read existing /games/patients/{id}/stats. Assert overall.sessions=4 and exact attempt-weighted accuracy, mean of session response averages and day bucket counts from known unequal attempts/time fixtures; vary/remove each game's contribution in separate fixtures to prove every type affects aggregate. Do not change stats/dashboard implementation; document pooled series versus four separate series and existing start-time/no-completed-filter semantics. Include each session's B decision record, source/reason/probability/version and repeat offline synchronization/completion proving counts/audit remain unchanged. Keep separate tests for scoring/progression of all games including max/min and error-pattern veto/fallback; an aggregate chart test alone is insufficient. Unsupported Odd-One-Out model strata remain fallback until retraining support exists.</action>
<verify>In backend: python3 -m pytest app/tests/test_four_game_sessions.py app/tests/test_phase5_game_stats.py -q; python3 -m pytest app/tests tests -q. Record exact pooled arithmetic and one-log-per-decision assertions.</verify>
<done>Fresh tests prove all four contribute to the unchanged pooled endpoint and deduplication preserves metrics; no claim of separate per-game charts.</done>
</task>
</tasks>
<verification>No dashboard implementation edits. Full test output, no stale counts; data is isolated/disposable.</verification>
<success_criteria>Four-game scoring/session/config/progression/audit and pooled aggregation are evidenced.</success_criteria>
<output>.planning/phases/cognitive-games-ml/C-02-SUMMARY.md including action registry, scoring contract, matrix and pooled arithmetic evidence. No commit.</output>

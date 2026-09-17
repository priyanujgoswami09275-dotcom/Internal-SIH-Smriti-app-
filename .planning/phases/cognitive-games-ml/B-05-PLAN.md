# SUPERSEDED — inactive archival methodology; NEVER AUTOEXECUTE

Replaced by the single 1-working-day / 6-hour B-01 plan. Everything below is historical, including mobile authority work, gates and outputs; it imposes no current requirement. Optional future work requires a separate user-approved task.

---
phase: cognitive-games-ml
plan: B-05
type: execute
wave: 7
depends_on: [B-04]
files_modified:
  - mobile/lib/screens/match_it_screen.dart
  - mobile/lib/screens/routine_screen.dart
  - mobile/lib/screens/recall_screen.dart
  - mobile/test/adaptive_screens_test.dart
  - mobile/test/game_analytics_engine_test.dart
autonomous: false
must_haves:
  truths:
    - All three existing games use the server-assigned level and next decision online.
    - Offline result views clearly label conservative fallback without unsupported ML/risk claims.
    - Number Recall is reused rather than recreated.
  artifacts:
    - path: mobile/lib/screens/recall_screen.dart
      provides: Existing Number Recall wired to shared B contract
    - path: mobile/test/adaptive_screens_test.dart
      provides: Three-game authority, fallback and replay assertions
  key_links:
    - from: mobile/lib/screens/match_it_screen.dart
      to: mobile/lib/services/api_service.dart
      via: startGameWithDecision and completion decision consumption
    - from: mobile/lib/screens/routine_screen.dart
      to: mobile/lib/games/level_config.dart
      via: Assigned-level board parameters with cache/bundled fallback
    - from: mobile/lib/screens/recall_screen.dart
      to: mobile/lib/services/offline_sync_service.dart
      via: Buffered actions and known server identity survive partial failure
---

<objective>Replace active divergent mobile progression with the shared server/offline contract across existing games.</objective>
<context>
@.planning/phases/cognitive-games-ml/ROADMAP.md
@.planning/phases/cognitive-games-ml/B-04-SUMMARY.md
@mobile/lib/games/game_analytics_engine.dart
@mobile/lib/theme/monad_theme.dart
</context>
**PROVISIONAL:** Requires approved B scope. No implementation this turn. No extra game, level map or clinical-risk UI.
<tasks>
<task type="auto">
<name>1. Wire existing screens to server assignment and completion</name>
<files>mobile/lib/screens/match_it_screen.dart; mobile/lib/screens/routine_screen.dart; mobile/lib/screens/recall_screen.dart; mobile/test/adaptive_screens_test.dart</files>
<action>Use B-04 startGameWithDecision in each screen; set _difficulty to server assignment before requesting a session-bound board. Keep LevelConfig.refresh and cached/bundled fallback; do not assume requested difficulty equals server-assigned difficulty. After completion consume summary.decision as the sole online next-level result and result label, bypass local three-agreeing progression. Use actual patient profile identity from existing API/auth flow. Await/track action submission before completing so failed actions remain buffered with stable IDs; preserve known server session ID in partial failure replay. For genuine connectivity failure keep conservative offline decision and pending-sync label, no upward progression. Authentication/consent denial is not silently treated as offline authorization to upload later. Display Monad visuals and explicit source/reason; probability is success probability, not confidence, and may stay hidden rather than mislead. Remove sensitive performance debug payload logging on these paths. Preserve Number Recall memorization/tap logic and Match It/Routine scoring shape.</action>
<verify>Future mobile cwd: flutter test test/adaptive_screens_test.dart. Parameterize three screens for differing requested/server level, completion decision, failed/queued action and no-local-online-override behavior.</verify>
<done>Every existing game consumes authoritative online level/result; partial failures queue stable data and offline state is visible without clinical claims.</done>
</task>
<task type="auto">
<name>2. Pin the new contract against divergent legacy expectations</name>
<files>mobile/test/adaptive_screens_test.dart; mobile/test/game_analytics_engine_test.dart</files>
<action>Update old tests that asserted the mobile three-agreeing/time progression to assert server authority and separately labeled offline conservative behavior; do not weaken unrelated analytics/tag tests. Cover 0/1/2 and 3 completed session envelopes, server raise/hold/lower, min/max, nullable fallback probability, localized-error-veto reason rendering, cold start and repeat result rendering without re-evaluation. All three screen flows must request boards for assigned levels and feed completion decisions into subsequent starts. Use existing test dependencies; device visuals are not certified by widget tests. If dependency injection beyond the named screens is necessary, stop and replan rather than exceeding five files.</action>
<verify>In mobile: flutter test test/adaptive_screens_test.dart test/game_analytics_engine_test.dart; flutter test; flutter analyze. In backend: python3 -m pytest app/tests tests -q. Record new complete outputs, no suppressed failures.</verify>
<done>Regression tests no longer endorse conflicting online rules; current test/analyzer results are ready for B report, with any failures honestly listed.</done>
</task>
</tasks>
<verification>No physical-device validation claim. Missing backend lint/typecheck command remains unresolved until provided.</verification>
<success_criteria>All existing games are wired and regression evidence is available; B stays gated until B-06.</success_criteria>
<output>.planning/phases/cognitive-games-ml/B-05-SUMMARY.md with per-screen source proof and full verification outcomes. No commit.</output>

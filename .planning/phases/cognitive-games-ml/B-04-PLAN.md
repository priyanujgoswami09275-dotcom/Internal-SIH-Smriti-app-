# SUPERSEDED — inactive archival methodology; NEVER AUTOEXECUTE

Replaced by the single 1-working-day / 6-hour B-01 plan. Everything below is historical, including mobile/replay work, gates and outputs; it imposes no current requirement. Optional future work requires a separate user-approved task.

---
phase: cognitive-games-ml
plan: B-04
type: tdd
wave: 6
depends_on: [B-03]
files_modified:
  - mobile/lib/services/api_service.dart
  - mobile/lib/models/game_models.dart
  - mobile/lib/games/game_analytics_engine.dart
  - mobile/lib/services/offline_sync_service.dart
  - mobile/test/adaptive_contract_test.dart
autonomous: false
must_haves:
  truths:
    - Mobile can consume server decisions without replacing probability with confidence.
    - Offline decisions are labeled conservative fallback and cannot promote difficulty.
    - Replay retains stable identifiers and provenance across partial failures.
  artifacts:
    - path: mobile/lib/models/game_models.dart
      provides: Typed server decision/start/summary envelope
    - path: mobile/lib/services/offline_sync_service.dart
      provides: Existing queue replay with stable session/action identities
    - path: mobile/test/adaptive_contract_test.dart
      provides: Online/offline parsing and reconciliation contract tests
  key_links:
    - from: mobile/lib/services/api_service.dart
      to: mobile/lib/models/game_models.dart
      via: Start and complete responses preserve B-03 decision metadata
    - from: mobile/lib/services/offline_sync_service.dart
      to: backend/app/routes/games.py
      via: Stable client_session_id/action_id replay protocol
---

<objective>Supply shared mobile authority/fallback contracts without yet editing the three screens.</objective>
<context>
@.planning/phases/cognitive-games-ml/ROADMAP.md
@.planning/phases/cognitive-games-ml/B-03-SUMMARY.md
@mobile/lib/database/app_database.dart
@mobile/lib/games/level_config.dart
</context>
**PROVISIONAL:** Requires the accepted A report and explicit B approval; the B report is produced later by B-06, after B-04. No implementation this turn. B-05 is required to finish active screen wiring.
<tasks>
<task type="auto">
<name>1. Parse server decisions and isolate conservative offline policy</name>
<files>mobile/lib/services/api_service.dart; mobile/lib/models/game_models.dart; mobile/lib/games/game_analytics_engine.dart; mobile/test/adaptive_contract_test.dart</files>
<action>Write tests for a typed DifficultyDecision and GameStartResult matching B-03; add startGameWithDecision while retaining the old String-returning startGame wrapper for compatibility. Extend GameSessionSummary parsing with nullable decision without fabricating values for older responses. Board API methods accept session ID to retrieve assigned-level snapshots. Make analytics reporting separate from authoritative difficulty: accept an optional server decision, preserve server new level/source/probability/version and avoid local streak recalculation online. Offline or missing-decision response returns labeled rule_fallback, probability null, reason offline or server_contract_missing; conservative hold or one-step lowering only, bounded 1–3, never promotion. Offline lowering follows observed support (two completed low-accuracy sessions), not the old three-verdict/time engine; it is explicitly not an ML decision. Key state by actual patient profile and game, not caregiver/user ID. Do not add risk feature logs or new comments. Existing screen call signatures remain compilable until B-05.</action>
<verify>Future mobile cwd: flutter test test/adaptive_contract_test.dart. Test exact server value preservation, null legacy probability, invalid finite/bounds handling, separate patient/game histories, no offline promotion and no duplicate local history accumulation.</verify>
<done>Shared types carry provenance honestly and fallback cannot claim confidence/ML authority; old screens still compile pending B-05.</done>
</task>
<task type="auto">
<name>2. Update replay payloads and prove resumable reconciliation</name>
<files>mobile/lib/services/offline_sync_service.dart; mobile/lib/services/api_service.dart; mobile/lib/models/game_models.dart; mobile/test/adaptive_contract_test.dart</files>
<action>Reuse existing SyncQueueItem JSON payload rather than adding a mobile DB migration/generated file. Persist stable local session identity, known server ID, original timestamps, decision snapshot, board/config identity and action IDs. Replay via B-03 live session endpoints with stable keys, resume known server session, resend safely after timeout and retain offline source/probability null. Mark queued item synced only after authoritative completion acknowledgment; failures remain retryable. Preserve reconciliation mapping inside queue payload/response; subsequent next-game decisions come from server, not duplicate local audit. Ensure compatibility with existing stored queue items using conservative legacy_missing_metadata handling; do not invent original timestamps or ML provenance. Add transport/database-fake contract tests for offline enqueue, partial online failure, restart/retry and one logical session/decision. These mobile transport fakes are not substitutes for A's real-artifact endpoint gate or B's fitted model tests.</action>
<verify>In mobile: flutter test test/adaptive_contract_test.dart; flutter test; flutter analyze. Capture full exit status/output; do not reuse the historical 45 findings as today's result.</verify>
<done>Retry uses stable IDs and preserves offline/online provenance; no new generated DB files and no premature queue deletion.</done>
</task>
</tasks>
<verification>Backend integration proof remains B-03; mobile tests establish request/response consistency. Analyzer failures are reported without masked exits.</verification>
<success_criteria>Shared mobile contract is ready for all existing screens and later Odd-One-Out.</success_criteria>
<output>.planning/phases/cognitive-games-ml/B-04-SUMMARY.md with parsing/fallback/replay evidence. No commit or auto-advance.</output>

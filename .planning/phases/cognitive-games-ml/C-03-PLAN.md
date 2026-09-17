# UNAPPROVED — REPLAN REQUIRED; NEVER AUTOEXECUTE

The single six-hour B-01 plan and one final B report replace the former B chain. Everything below preserves the old C proposal, including full-stack B mobile authority and replay assumptions; these are not active requirements or approved dependencies. Replan C after the B report and obtain explicit approval before execution. Risk/difficulty independence remains binding.

---
phase: cognitive-games-ml
plan: C-03
type: execute
wave: 11
depends_on: [C-02]
files_modified:
  - mobile/lib/screens/odd_one_out_screen.dart
  - mobile/lib/models/shared_models.dart
  - mobile/lib/main.dart
  - mobile/lib/games/level_config.dart
  - mobile/test/odd_one_out_screen_test.dart
autonomous: false
must_haves:
  truths:
    - Home offers exactly four games with existing Number Recall reused.
    - Odd-One-Out uses Monad visuals, existing assets, server decisions and shared config.
    - Offline play is conservative and reconciles through the same B queue contract.
  artifacts:
    - path: mobile/lib/screens/odd_one_out_screen.dart
      provides: Focused Odd-One-Out board parsing, action binding and UI flow
    - path: mobile/lib/games/level_config.dart
      provides: Fourth-game canonical bundled mirror and cached params
    - path: mobile/test/odd_one_out_screen_test.dart
      provides: Config, selection, source labels and four-game navigation checks
  key_links:
    - from: mobile/lib/main.dart
      to: mobile/lib/screens/odd_one_out_screen.dart
      via: Fourth game home entry using existing Monad navigation
    - from: mobile/lib/screens/odd_one_out_screen.dart
      to: mobile/lib/services/api_service.dart
      via: Existing getJson/postJson and B typed start/complete contract
    - from: mobile/lib/screens/odd_one_out_screen.dart
      to: mobile/lib/services/offline_sync_service.dart
      via: Existing B queue with stable IDs and board/decision snapshot
---

<objective>Make the fourth game playable through shared infrastructure without new art or duplicate Recall.</objective>
<context>
@.planning/phases/cognitive-games-ml/ROADMAP.md
@.planning/phases/cognitive-games-ml/B-04-SUMMARY.md
@.planning/phases/cognitive-games-ml/C-02-SUMMARY.md
@mobile/lib/screens/recall_screen.dart
@mobile/lib/games/game_visuals.dart
@mobile/lib/data/local_content_packs.dart
@mobile/lib/theme/monad_theme.dart
</context>
**PROVISIONAL:** Requires accepted B report, explicit C approval and existing API/queue contracts. No implementation this turn. Word mode excluded unless plans are revised and approved.
<tasks>
<task type="auto">
<name>1. Add the fourth enum/navigation/config slice</name>
<files>mobile/lib/models/shared_models.dart; mobile/lib/main.dart; mobile/lib/games/level_config.dart; mobile/lib/screens/odd_one_out_screen.dart; mobile/test/odd_one_out_screen_test.dart</files>
<action>Add GameType.oddOneOut and exact API mapping odd_one_out, retaining existing three values and Number Recall routing. Add a fourth home game card with Monad widgets and no new assets. Extend bundled LevelConfig with C-approved canonical Odd-One-Out params (3/4/6 items and 45/70/120 target seconds if ratified) and generic/specific accessor; screen must consume synced/cached/bundled params, never hardcode a second progression map. Use a focused screen file containing its small typed board parser/action identifiers rather than multiplying files; use existing public ApiService.getJson with configured API prefix for board fetching and existing B typed start/complete methods. Mirror existing screen lifecycle and Monad theme. Tests assert four distinct API mappings/home destinations, no fifth word game, retained Number Recall, and server config override changes board item count/timing.</action>
<verify>Future mobile cwd: flutter test test/odd_one_out_screen_test.dart test/level_config_test.dart test/recall_service_test.dart. If existing hard-coded game-count assertions outside the listed files need changes, stop and revise the plan's five-file budget instead of silently expanding scope.</verify>
<done>Exactly four enum/navigation entries and canonical config access exist; existing Recall remains intact.</done>
</task>
<task type="auto">
<name>2. Implement selections, source labels and shared replay</name>
<files>mobile/lib/screens/odd_one_out_screen.dart; mobile/test/odd_one_out_screen_test.dart</files>
<action>Start using B server assignment, fetch session-bound board, render existing game_visuals art by stable item ID, send select_odd_item with selected ID/action ID/time and consume server correctness/summary. Keep server answer out of online authority; local preview feedback is not scoring truth. Show next level and source/reason from B completion, not an independent local rule. Offline uses an available cached board/snapshot and shared conservative fallback; if no compatible cached board exists show explicit connect-to-download state instead of synthesizing unsupported taxonomy/art. Queue completed cached-board play using B stable IDs/original timestamps/snapshot and label pending synchronization; no duplicate audit on retry. Include selected/wrong/correct states, accessible tap targets/labels, calm Monad result view, cancellation/disposal and bounded timers. Tests cover correct/incorrect selection, informational versus resolved attempts, all three config levels, no promotion offline, reconnect retry, server-level mismatch, unavailable cached content, known error-veto reason and source labels. Reuse existing API/queue injection seams; do not add another training/model/policy implementation or visual-similarity grading.</action>
<verify>In mobile: flutter test test/odd_one_out_screen_test.dart; flutter test; flutter analyze. Backend cwd: python3 -m pytest app/tests tests -q. Record full outcomes and classify new versus existing analyzer findings from fresh output.</verify>
<done>Odd-One-Out completes via shared scoring/session/decision flow with honest offline behavior; automated tests pass or report explicit blockers, without claiming device validation.</done>
</task>
</tasks>
<verification>Physical target/browser inspection belongs only to C-04. No dashboard/art/generated DB files changed.</verification>
<success_criteria>Four games are reachable and fourth-game contract is verified by tests; C gate still pending.</success_criteria>
<output>.planning/phases/cognitive-games-ml/C-03-SUMMARY.md with UI/contract test evidence and pending device note. No commit.</output>

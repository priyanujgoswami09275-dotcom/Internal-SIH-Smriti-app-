# C-03-SUMMARY (implemented 2026-09-21, commit 78b172c)

- Nav/config: `GameType.oddOneOut ↔ odd_one_out`; fourth home card appended (existing three
  restored byte-for-byte after review); bundled `odd_one_out` map + `oddOneOutItems()`.
- Screen: typed start, session-bound board fetch, `GameVisuals.face` tiles (no new art),
  `select_odd_item` + server verdict parsing **including the event envelope**
  (`event.is_correct`, `event.action_data.is_correct` first), completion summary parsed to
  existing summary fields only, Next/Source/Reason rows shown only when non-null.
- Offline: cached-board play queued with `act_<ms>_<seq>_<item>` IDs + original timestamps,
  pending-sync labeling; no cache → connect-to-download; no offline promotion; reconnect
  retry without duplicate audit.
- Evidence: 23 widget tests (mappings, override 5-items/90s, correct/incorrect incl. real
  echo shape, informational vs resolved, 3 levels, mismatch adopts server level, dispose,
  offline queue, no-cache, retry, hidden-rows); `flutter test` all-pass, `flutter analyze`
  zero new findings. SDD review: Approved after fix round (envelope, append-only menu,
  id uniqueness, key alignment).
- Limits: widget tests only — no device validation (pending, see C-REPORT); dialog
  Next/Source/Reason path is test-only until a backend source exists for those keys.

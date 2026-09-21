# C-02-SUMMARY (implemented 2026-09-21, commit daa64b8)

- Board: `GET /games/odd-one-out/board?session_id&level` — require_patient + owned session +
  caller profile + `game_data` consent; DB-resolved params; answer stored in
  `session.board_snapshot`, response carries no answer; bad level → 422.
- Scoring: `select_odd_item{selected_item_id}` — correctness from stored answer via
  `score_odd_one_out`; client `is_correct` ignored for this action; server verdict +
  `error_category`/`opportunity` persisted in the event; NULL snapshot → 422 verbatim;
  other games unchanged.
- Adaptive: odd_one_out → `unsupported_game` fallback (`adaptive_features.py:66`,
  `adaptive_shadow.py:80`); `evaluate_difficulty` untouched, `source=rule_fallback`;
  semantic errors never enter the 3-category vector.
- Evidence: 23 four-game tests (withheld answer, tamper both directions, 422, 4×3 flow,
  pooled stats movement, shadow fallback, repeat-complete stability) + matrix extension;
  full suite 469 passed / 7 skipped at final HEAD. SDD review: Approved after fix round
  (typed `OddOneOutItem` model); recorded-minor kept: `game_service.py` docstring gained
  an accurate Number Recall entry.
- Limits: no per-game stats series; no historical-migration rewrite; endpoint does not
  enforce `session.game_type` (inert — scorer gate covers it).

# C-01-SUMMARY (implemented 2026-09-21, commit d82490e)

R0 taxonomy/params ratified by default (Option A — user authorized full build without
selecting; see C-REPLAN.md §5 handoff and final-report rulings).

- Enum: `ODD_ONE_OUT='odd_one_out'` → exactly four `GameTypeEnum` values; Recall untouched.
- Config: `odd_one_out` L1–L3 = items 3/4/6, target_seconds 45/70/120 (seeds + DEFAULT).
- Generator/scorer: seeded deterministic boards, majority + disjoint odd, exactly one
  answer, no dup IDs; scorer returns `correct / semantic_category / opportunity`.
- Migration `0010_odd_one_out` (down `0009_shadow_difficulty`): PG enum add (dialect-guarded),
  nullable `board_snapshot` on `game_sessions`, 3 seeds; downgrade removes rows only
  (enum/column retention documented).
- Evidence: 7 new service tests + migration round-trip (SQLite, legacy NULL row preserved);
  full suite 444 passed / 7 skipped at this commit. SDD task review: Approved, no findings.
- Limits: L3 majority festivals-only; 0010 deployed nowhere (host/compose stay on 0008/0009).

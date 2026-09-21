# C-REPORT — Odd-One-Out fourth game (implementation)

Date: 2026-09-21. Built under user-approved C-REPLAN.md (R0 Option A: L3 majority =
festivals only). Exactly four games; Number Recall (`6a2af63`) reused unchanged; only new
enum/migration is Odd-One-Out. No model activation, calibration, promotion tooling,
authority unification, dashboard change, or new art at any step.

## What shipped (commits on `chore/deployment-readiness`)

- `d82490e` C-01' backend domain/config: `GameTypeEnum.ODD_ONE_OUT`, `GameSession.board_snapshot`
  (nullable JSON), `odd_one_out_service.py` (R0 taxonomy, seeded generator, scorer with
  `error_category='semantic_category'`), `DEFAULT_LEVEL_CONFIG["odd_one_out"]`
  (3/45, 4/70, 6/120), migration `0010_odd_one_out` (PG enum add dialect-guarded, seeds,
  rows-only downgrade), 7 service tests + migration round-trip test.
- `daa64b8` C-02' session/action integration: `GET /games/odd-one-out/board` (patient +
  owned session + `game_data` consent; answer stored server-side, never served),
  `select_odd_item` server-truth scoring (client `is_correct` ignored; NULL snapshot →
  422), adaptive fallback (`unsupported_game`, rules authority intact, no 3-vector
  folding), 23 four-game tests + level-config matrix extension.
- `78b172c` C-03' mobile: `GameType.oddOneOut`, fourth home card (append-only),
  `odd_one_out_screen.dart` (server-truth verdict parsing incl. event envelope, honest
  offline states, no local promotion), bundled config mirror + accessor, 23 widget tests.

## Verification (first-hand where stated)

- Backend full suite, controller-run 2026-09-21, pinned Python 3.12.14:
  **469 passed, 7 skipped** (`cd backend && .venv-demo/bin/python -m pytest app/tests tests -q`).
- Mobile full suite, controller-run 2026-09-21: **all passed (+80 ~5)**
  (`cd mobile && flutter test`); `flutter analyze` 45 issues, all pre-existing, zero in
  touched files. SDD per-task reviews clean (Tasks 1–3 Approved; two fix rounds, all closed).
- `git diff --check` clean. Graph refreshed (`graphify update .`, 4662 nodes).
- Migration proof: SQLite upgrade/downgrade/re-upgrade preserving legacy rows (test).
  0010 **not applied** to host or compose databases; demo server schema untouched.

## Pooled contribution

Per-game fixtures prove each of the four games moves the unchanged pooled
`/patients/{id}/stats` aggregate; repeat completion stable; one-log-per-decision for
odd_one_out with `source=rule_fallback` + `unsupported_game` shadow reason. No separate
per-game series claimed; dashboard implementation unchanged.

## Device/browser checkpoint: PENDING

Attached targets exist (macOS desktop, Chrome) but the patient app is Android/iOS
(`dart:io` + drift block web builds), and manual play needs isolated-backend/data
approval (never granted) — the populated demo DB must not be touched. No device run
performed; widget tests are not device validation. Browser testing would prove browser
behavior only and was not run.

## Standing limits

- Odd-One-Out has no trained-model support by design (shadow `unsupported_game` fallback);
  retrain support needs a separately approved task (B extractor is 3-category by contract).
- L3 majority = festivals only (content insufficiency, not a code gap); fruit/attire max
  out at L2; instruments/animals at L1.
- `backend/eldercare.db` (untracked, pre-existing) was never a test dependency
  (`:memory:` SQLite) and is not committed.
- Backend lint/typecheck unrun (commands unspecified); risk screening untouched and still
  experimental/not validated; backend/mobile authority still divergent.

## Gate

User decision 2026-09-21: **accept-with-deferred-validation** — code, tests, and review
accepted as solid; the device play-test is genuinely outstanding, not a formality. It is
recorded here as an explicit deferral, not waived: manual play against an isolated
backend on an attached target remains required before any demo-day claim, and no
activation/calibration/promotion work is authorized by this acceptance.

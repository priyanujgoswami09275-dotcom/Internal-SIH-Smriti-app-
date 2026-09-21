# C-REPLAN — fourth game (Odd-One-Out) scoped to post-B-01 reality

> **Status:** REPLAN ONLY — unapproved for implementation. Old `C-01-PLAN.md`…`C-04-PLAN.md`
> remain **UNAPPROVED / NEVER AUTOEXECUTE**; this document replaces their dependencies,
> migration numbers, and contract assumptions. No code, tests, DB operations, or commits
> were performed to produce it. C implementation needs a separate explicit approval.

**Goal:** Add exactly one new game, Odd-One-Out, to the existing three (Match It, Routine
Sequencing, Number Recall) through shared session/scoring/config/decision paths, with the
B-01 shadow model untouched and rules sole authority.

**Architecture:** Backend domain slice (enum + config + generator/scorer) → session/action
integration on existing routes → mobile screen on existing API/queue seams → report +
device checkpoint. Each slice is independently testable; no new engine, progression map,
art, dashboard change, or model activation at any step.

**Tech Stack:** FastAPI + SQLAlchemy + Alembic + PostgreSQL backend; Flutter mobile;
existing `game_level_config` + `DifficultyAdjustmentLog` + `evaluate_difficulty` contracts.

**Spec:** `.planning/phases/cognitive-games-ml/B-REPORT.md` (sole B deliverable),
`ROADMAP.md` (binding B contract), `STATE.md` (runtime evidence), old `C-01..C-04-PLAN.md`
(archival proposals only).

## Global Constraints

- Risk/difficulty independence is binding: no risk input, prior, calibration, missingness,
  or screening reads/joins anywhere in C.
- Every returned level uses exact existing rules (`difficulty_engine.py:48`); applied
  `source=rule_fallback` always; shadow fields stay nullable and separate.
- Exactly four games; word mode is not a fifth game; no new art, no visual-similarity
  grading, no new progression map, no dashboard implementation change.
- Mobile/backend authority stays divergent (`game_analytics_engine.dart:207` untouched);
  unification is a separate optional task, not a C requirement.
- Backend lint/typecheck commands remain unspecified — never claim them run.

---

## 1. Post-B-01 ground truth (what the old C plans get wrong)

| # | Old assumption | Current truth | Correction |
|---|---|---|---|
| 1 | Migration `0009_odd_one_out` after head `0008_*` | `0009_shadow_difficulty` (19-char id) is committed (`7f650ac`); head is now 0009 | New migration is **`0010_odd_one_out`** (16 chars, within 32-char limit), `down_revision` = verified head at execution time; run `alembic heads` first, stop/replan on mismatch |
| 2 | `depends_on: [B-06]`, B-06-gated config (3/4/6 items, 45/70/120s) | B-02–B-06 superseded; B-01 is the only B | Those numbers are **proposed defaults needing ratification in gate R0**, not approved values |
| 3 | C-02 context cites `B-03-SUMMARY.md`, `C-01-SUMMARY.md`; C-03 cites `B-04-SUMMARY.md` | None of those files exist | Drop all three references; cite `B-REPORT.md` + this replan only |
| 4 | "B authoritative decision" as full-stack/mobile authority | B-01 scope: backend shadow only; no mobile changes; authority divergent | Mobile consumes server assignment display-only; offline never promotes; no unification claim |
| 5 | New-game ML support assumed eventually in-plan | B extractor vector is fixed `[mismatch, sequence_position, recall_position]`; Odd-One-Out errors are `semantic_category` | Semantic errors are **never folded into the 3-vector**; Odd-One-Out shadow uses reason `unsupported_game`/`unsupported_category` fallback until a separately approved retrain adds support |
| 6 | Board/session endpoints staff-gated (pre-B-01 shape) | B-01 review fix: `POST /difficulty/evaluate` enforces patient access + active `game_data` consent | New `GET /games/odd-one-out/board` must enforce the same gate from day one |
| 7 | 0009 deploy assumed available | 0009 applied nowhere (host + compose stay on 0008); demo server runs schema 0008 | C migration deploys only with backup + explicit approval; never imply host mutation |

## 2. Decision gate R0 (docs-only, before any C slice)

Taxonomy/config choice is a user decision, not an implementer detail. Present and get
explicit sign-off on:

- **a. Curated ID taxonomy** built only from existing `content_packs.py` item IDs, using
  disjoint semantic groups (never geographic category-as-semantics). Candidate groups from
  the old proposal: festivals (bihu/hornbill/chapchar_kut/nongkrem/losar/sangken), edible
  fruit (kaji_nemu/ou_tenga/jolpai/starfruit), animals (rhino/red_panda), instruments
  (dhol/pepa). Each group must have `item_count - 1` distinct members with verified
  asset/registry keys.
- **b. Level params:** proposed 3/4/6 items with target_seconds 45/70/120 — ratify or amend.
- **c. L3 sufficiency:** if no group yields five unambiguous existing members, the answer is
  a recorded **content-insufficiency report**, not invented art.
- **d. Number Recall reuse** (`6a2af63`) untouched; exactly four enum values after C.

R0 output: taxonomy table + params sign-off appended to this file. No R0 sign-off → no C-01'.

## 3. Revised slices (supersede old C-01..C-04 on approval)

### Slice C-01' — Odd-One-Out domain + config (backend, TDD)

**Files:**
- Modify: `backend/app/models/all_models.py` (add `ODD_ONE_OUT='odd_one_out'`)
- Create: `backend/alembic/versions/0010_odd_one_out.py`
- Modify: `backend/app/services/level_config_service.py` (3 R0-ratified rows)
- Create: `backend/app/services/odd_one_out_service.py` (`generate_board`, `score_selection`)
- Create: `backend/app/tests/test_odd_one_out.py`

**Interfaces:**
- Consumes: `content_packs` item IDs/names/assets; `level_config_service` canonical params.
- Produces: `generate_board(params, seed) -> board{game_type, difficulty_level, config_version,
  items, answer_item_id}`; `score_selection(board_snapshot, selected_item_id) ->
  {correct, error_category='semantic_category', opportunity}`. Server holds the answer;
  correctness derives from stored snapshot, never client claims.

- [ ] **Step 1:** `alembic heads` on approved env; confirm head is `0009_shadow_difficulty`.
- [ ] **Step 2:** Failing test — four enum values, config levels 1–3, deterministic seeded
  boards, exactly one answer, ambiguous/unknown taxonomy rejected.
- [ ] **Step 3:** Minimal implementation; populated disposable-PostgreSQL upgrade preserves
  Number Recall/session/audit rows; downgrade removes new rows only (document enum retention).
- [ ] **Step 4:** Full backend suite green; record counts.
- [ ] **Step 5:** Write `.planning/phases/cognitive-games-ml/C-01-SUMMARY.md`. No commit.

### Slice C-02' — session/action integration + pooled proof (backend, TDD)

**Files:**
- Modify: `backend/app/routes/games.py` (`GET /games/odd-one-out/board`, patient access +
  `game_data` consent gate), `backend/app/services/game_service.py` (action registry:
  `flip_card`, `place_step`, `show_sequence`/`recall_tap`, `select_odd_item`)
- Create: `backend/app/tests/test_four_game_sessions.py`
- Modify (tests only): `test_phase5_game_stats.py`, `test_level_config_matrix.py`

**Interfaces:**
- Consumes: C-01' generator/scorer; `evaluate_difficulty` rules path; `DifficultyAdjustmentLog`.
- Produces: server-scored selections for all four games; standardized category/opportunity
  metadata; Odd-One-Out shadow rows carry `unsupported_game`/`unsupported_category` reason.

- [ ] **Step 1:** Failing tests — 4 games × 3 levels server correctness; unknown ML stratum
  falls back; client `is_correct` never trusted; unscorable legacy events classified.
- [ ] **Step 2:** Minimal integration; pooled `/games/patients/{id}/stats` contribution proven
  per-game (vary/remove each fixture); one-log-per-decision asserted; replay dedup stable.
- [ ] **Step 3:** Full suite green; record pooled arithmetic explicitly.
- [ ] **Step 4:** Write `C-02-SUMMARY.md`. No dashboard edits, no commit.

### Slice C-03' — mobile fourth game (Flutter, existing seams only)

**Files:**
- Modify: `mobile/lib/models/shared_models.dart` (`GameType.oddOneOut` ↔ `odd_one_out`),
  `mobile/lib/main.dart` (fourth home card), `mobile/lib/games/level_config.dart` (bundled mirror)
- Create: `mobile/lib/screens/odd_one_out_screen.dart`, `mobile/test/odd_one_out_screen_test.dart`

**Interfaces:**
- Consumes: `ApiService.getJson/postJson`, B typed start/complete, `offline_sync_service`
  queue, `game_visuals` art by stable item ID.
- Produces: board play with server-truth scoring display, source/reason labels, honest
  offline states (cached-board play queued with stable IDs; no compatible cache →
  explicit connect-to-download, never synthesized taxonomy).

- [ ] **Step 1:** Failing widget tests — four mappings/destinations, no fifth game, Recall
  intact, server config override changes item count/timing.
- [ ] **Step 2:** Minimal screen; correct/incorrect/preview/cancel/dispose/timer states;
  reconnect retry without duplicate audit.
- [ ] **Step 3:** `flutter test`, `flutter analyze`; backend suite green; classify new vs
  pre-existing analyzer findings.
- [ ] **Step 4:** Write `C-03-SUMMARY.md` with pending-device note. No commit.

### Slice C-04' — report + device checkpoint (no implementation)

- [ ] **Step 1:** Assemble `C-REPORT.md` from the three slice summaries: four-game matrix,
  migration head/populated-upgrade proof, taxonomy/asset support, config overrides,
  pooled arithmetic, model-fallback status. Automated results labeled separately from
  device evidence.
- [ ] **Step 2:** Attached-target check only with explicit disposable-backend/data approval:
  `flutter devices` → `flutter run -d <actual-ID>`; exercise four games, level change,
  offline cached play, reconnect; inspect server session/audit + pooled aggregate. No
  target/approval → mark pending, never waive.
- [ ] **Step 3:** User accepts, accepts-with-deferred-validation, or holds with named
  corrections in `STATE.md`. No auto-commit, deploy, promotion, or out-of-scope work.

## 4. Self-review

- **Spec coverage:** every binding B-contract row maps to a slice (rules authority → all
  slices; 3-category extractor → §1 row 5 + C-02' fallback; additive migration → C-01'
  step 3; no calibration/activation/unification → Global Constraints + C-04' step 3).
  R0 covers the open taxonomy/config choice the old plans left to B-06.
- **Placeholder scan:** no TBD/TODO/"appropriate handling" language; each step names exact
  files, commands, and observable outcomes. R0 content-insufficiency is a defined output,
  not a gap.
- **Type consistency:** `ODD_ONE_OUT='odd_one_out'`, action `select_odd_item`,
  `error_category='semantic_category'`, reasons `unsupported_game`/`unsupported_category`,
  migration `0010_odd_one_out` — identical across slices.

## 5. Execution handoff

Replan complete, saved here (repo convention; deviates from the skill default
`docs/superpowers/plans/` where no A/B/C plan has ever lived). C implementation is
**not authorized** by this replan or by your "approve" of the replan start.

Two options — reply with one:

1. **Approve C implementation** (gates R0 decision first, then slices in order; I will
   present the R0 taxonomy table for sign-off before any C-01' work).
2. **Hold / request changes** to this replan.

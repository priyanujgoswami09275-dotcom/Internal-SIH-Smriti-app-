# UNAPPROVED — REPLAN REQUIRED; NEVER AUTOEXECUTE

The single six-hour B-01 plan and one final B report replace the former B chain. Everything below preserves the old C proposal, including B-06, integration, migration and config assumptions; these are not active requirements or approved dependencies. Replan C after the B report and obtain explicit approval before execution. Risk/difficulty independence remains binding.

---
phase: cognitive-games-ml
plan: C-01
type: tdd
wave: 9
depends_on: [B-06]
files_modified:
  - backend/app/models/all_models.py
  - backend/alembic/versions/0009_odd_one_out.py
  - backend/app/services/level_config_service.py
  - backend/app/services/odd_one_out_service.py
  - backend/app/tests/test_odd_one_out.py
autonomous: false
must_haves:
  truths:
    - Exactly one new game enum is added: Odd-One-Out; existing Number Recall survives unchanged.
    - Every generated board has exactly one deterministic semantic odd item using existing assets.
    - Board dimensions/timing resolve through shared config, not a new progression map.
  artifacts:
    - path: backend/alembic/versions/0009_odd_one_out.py
      provides: Additive enum/config migration following verified current head
    - path: backend/app/services/odd_one_out_service.py
      provides: Curated taxonomy, config-fed generator and deterministic scorer
  key_links:
    - from: backend/app/services/odd_one_out_service.py
      to: backend/app/services/content_packs.py
      via: Existing item IDs/names/assets rather than geographic category-as-semantics
    - from: backend/app/services/odd_one_out_service.py
      to: backend/app/services/level_config_service.py
      via: Params supplied by canonical config for board generation
---

<objective>Add Odd-One-Out domain/config safely without duplicating Number Recall.</objective>
<context>
@.planning/phases/cognitive-games-ml/ROADMAP.md
@.planning/phases/cognitive-games-ml/B-REPORT.md
@backend/app/services/content_packs.py
@backend/alembic/versions/0007_number_recall.py
@backend/app/tests/test_number_recall.py
</context>
**PROVISIONAL:** Requires accepted B report and explicit C approval, including config/taxonomy choice. No implementation this turn. Word mode excluded unless separately revised/approved.
<tasks>
<task type="auto">
<name>1. Add only Odd-One-Out enum and canonical config</name>
<files>backend/app/models/all_models.py; backend/alembic/versions/0009_odd_one_out.py; backend/app/services/level_config_service.py; backend/app/tests/test_odd_one_out.py</files>
<action>Before authoring run alembic heads on the approved execution environment; the historical assumption of head 0008_adaptive_decisions is stale after implemented 0008_risk_screening — stop/replan if the verified B head differs. Add ODD_ONE_OUT='odd_one_out', revision 0009_odd_one_out (<=32 chars), down_revision matching the verified current head. Add only new enum value and three game_level_config rows using B-06-approved proposal (items 3/4/6, target_seconds 45/70/120); no Number Recall migration/enum duplicate, no edits to dirty historical migrations. Add canonical default params matching seeds. Test populated upgrade from B head on disposable PostgreSQL, preserving Number Recall/session/audit data and overrides. Downgrade removes new config rows only, documents PostgreSQL enum retention and existing-session handling without destructive row deletion. Test exactly four enum values and config levels 1–3.</action>
<verify>Future backend cwd, disposable PostgreSQL explicitly selected: alembic heads; python3 -m pytest app/tests/test_odd_one_out.py -q. Tests include migration identity length, populated upgrade, retained Number Recall and config parity.</verify>
<done>Exactly four game types exist; one additive revision/config slice follows actual head and legacy populated data survives.</done>
</task>
<task type="auto">
<name>2. Generate and score unambiguous semantic boards</name>
<files>backend/app/services/odd_one_out_service.py; backend/app/tests/test_odd_one_out.py</files>
<action>Create generate_board(params, seed) and score_selection(board_snapshot, selected_item_id) using existing ContentItem IDs/names/art. Category fields are geographic, so use an explicit curated ID taxonomy in this service: e.g. festivals (bihu/hornbill/chapchar_kut/nongkrem/losar/sangken), edible fruit (kaji_nemu/ou_tenga/jolpai/starfruit), animals (rhino/red_panda), instruments (dhol/pepa). Only use groups with item_count-1 distinct members; validate referenced assets/registry keys exist before accepting a group. If L3 cannot obtain five unambiguous existing members, report content insufficiency rather than invent new art or visual similarity. Majority taxonomy members plus one member from a disjoint category, stable seeded shuffle, exactly one answer, no duplicated IDs; expose category explanation after completion, not as a scored client assertion. No visual-similarity grading, new progression thresholds or additional fifth game. Return shared board shape with game_type, difficulty_level/config version, items and server-held answer; scorer returns correctness, error_category='semantic_category' and opportunity metadata for B. Test reproducibility, every configured level, ambiguous/unknown taxonomy rejection and localized error counting.</action>
<verify>In backend: python3 -m pytest app/tests/test_odd_one_out.py app/tests/test_number_recall.py -q; python3 -m pytest app/tests tests -q. Test references resolve to existing content/art mappings and board difficulty changes when canonical config is overridden.</verify>
<done>Deterministic semantic boards/scoring work at approved levels without fabricated categories/art or separate difficulty logic; Number Recall remains reused.</done>
</task>
</tasks>
<verification>Use actual registry/assets during future tests, not assumptions based solely on image_url strings. Backend lint/typecheck remains unspecified.</verification>
<success_criteria>New domain/config slice passes tests and is ready for existing session route integration.</success_criteria>
<output>.planning/phases/cognitive-games-ml/C-01-SUMMARY.md with taxonomy/config approval, migration and asset-support evidence. No commit.</output>

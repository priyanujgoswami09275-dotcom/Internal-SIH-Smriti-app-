# UNAPPROVED — REPLAN REQUIRED; NEVER AUTOEXECUTE

The single six-hour B-01 plan and one final B report replace the former B chain. Everything below preserves the old C checkpoint proposal, including full-stack B evidence, calibration and activation assumptions; these are not active requirements or approved gates. Replan C after the B report and obtain explicit approval before execution. Risk/difficulty independence remains binding.

---
phase: cognitive-games-ml
plan: C-04
type: execute
wave: 12
depends_on: [C-03]
files_modified:
  - .planning/phases/cognitive-games-ml/C-REPORT.md
  - .planning/phases/cognitive-games-ml/STATE.md
autonomous: false
must_haves:
  truths:
    - Four-game completion and pooled contribution are evidenced without claiming separate dashboard series.
    - Device/browser validation is explicitly pending unless an attached target was actually exercised.
    - Milestone completion requires user acceptance, not automated phase advancement.
  artifacts:
    - path: .planning/phases/cognitive-games-ml/C-REPORT.md
      provides: Four-game evidence, target record, limitations and final gate decision
  key_links:
    - from: .planning/phases/cognitive-games-ml/C-02-SUMMARY.md
      to: .planning/phases/cognitive-games-ml/C-REPORT.md
      via: Four-game scoring/progression/session audit and pooled arithmetic
    - from: .planning/phases/cognitive-games-ml/C-03-SUMMARY.md
      to: .planning/phases/cognitive-games-ml/C-REPORT.md
      via: Mobile contract results kept distinct from target validation
---

<objective>Review C evidence and perform an explicitly authorized target check before final acceptance.</objective>
<context>
@.planning/phases/cognitive-games-ml/ROADMAP.md
@.planning/phases/cognitive-games-ml/B-REPORT.md
@.planning/phases/cognitive-games-ml/C-01-SUMMARY.md
@.planning/phases/cognitive-games-ml/C-02-SUMMARY.md
@.planning/phases/cognitive-games-ml/C-03-SUMMARY.md
</context>
**PROVISIONAL dedicated checkpoint:** No implementation or dashboard changes. No target is assumed attached; no smoke/config/database mutation without isolated-data approval.
<tasks>
<task type="checkpoint:human-verify">
<name>1. Review C report and verify an attached target</name>
<files>.planning/phases/cognitive-games-ml/C-REPORT.md</files>
<action>Prepare report from C summaries with exactly four games, existing Number Recall/6a2af63 reuse, only new Odd-One-Out enum/migration, current migration head/populated-upgrade proof, taxonomy/asset support, shared config overrides and B policy/source audit. Include all-game scoring/progression matrix and existing pooled stats arithmetic; explicitly no dashboard implementation change or separate series claim. Record all current full test/analyzer commands/exits and model activation/support status from B; new game may remain unsupported-model fallback. For manual run first disclose that game play/smoke creates sessions and may affect demo DB/config; require explicit disposable backend/data authorization. In mobile run flutter devices to identify attached target; only then use flutter run -d with its actual returned ID and isolated backend configuration. Record actual command/target/platform/date. On the attached device or browser exercise each of four games through a level/config change, completion, visible fallback/source state, offline cached play and reconnect; inspect server linked session/audit and unchanged pooled aggregate. Browser testing proves browser behavior only. If no target or isolation approval, mark device/browser checkpoint pending; never report widget tests as physical-device validation.</action>
<how-to-verify>User reviews four-game flow and Monad visuals on the actual identified target, confirms source/fallback labels, and compares completed session IDs/counts against report evidence. No secrets or patient data in screenshots/logs.</how-to-verify>
<verify>C-REPORT includes separately labeled automated results, device/browser evidence (or pending), pooled contribution and no-duplicate-audit observation. A model fallback cannot be relabeled ML to satisfy a demonstration.</verify>
<done>User accepts evidence; unavailable target leaves visual/physical validation pending and is not silently waived.</done>
<resume-signal>Explicit target verification acceptance, or pending target/isolation reason.</resume-signal>
</task>
<task type="checkpoint:decision">
<name>2. Accept milestone or retain explicit blockers</name>
<files>.planning/phases/cognitive-games-ml/C-REPORT.md; .planning/phases/cognitive-games-ml/STATE.md</files>
<action>Review A/B/C gate records, fresh test failures, device status, real model compatibility, real-data/cohort limits, probability calibration/activation status and the binding risk/difficulty independence (no risk prior to reopen). Record user acceptance or requested bounded follow-up plans within this directory. Do not equate synthetic metrics with patient/clinical validation, source inspection with live risk use, pooled chart with per-game series or browser test with physical device validation. If a user explicitly defers a checkpoint, label accepted-with-deferred-validation rather than fully validated. No automatic commit, deployment, artifact promotion or excluded multiplayer/media/PDF/personalization/snooze/quiet-hours work.</action>
<options>Accept evidenced scope; accept explicitly documented deferrals; or hold for named corrections and separately approved plans.</options>
<verify>STATE links accepted reports and precise remaining blockers; every deferred validation remains visible and final status matches explicit user wording.</verify>
<done>User decision is recorded without silently advancing any unapproved work.</done>
<resume-signal>Explicit milestone acceptance or requested corrections.</resume-signal>
</task>
</tasks>
<verification>Review and authorized manual verification only; any code fix requires a new approved implementation task.</verification>
<success_criteria>Evidence and limitations are accurately accepted or the milestone remains blocked/pending.</success_criteria>
<output>C-REPORT.md and local STATE.md only. No commit.</output>

# SUPERSEDED — inactive archival methodology; NEVER AUTOEXECUTE

Replaced by the single 1-working-day / 6-hour B-01 plan and its one final B report. Everything below is historical, including calibration, activation and C gates; it imposes no current requirement. Activation is excluded; C must be replanned and remains unapproved.

---
phase: cognitive-games-ml
plan: B-06
type: execute
wave: 8
depends_on: [B-05]
files_modified:
  - .planning/phases/cognitive-games-ml/B-REPORT.md
  - .planning/phases/cognitive-games-ml/STATE.md
autonomous: false
must_haves:
  truths:
    - Reported metrics distinguish synthetic assumptions, held-out real performance and operational evidence.
    - Probability thresholds/calibration and C scope cannot be silently approved.
  artifacts:
    - path: .planning/phases/cognitive-games-ml/B-REPORT.md
      provides: Model, policy, provenance, audit and approval evidence
  key_links:
    - from: .planning/phases/cognitive-games-ml/B-01-SUMMARY.md
      to: .planning/phases/cognitive-games-ml/B-REPORT.md
      via: Split-safe fitted model metrics and retrain eligibility
    - from: .planning/phases/cognitive-games-ml/B-REPORT.md
      to: .planning/phases/cognitive-games-ml/C-01-PLAN.md
      via: Explicit user approval of B report and revised C scope
---

<objective>Review B evidence and independently decide policy activation and C authorization.</objective>
<context>
@.planning/phases/cognitive-games-ml/ROADMAP.md
@.planning/phases/cognitive-games-ml/B-01-SUMMARY.md
@.planning/phases/cognitive-games-ml/B-02-SUMMARY.md
@.planning/phases/cognitive-games-ml/B-03-SUMMARY.md
@.planning/phases/cognitive-games-ml/B-04-SUMMARY.md
@.planning/phases/cognitive-games-ml/B-05-SUMMARY.md
</context>
**PROVISIONAL checkpoint only:** No implementation, artifact promotion or config/DB mutation inside this plan. No automatic C execution.
<tasks>
<task type="checkpoint:human-verify">
<name>1. Review B model and end-to-end evidence</name>
<files>.planning/phases/cognitive-games-ml/B-REPORT.md</files>
<action>Compile fresh summaries into B report: LR versus any GB comparison, seeds/schema/library versions, synthetic assumptions, cohort/class/category support, excluded/missing future labels, split boundaries and patient disjointness, holdout ROC/PR-AUC/log loss/Brier/reliability-bin support, calibration and behavior matrix. Separate synthetic assumption conformity from any real-data validation and explicitly state neither establishes clinical validation. Include fitted predict_proba proof, proposed thresholds, localized-error veto, 0/1/2 vs3 session exact fallback, missing-artifact/features/error reasons, model probability versus decision confidence, bounds, additive populated migration outcome and all full commands/exits. Provide linked decision/session samples for rule_fallback (null probability) and fitted ml_model in isolated explicitly enabled test policy, with source/version/result/reason/count/game/time; label test/shadow source proof, never present it as live production ML. Include online screen/API source matching and offline replay retry counts proving no duplicate audits. Verify binding risk/difficulty independence: only session accuracy/time/error/current-level features and game/config/support metadata; no risk inputs, priors, risk-based calibration, risk missingness or screening reads/joins anywhere in extraction, training, inference or policy. Include sensitive-log minimization and retrain refusal/promotion/rollback evidence.</action>
<how-to-verify>User checks B-REPORT and linked fresh outputs; missing strata, failed tests, mismatched schemas or unavailable real data remain explicit limitations/blockers, not hidden by synthetic metrics.</how-to-verify>
<verify>Every B requirement has a source/metric/test/audit reference; runtime activation state is explicit and historical analyzer/compatibility concerns are not fresh test results.</verify>
<done>User accepts report or records corrections; ML quality uncertainty is not converted into unwarranted confidence.</done>
<resume-signal>Explicit acceptance of B-REPORT.md or requested corrections.</resume-signal>
</task>
<task type="checkpoint:decision">
<name>2. Ratify probability policy and authorize or hold C</name>
<files>.planning/phases/cognitive-games-ml/B-REPORT.md; .planning/phases/cognitive-games-ml/STATE.md</files>
<action>Request evidence-based promotion thresholds and session-model calibration/support acceptance; alternative is rules/shadow with no live ML claim. Risk independence is binding, not a prior decision to reopen; no risk-based calibration or screening reads/joins are allowed. Probability of success at a harder level does not establish a lowering policy; retain rule-supported lowering. Record whether synthetic-demo scope only is accepted; insufficient real data forbids patient-validation claims. Approval of thresholds does not itself perform artifact/config promotion: any promotion requires a separately approved bounded execution step with isolation/rollback disclosure, then runtime evidence before declaring live. Review C's four-game scope, proposed Odd-One-Out config and curated taxonomy; choose word mode excluded (recommended) or an optional mode requiring revised within-budget plans, never a fifth enum. C cannot start until B report acceptance and explicit C approval; approval may accept rules/shadow limitations, which remain visible in C report. Record full decision text and revised plan identifiers if needed.</action>
<options>Accept B report and approve C with rules/shadow limitations; approve a separately controlled demo activation and C; or hold for calibration/support/runtime corrections. Choose word mode excluded or require a revised optional-mode plan.</options>
<verify>STATE records model activation status separately from B acceptance, exact policy decisions and C permission. No operational threshold is invented to clear a gate.</verify>
<done>C is either explicitly approved with a frozen contract/config or remains provisional. No code/config/DB changes occur in this checkpoint.</done>
<resume-signal>User explicitly approves C after B report review and resolves C content/config decisions.</resume-signal>
</task>
</tasks>
<verification>Review existing evidence only; no hidden implementation in checkpoint tasks.</verification>
<success_criteria>Report acceptance, policy activation and C scope are distinct recorded decisions.</success_criteria>
<output>B-REPORT.md and local STATE.md. No auto-execution/commit.</output>

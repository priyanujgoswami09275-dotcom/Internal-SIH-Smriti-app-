from datetime import timedelta
from types import SimpleNamespace

import numpy as np
import pytest

from tests.test_adaptive_features import NOW, session


def decision(**changes):
    return SimpleNamespace(**dict(dict(patient_id="p", game_type="match_it", old_difficulty=1,
                                      adjusted_at=NOW, id="decision"), **changes))


def outcome(identifier="target", **changes):
    return session(identifier, -1, difficulty_level=2, **changes)


def test_label_targets_record_resolved_config_at_training_time(tmp_path):
    from app.services.adaptive_training import build_examples, synthetic_examples, train_candidate
    from app.services.level_config_service import default_params
    import joblib

    rows = [session(str(i), i + 1) for i in range(3)]
    rows += [outcome(accuracy_pct=84), session("later", -2, difficulty_level=2, accuracy_pct=100)]
    examples, exclusions, targets = build_examples([decision()], rows, {}, NOW + timedelta(days=31))
    assert len(examples) == 1
    assert targets == {"match_it:2": default_params("match_it", 2)["target_seconds"]}
    overridden, _, overridden_targets = build_examples(
        [decision()], rows, {("match_it", 2): {"target_seconds": 123}}, NOW + timedelta(days=31))
    assert len(overridden) == 1
    assert overridden_targets == {"match_it:2": 123}
    synthetic, _, synthetic_targets = synthetic_examples()
    assert synthetic_targets["match_it:2"] == default_params("match_it", 2)["target_seconds"]
    path = tmp_path / "targets.joblib"
    report = train_candidate(synthetic, path, origin="synthetic", label_targets=synthetic_targets)
    assert report["status"] == "fitted"
    assert report["label_targets"] == synthetic_targets
    assert joblib.load(path)["label_targets"] == synthetic_targets


def test_first_observed_failure_is_not_replaced_by_later_success():
    from app.services.adaptive_training import build_examples

    rows = [session(str(i), i + 1) for i in range(3)]
    rows += [outcome(accuracy_pct=84), session("later", -2, difficulty_level=2, accuracy_pct=100)]
    examples, exclusions, _ = build_examples([decision()], rows, {}, NOW + timedelta(days=31))
    assert len(examples) == 1
    assert examples[0].label == 0
    assert examples[0].features.values[0] == 90
    assert exclusions == {}


@pytest.mark.parametrize("changes,reason", [
    ({"accuracy_pct": None}, "missing_outcome_accuracy"),
    ({"started_at": None}, "invalid_outcome_timestamp"),
    ({"started_at": NOW - timedelta(seconds=1)}, "outcome_started_before_decision"),
])
def test_unevaluable_first_outcome_excluded_not_replaced(changes, reason):
    from app.services.adaptive_training import build_examples

    rows = [session(str(i), i + 1) for i in range(3)] + [outcome(**changes), session("later", -2, difficulty_level=2)]
    examples, counts, _ = build_examples([decision()], rows, {}, NOW + timedelta(days=31))
    assert examples == []
    assert counts == {reason: 1}


@pytest.mark.parametrize("days,accuracy,duration,label", [(30, 85, 150, 1), (1, 85, 151, 0), (1, 84.9, 30, 0)])
def test_actual_label_boundaries(days, accuracy, duration, label):
    from app.services.adaptive_training import build_examples

    target = session("target", -days, difficulty_level=2, accuracy_pct=accuracy,
                     started_at=NOW + timedelta(days=days, seconds=-duration))
    rows = [session(str(i), i + 1) for i in range(3)] + [target]
    examples, _, _ = build_examples([decision()], rows, {}, NOW + timedelta(days=31))
    assert examples[0].label == label


def test_unplayed_late_top_level_and_missing_target_excluded():
    from app.services.adaptive_training import build_examples

    history = [session(str(i), i + 1) for i in range(3)]
    for rows in (history, history + [session("late", -31, difficulty_level=2)]):
        assert build_examples([decision()], rows, {}, NOW + timedelta(days=32))[1] == {"missing_outcome": 1}
    assert build_examples([decision(old_difficulty=3)], history, {}, NOW)[1] == {"top_level": 1}
    assert build_examples([decision()], history + [outcome()], {("match_it", 2): {"target_seconds": None}}, NOW + timedelta(days=31))[1] == {"missing_target": 1}


def test_bootstrap_fitted_probability_group_split_and_train_only_imputation(tmp_path):
    from app.services.adaptive_training import synthetic_examples, train_candidate
    import joblib

    examples, exclusions, _ = synthetic_examples()
    path = tmp_path / "bootstrap.joblib"
    report = train_candidate(examples, path, origin="synthetic", exclusions=exclusions)
    assert report["status"] == "fitted"
    artifact = joblib.load(path)
    split = artifact["split"]
    assert split["disjoint"]
    assert split["train_groups"] == 80
    assert split["test_groups"] == 20
    assert all(report["class_counts"][name][str(label)] > 0 for name in ("overall", "train", "test") for label in (0, 1))
    from sklearn.model_selection import GroupShuffleSplit
    rows = np.array([e.features.model_row() for e in examples])
    train, test = next(GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42).split(rows, groups=[e.patient_id for e in examples]))
    np.testing.assert_allclose(artifact["pipeline"].named_steps["imputer"].statistics_, np.nanmedian(rows[train], axis=0))
    probability = artifact["pipeline"].predict_proba(rows[test])[:, 1]
    assert np.isfinite(probability).all()
    assert ((0 <= probability) & (probability <= 1)).all()
    assert artifact["origin"] == "synthetic"
    assert "assumption conformity" in report["evidence"]
    assert 0 <= report["metrics"]["accuracy"] <= 1
    assert 0 <= report["metrics"]["roc_auc"] <= 1


def test_localized_weakness_lowers_fitted_probability(tmp_path):
    from app.services.adaptive_training import synthetic_examples, train_candidate
    import joblib

    examples, exclusions, _ = synthetic_examples()
    path = tmp_path / "candidate.joblib"
    train_candidate(examples, path, origin="synthetic", exclusions=exclusions)
    pipeline = joblib.load(path)["pipeline"]
    for category in (2, 3, 4):
        strong = [90, 1800, np.nan, np.nan, np.nan, 1, 0, 0, 1, 1, 1, 0]
        strong[category] = 0.05
        strong[category + 6] = 0
        weak = strong.copy()
        weak[category] = 0.65
        probabilities = pipeline.predict_proba([strong, weak])[:, 1]
        assert probabilities[1] < probabilities[0]


def test_real_refusal_and_existing_candidate_never_overwritten(tmp_path):
    from app.services.adaptive_training import synthetic_examples, train_candidate

    examples, _, _ = synthetic_examples()
    path = tmp_path / "candidate.joblib"
    path.write_bytes(b"original")
    report = train_candidate(examples[:20], path, origin="real")
    assert report["status"] == "insufficient_data"
    assert path.read_bytes() == b"original"
    report = train_candidate(examples, path, origin="synthetic")
    assert report["status"] == "output_exists"
    assert path.read_bytes() == b"original"

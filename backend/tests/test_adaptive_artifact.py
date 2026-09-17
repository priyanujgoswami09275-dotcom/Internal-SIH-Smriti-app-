from pathlib import Path

import joblib
import pytest

from tests.test_adaptive_features import NOW, session
from app.services.adaptive_features import extract_features


def test_missing_unsafe_bad_and_incompatible_artifact_are_graceful(tmp_path, monkeypatch):
    from app.services import adaptive_shadow as shadow

    monkeypatch.setattr(shadow, "MODEL_ROOT", tmp_path)
    features = extract_features([session(str(i), i + 1) for i in range(3)], "p", "match_it", 1, NOW)
    assert shadow.predict_shadow(features, "")["shadow_reason"] == "disabled"
    assert shadow.predict_shadow(features, "missing.joblib")["shadow_reason"] == "artifact_missing"
    assert shadow.predict_shadow(features, "../escape.joblib")["shadow_reason"] == "unsafe_artifact_path"
    bad = tmp_path / "bad.joblib"
    bad.write_bytes(b"invalid")
    assert shadow.predict_shadow(features, "bad.joblib")["shadow_reason"] == "artifact_invalid"
    joblib.dump({"schema_version": "wrong"}, bad)
    assert shadow.predict_shadow(features, "bad.joblib")["shadow_reason"] == "artifact_incompatible"
    (tmp_path / "link.joblib").symlink_to(tmp_path.parent / "outside.joblib")
    assert shadow.predict_shadow(features, "link.joblib")["shadow_reason"] == "unsafe_artifact_path"


def test_fitted_artifact_loaded_cached_and_probability_is_separate(tmp_path, monkeypatch):
    from app.services import adaptive_shadow as shadow
    from app.services.adaptive_training import synthetic_examples, train_candidate

    monkeypatch.setattr(shadow, "MODEL_ROOT", tmp_path)
    examples, exclusions, _ = synthetic_examples()
    report = train_candidate(examples, tmp_path / "candidate.joblib", origin="synthetic", exclusions=exclusions)
    features = examples[0].features
    result = shadow.predict_shadow(features, "candidate.joblib")
    assert result["shadow_reason"] == "predicted"
    assert 0 <= result["shadow_probability"] <= 1
    assert result["shadow_model_version"] == report["version"]
    def no_reload(*args, **kwargs):
        raise AssertionError("cached artifact reloaded")
    monkeypatch.setattr(joblib, "load", no_reload)
    assert shadow.predict_shadow(features, "candidate.joblib") == result
    assert "new_difficulty" not in result


def test_ineligible_features_never_load_artifact(tmp_path, monkeypatch):
    from app.services import adaptive_shadow as shadow

    def forbidden(*args, **kwargs):
        raise AssertionError("must not load")
    monkeypatch.setattr(joblib, "load", forbidden)
    features = extract_features([], "p", "match_it", 1, NOW)
    assert shadow.predict_shadow(features, "bootstrap.joblib")["shadow_reason"] == "insufficient_history"

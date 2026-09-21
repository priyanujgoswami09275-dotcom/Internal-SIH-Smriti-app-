from functools import lru_cache
from math import isfinite
from pathlib import Path

from sqlalchemy import select

from app.config import settings
from app.models.all_models import GameSession
from app.services.adaptive_features import ACTIONS, INPUT_NAMES, SCHEMA_VERSION, extract_features


MODEL_ROOT = Path(__file__).resolve().parents[2] / "ml_models" / "adaptive_success"


def shadow_result(reason, probability=None, version=None):
    return dict(shadow_probability=probability, shadow_model_version=version, shadow_reason=reason)


@lru_cache(maxsize=4)
def load_candidate(path, modified, size):
    import joblib
    import sklearn
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import Pipeline
    from sklearn.utils.validation import check_is_fitted

    try:
        artifact = joblib.load(path)
    except Exception:
        return None, "artifact_invalid"
    try:
        if (not isinstance(artifact, dict) or artifact.get("format_version") != 1
                or artifact.get("schema_version") != SCHEMA_VERSION
                or artifact.get("input_names") != INPUT_NAMES
                or artifact.get("seed") != 42
                or artifact.get("origin") not in ("real", "synthetic")
                or artifact.get("sklearn_version") != sklearn.__version__
                or not isinstance(artifact.get("version"), str)
                or not 1 <= len(artifact["version"]) <= 120):
            return None, "artifact_incompatible"
        pipeline = artifact["pipeline"]
        if (not isinstance(pipeline, Pipeline)
                or type(pipeline.named_steps["classifier"]) is not LogisticRegression
                or pipeline.n_features_in_ != len(INPUT_NAMES)
                or list(pipeline.classes_) != [0, 1]):
            return None, "artifact_incompatible"
        check_is_fitted(pipeline)
    except Exception:
        return None, "artifact_incompatible"
    return artifact, "loaded"


def predict_shadow(features, model_path):
    if features.values is None:
        return shadow_result(features.reason)
    if not model_path:
        return shadow_result("disabled")
    try:
        relative = Path(model_path)
        path = (MODEL_ROOT / relative).resolve()
        if relative.is_absolute() or ".." in relative.parts or path.suffix != ".joblib" or not path.is_relative_to(MODEL_ROOT.resolve()):
            return shadow_result("unsafe_artifact_path")
        if not path.is_file():
            return shadow_result("artifact_missing")
        stat = path.stat()
        artifact, reason = load_candidate(str(path), stat.st_mtime_ns, stat.st_size)
        if artifact is None:
            return shadow_result(reason)
        probability = float(artifact["pipeline"].predict_proba([features.model_row()])[0, 1])
        if not isfinite(probability) or not 0 <= probability <= 1:
            return shadow_result("invalid_probability")
        return shadow_result("predicted", probability, artifact["version"])
    except Exception:
        return shadow_result("inference_error")


async def evaluate_shadow(db, patient_id, game_type, current_level, decision_time):
    if current_level == 3:
        return shadow_result("top_level")
    game = getattr(game_type, "value", game_type)
    if game not in ACTIONS:
        # No learned support for this game (Odd-One-Out semantic errors are
        # never folded into the 3-category vector): rules stay authoritative.
        return shadow_result("unsupported_game")
    if not settings.ADAPTIVE_SHADOW_MODEL:
        return shadow_result("disabled")
    query = select(GameSession).where(
        GameSession.patient_id == patient_id, GameSession.game_type == game_type,
        GameSession.completed_at.isnot(None), GameSession.completed_at < decision_time,
    ).order_by(GameSession.completed_at.desc(), GameSession.id.desc())
    rows = (await db.execute(query)).scalars().all()
    features = extract_features(rows, patient_id, game_type, current_level, decision_time)
    return predict_shadow(features, settings.ADAPTIVE_SHADOW_MODEL)

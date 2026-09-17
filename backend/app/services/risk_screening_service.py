"""Worker-initialized preliminary screening; not a clinical diagnosis."""
import hashlib
import json
import logging
import math
import os
from pathlib import Path
from threading import Lock
from typing import Any, Dict, List

logger = logging.getLogger(__name__)

ASSET_DIR = Path(__file__).resolve().parents[2] / "ml_models" / "alzheimers_risk"
FEATURE_PATH = ASSET_DIR / "feature_names.json"
GUIDE_PATH = ASSET_DIR / "model_input_guide.json"
SCALER_PATH = ASSET_DIR / "scaler.pkl"
MODEL_PATH = ASSET_DIR / "alzheimers_risk_model.keras"


def _load_schema(path, fallback):
    try:
        with open(path, encoding="utf-8") as source:
            value = json.load(source)
            return value if type(value) is type(fallback) else fallback
    except (OSError, ValueError):
        return fallback


FEATURE_NAMES: List[str] = _load_schema(FEATURE_PATH, [])
FEATURE_GUIDE = _load_schema(GUIDE_PATH, {})
FEATURE_DTYPE_MAP = {
    name: int if isinstance(rule, dict) and rule.get("dtype") == "int64" else float
    for name, rule in FEATURE_GUIDE.items()
}
_model = None
_scaler = None
_model_loaded = False
_initialized_pid = None
_initialization_error = None
_initialization_lock = Lock()
MODEL_VERSION = None


def _load_artifacts():
    import joblib
    import tensorflow as tf

    model = tf.keras.models.load_model(os.path.abspath(MODEL_PATH), compile=False)
    scaler = joblib.load(os.path.abspath(SCALER_PATH))
    return model, scaler


def _validate_schema(request_names):
    if (len(FEATURE_NAMES) != 32 or len(set(FEATURE_NAMES)) != 32
            or list(FEATURE_GUIDE) != FEATURE_NAMES):
        raise ValueError("Feature, guide and request schemas must agree on 32 ordered unique names")
    for rule in FEATURE_GUIDE.values():
        if not isinstance(rule, dict) or (
                rule["dtype"] not in ("int64", "float64")
                or not math.isfinite(rule["min"]) or not math.isfinite(rule["max"])
                or rule["min"] > rule["max"]):
            raise ValueError("Invalid feature guide")
    if request_names is not None and list(request_names) != FEATURE_NAMES:
        raise ValueError("Feature, guide and request schemas must agree on 32 ordered unique names")


def _validate_artifacts(model, scaler):
    import numpy as np

    if scaler.n_features_in_ != 32:
        raise ValueError("Scaler input must have 32 features")
    if hasattr(scaler, "feature_names_in_") and list(scaler.feature_names_in_) != FEATURE_NAMES:
        raise ValueError("Scaler feature order differs from schema")
    for name in ("mean_", "var_", "scale_"):
        values = np.asarray(getattr(scaler, name), dtype=np.float64)
        if values.shape != (32,) or not np.isfinite(values).all():
            raise ValueError("Invalid scaler parameters")
        if name == "scale_" and (values <= 0).any():
            raise ValueError("Scaler scale must be positive")
        if name == "var_" and (values < 0).any():
            raise ValueError("Scaler variance must be nonnegative")
    if model.input_shape != (None, 32) or model.output_shape != (None, 1):
        raise ValueError("Model must map 32 features to one probability")


def initialize_risk_screening(request_names=None) -> bool:
    global _model, _scaler, _model_loaded, _initialized_pid, _initialization_error, MODEL_VERSION

    with _initialization_lock:
        pid = os.getpid()
        if _initialized_pid == pid:
            return _model_loaded
        _initialized_pid = pid
        _model_loaded = False
        _model = _scaler = MODEL_VERSION = None
        _initialization_error = None
        try:
            _validate_schema(request_names)
            model, scaler = _load_artifacts()
            _validate_artifacts(model, scaler)
            digest = hashlib.sha256()
            for path in (MODEL_PATH, SCALER_PATH, FEATURE_PATH, GUIDE_PATH):
                with open(path, "rb") as source:
                    digest.update(hashlib.file_digest(source, "sha256").digest())
            MODEL_VERSION = "sha256:" + digest.hexdigest()
            _model, _scaler = model, scaler
            _model_loaded = True
            logger.info("Risk screening initialized with 32 features (%s)", MODEL_VERSION)
        except Exception as exc:
            _initialization_error = f"{type(exc).__name__}: {exc}"
            logger.warning("Risk screening unavailable: %s", _initialization_error)
        return _model_loaded


def validate_input(data: Dict[str, Any]) -> List[str]:
    errors = [f"unexpected_feature: {name}" for name in data if name not in FEATURE_NAMES]
    for name in FEATURE_NAMES:
        if name not in data:
            errors.append(f"missing_feature: {name}")
            continue
        value = data[name]
        if value is None:
            errors.append(f"null_feature: {name}")
            continue
        try:
            numeric = float(value)
        except (TypeError, ValueError, OverflowError):
            errors.append(f"bad_type: {name}")
            continue
        if not math.isfinite(numeric):
            errors.append(f"non_finite_feature: {name}")
            continue
        rule = FEATURE_GUIDE[name]
        if rule["dtype"] == "int64" and not numeric.is_integer():
            errors.append(f"non_integer_feature: {name}")
        if not rule["min"] <= numeric <= rule["max"]:
            errors.append(f"out_of_range_feature: {name}")
    return errors


def build_feature_array(data: Dict[str, Any]) -> Any:
    import numpy as np

    arr = np.array([[float(data[name]) for name in FEATURE_NAMES]], dtype=np.float64)
    if arr.shape != (1, 32) or not np.isfinite(arr).all():
        raise ValueError("Invalid raw feature array")
    return arr


def run_inference(data: Dict[str, Any]) -> Dict[str, Any]:
    if not _model_loaded:
        return {"status": "model_unavailable", "message": "Risk-screening model unavailable in this worker."}
    errors = validate_input(data)
    if errors:
        return {"status": "validation_failed", "errors": errors}

    import numpy as np

    try:
        arr = build_feature_array(data)
        scaled = np.asarray(_scaler.transform(arr))
        if scaled.shape != (1, 32) or not np.isfinite(scaled).all():
            raise ValueError("Invalid scaled feature array")
        output = np.asarray(_model(scaled, training=False))
        if output.shape != (1, 1) or not np.isfinite(output).all():
            raise ValueError("Invalid prediction shape or value")
        prediction = float(output[0, 0])
        if not 0 <= prediction <= 1:
            raise ValueError("Prediction outside probability range")
    except Exception:
        logger.warning("Risk screening inference failed")
        return {"status": "inference_failed", "message": "Risk-screening inference failed validation."}
    score = round(prediction * 100, 2)
    tier = "low_risk" if score < 33 else "moderate_risk" if score < 67 else "high_risk"
    return {
        "status": "ok",
        "risk_score": score,
        "probability": prediction,
        "tier": tier,
        "feature_count": 32,
        "model_version": MODEL_VERSION,
        "note": "Preliminary screening only; not a clinical diagnosis",
    }

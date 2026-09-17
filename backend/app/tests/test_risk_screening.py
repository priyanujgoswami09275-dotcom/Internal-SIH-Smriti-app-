import json
import math
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

import numpy as np
import pytest
from sqlalchemy import select

from app.deps import get_current_user
from app.main import app
from app.models import all_models
from app.models.all_models import AuditLog, CaregiverPatientLink, ConsentRecord, PatientProfile
from app.models.user import RoleEnum, User
from app.routes.patients import RiskScreeningRequest
from app.services import risk_screening_service as risk
from app.services.compliance_service import ComplianceService
from app.services.retention_service import RetentionService

ASSETS = Path(__file__).resolve().parents[2] / "ml_models" / "alzheimers_risk"
GUIDE = json.loads((ASSETS / "model_input_guide.json").read_text())
FEATURES = json.loads((ASSETS / "feature_names.json").read_text())


@pytest.fixture
def features():
    return {
        name: int((rule["min"] + rule["max"]) / 2)
        if rule["dtype"] == "int64" else (rule["min"] + rule["max"]) / 2
        for name, rule in GUIDE.items()
    }


@pytest.fixture
def fresh_state(monkeypatch):
    for name, value in {
        "_initialized_pid": None,
        "_model_loaded": False,
        "_model": None,
        "_scaler": None,
        "_initialization_error": None,
        "MODEL_VERSION": None,
    }.items():
        monkeypatch.setattr(risk, name, value, raising=False)


def test_import_does_not_deserialize_artifacts():
    result = subprocess.run(
        [sys.executable, "-c", "import sys; from app.services import risk_screening_service as r; "
         "assert 'tensorflow' not in sys.modules; assert 'sklearn' not in sys.modules; "
         "assert len(r.FEATURE_NAMES) == 32; assert not r._model_loaded"],
        capture_output=True, text=True, timeout=120,
    )
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize("filename,payload", [
    ("model_input_guide.json", "[]"),
    ("model_input_guide.json", '{"Age": null}'),
    ("model_input_guide.json", '{"Age": []}'),
    ("model_input_guide.json", '{"Age": "invalid"}'),
    ("model_input_guide.json", '{"Age": 42}'),
    ("model_input_guide.json", '{'),
    ("feature_names.json", '{}'),
    ("feature_names.json", '[{}]'),
])
def test_malformed_metadata_leaves_app_importable_and_model_unavailable(filename, payload):
    code = """
import json
import sys
from pathlib import Path
original = json.load
def load(source, *args, **kwargs):
    if Path(source.name).name == sys.argv[1]:
        return json.loads(sys.argv[2])
    return original(source, *args, **kwargs)
json.load = load
from app.main import app
from app.services import risk_screening_service as r
assert app is not None
assert type(r.FEATURE_NAMES) is list
assert type(r.FEATURE_GUIDE) is dict
def unexpected_load():
    raise AssertionError('Invalid metadata must be rejected before loading artifacts')
r._load_artifacts = unexpected_load
assert not r.initialize_risk_screening()
assert r._initialization_error.startswith('ValueError:'), r._initialization_error
assert r.run_inference({})['status'] == 'model_unavailable'
"""
    result = subprocess.run(
        [sys.executable, "-c", code, filename, payload],
        capture_output=True, text=True, timeout=120,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_each_worker_initializes_real_artifacts_once():
    code = """
import os
from app.services import risk_screening_service as r
loads = []
original = r._load_artifacts
def load():
    loads.append(os.getpid())
    return original()
r._load_artifacts = load
assert r.initialize_risk_screening()
assert r.initialize_risk_screening()
assert loads == [os.getpid()]
print('worker', os.getpid(), 'loads', len(loads))
"""
    workers = [subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=120)
               for _ in range(2)]
    for worker in workers:
        assert worker.returncode == 0, worker.stdout + worker.stderr
        print(worker.stdout, worker.stderr)
    assert workers[0].stdout != workers[1].stdout


def test_missing_artifacts_remain_unavailable_without_retry(monkeypatch, fresh_state, features):
    monkeypatch.setattr(risk, "MODEL_PATH", "/nonexistent/risk-model.keras")
    assert not risk.initialize_risk_screening()
    assert risk._initialization_error
    monkeypatch.setattr(risk, "MODEL_PATH", str(ASSETS / "alzheimers_risk_model.keras"))
    assert not risk.initialize_risk_screening()
    assert risk.run_inference(features)["status"] == "model_unavailable"


@pytest.mark.parametrize("change", [
    "duplicate_names", "guide_order", "request_order", "scaler_width", "scaler_names",
    "scaler_nan", "scaler_scale", "model_width", "model_output",
])
def test_incompatible_schema_stays_unavailable(change, monkeypatch, fresh_state):
    scaler = SimpleNamespace(n_features_in_=32, mean_=np.zeros(32), var_=np.ones(32), scale_=np.ones(32))
    model = SimpleNamespace(input_shape=(None, 32), output_shape=(None, 1))
    request_names = list(RiskScreeningRequest.model_fields)
    if change == "duplicate_names":
        monkeypatch.setattr(risk, "FEATURE_NAMES", FEATURES[:-1] + [FEATURES[0]])
    elif change == "guide_order":
        monkeypatch.setattr(risk, "FEATURE_GUIDE", dict(reversed(list(GUIDE.items()))), raising=False)
    elif change == "request_order":
        request_names.reverse()
    elif change == "scaler_width":
        scaler.n_features_in_ = 31
    elif change == "scaler_names":
        scaler.feature_names_in_ = FEATURES[::-1]
    elif change == "scaler_nan":
        scaler.mean_[0] = np.nan
    elif change == "scaler_scale":
        scaler.scale_[0] = 0
    elif change == "model_width":
        model.input_shape = (None, 31)
    else:
        model.output_shape = (None, 2)
    monkeypatch.setattr(risk, "_load_artifacts", lambda: (model, scaler))
    assert not risk.initialize_risk_screening(request_names)
    assert risk._initialization_error
    assert not risk._model_loaded


@pytest.mark.parametrize("value", [None, "not-numeric", float("nan"), float("inf"), -float("inf"), 59, 91, 70.5])
def test_invalid_input_is_rejected(value, features):
    features["Age"] = value
    assert risk.validate_input(features)


def test_missing_and_unexpected_input_is_rejected(features):
    del features["Age"]
    assert risk.validate_input(features)
    features["Age"] = 75
    features["unexpected"] = 1
    assert risk.validate_input(features)


@pytest.mark.parametrize("scaled,output", [
    (np.full((1, 32), np.nan), [[0.5]]),
    (np.full((1, 32), np.inf), [[0.5]]),
    (np.zeros((1, 31)), [[0.5]]),
    (np.zeros((1, 32)), [[float("nan")]]),
    (np.zeros((1, 32)), [[float("inf")]]),
    (np.zeros((1, 32)), [[-0.01]]),
    (np.zeros((1, 32)), [[1.01]]),
    (np.zeros((1, 32)), [[0.2, 0.8]]),
])
def test_invalid_transforms_or_predictions_never_succeed(scaled, output, features, monkeypatch):
    class InvalidModel:
        def __call__(self, values, training=False):
            return np.array(output)

        def predict(self, values, verbose=0):
            return np.array(output)

    monkeypatch.setattr(risk, "_model_loaded", True)
    monkeypatch.setattr(risk, "_scaler", SimpleNamespace(transform=lambda values: scaled))
    monkeypatch.setattr(risk, "_model", InvalidModel())
    assert risk.run_inference(features)["status"] == "inference_failed"


async def screening_fixture(db_session, role="clinician", tier=None, consent="health_data"):
    user = User(id=uuid4(), password_hash="unused", role=RoleEnum(role))
    owner = User(id=uuid4(), password_hash="unused", role=RoleEnum.PATIENT, is_active=True)
    patient = PatientProfile(id=uuid4(), user_id=owner.id, name="Synthetic screening fixture")
    db_session.add_all([user, owner, patient])
    await db_session.commit()
    if tier:
        db_session.add(CaregiverPatientLink(
            caregiver_id=user.id, patient_id=patient.id, relationship_type="family",
            permission_tier=tier, is_active=tier != "inactive",
        ) if tier != "inactive" else CaregiverPatientLink(
            caregiver_id=user.id, patient_id=patient.id, relationship_type="family",
            permission_tier="clinical", is_active=False,
        ))
    record = ConsentRecord(patient_id=patient.id, scope=consent or "game_data")
    db_session.add(record)
    await db_session.commit()
    app.dependency_overrides[get_current_user] = lambda: user
    return patient, record


@pytest.mark.asyncio
async def test_real_artifact_http_success_persists_latest_and_audits(client, db_session, features, fresh_state):
    patient, consent = await screening_fixture(db_session)
    async with app.router.lifespan_context(app):
        assert risk._model_loaded, getattr(risk, "_initialization_error", None)
        assert risk._model.input_shape == (None, 32)
        assert risk._scaler.n_features_in_ == 32
        for age in (75, 80):
            features["Age"] = age
            response = await client.post(f"/api/v1/patients/{patient.id}/risk-screening", json=features)
            assert response.status_code == 200, response.text
            result = response.json()
            assert result["status"] == "ok", result
            assert result["feature_count"] == 32
            assert math.isfinite(result["probability"]) and 0 <= result["probability"] <= 1
            assert math.isfinite(result["risk_score"]) and 0 <= result["risk_score"] <= 100
            assert result["risk_score"] == pytest.approx(result["probability"] * 100, abs=0.005)
            assert "not a clinical diagnosis" in result["note"]
            assert hasattr(all_models, "RiskScreening"), "Successful screening must be persisted"
            rows = (await db_session.execute(select(all_models.RiskScreening).execution_options(populate_existing=True))).scalars().all()
            assert len(rows) == 1
            row = rows[0]
            assert row.patient_id == patient.id and row.consent_id == consent.id
            assert row.probability == result["probability"]
            assert row.risk_score == result["risk_score"]
            assert row.model_version == result["model_version"]
            assert row.screened_at is not None
            assert set(row.__table__.columns.keys()) == {
                "patient_id", "consent_id", "probability", "risk_score", "model_version", "screened_at",
            }
        audits = (await db_session.execute(select(AuditLog).where(AuditLog.resource_type == "risk_screening"))).scalars().all()
        assert len(audits) == 2
        assert all(a.resource_id == patient.id and a.user_id is not None for a in audits)
        assert all(a.details == {"status": "ok", "model_version": row.model_version} for a in audits)
        exported = await ComplianceService.export_patient_data(db_session, patient.id)
        assert exported["risk_screening"]["probability"] == row.probability
        assert patient.clinical_features is None


@pytest.mark.asyncio
@pytest.mark.parametrize("role,tier,consent,allowed", [
    ("clinician", None, "health_data", True),
    ("asha_worker", None, "all", True),
    ("admin", None, "health_data", True),
    ("family_caregiver", "clinical", "health_data", True),
    ("family_caregiver", "basic", "health_data", False),
    ("family_caregiver", None, "health_data", False),
    ("family_caregiver", "inactive", "health_data", False),
    ("patient", None, "health_data", False),
    ("clinician", None, "game_data", False),
])
async def test_access_gates_before_processing(role, tier, consent, allowed, client, db_session, monkeypatch):
    patient, _ = await screening_fixture(db_session, role, tier, consent)
    monkeypatch.setattr(risk, "_model_loaded", False)
    response = await client.post(f"/api/v1/patients/{patient.id}/risk-screening", json={})
    assert response.status_code == (200 if allowed else 403), response.text
    if allowed:
        assert response.json()["status"] == "model_unavailable"
    audits = (await db_session.execute(select(AuditLog).where(AuditLog.resource_type == "risk_screening"))).scalars().all()
    assert len(audits) == int(allowed)


@pytest.mark.asyncio
@pytest.mark.parametrize("role,tier,clinical", [
    ("family_caregiver", "basic", False),
    ("family_caregiver", "clinical", True),
    ("clinician", None, True),
    ("asha_worker", None, True),
])
async def test_export_omits_screening_unless_clinical(role, tier, clinical, client, db_session):
    patient, consent = await screening_fixture(db_session, role, tier)
    db_session.add(all_models.RiskScreening(
        patient_id=patient.id, consent_id=consent.id, probability=0.5, risk_score=50,
        model_version="sha256:test", screened_at=datetime.now(timezone.utc),
    ))
    await db_session.commit()
    response = await client.get(f"/api/v1/compliance/patients/{patient.id}/export")
    assert response.status_code == 200, response.text
    exported = response.json()
    assert exported["patient"]["id"] == str(patient.id)
    assert "game_sessions" in exported and "reminder_events" in exported
    if clinical:
        assert exported["risk_screening"]["probability"] == 0.5
        assert exported["risk_screening"]["risk_score"] == 50
    else:
        assert "risk_screening" not in exported
        assert all(name not in response.text for name in ("probability", "risk_score", "model_version", "screened_at"))
    audits = (await db_session.execute(select(AuditLog).where(AuditLog.resource_type == "data_export"))).scalars().all()
    assert len(audits) == 1
    assert audits[0].resource_id == patient.id


@pytest.mark.asyncio
async def test_clinical_export_fails_closed_on_audit_persistence_failure(client, db_session, monkeypatch):
    patient, consent = await screening_fixture(db_session)
    patient_id = patient.id
    db_session.add(all_models.RiskScreening(
        patient_id=patient_id, consent_id=consent.id, probability=0.5, risk_score=50,
        model_version="sha256:test", screened_at=datetime.now(timezone.utc),
    ))
    await db_session.commit()

    async def fail_commit():
        raise RuntimeError("isolated audit persistence failure")

    monkeypatch.setattr(db_session, "commit", fail_commit)
    response = await client.get(f"/api/v1/compliance/patients/{patient_id}/export")
    assert response.status_code == 503, response.text
    assert "risk_screening" not in response.json()
    assert "probability" not in response.text
    assert not (await db_session.execute(select(AuditLog))).scalars().all()
    assert (await db_session.execute(select(all_models.RiskScreening))).scalar_one().probability == 0.5


@pytest.mark.asyncio
async def test_screening_locks_active_consent_before_inference(client, db_session, monkeypatch):
    patient, _ = await screening_fixture(db_session)
    queries = []
    execute = db_session.execute

    async def capture(statement, *args, **kwargs):
        if any(item.get("entity") is ConsentRecord for item in getattr(statement, "column_descriptions", [])):
            queries.append(statement)
        return await execute(statement, *args, **kwargs)

    def infer(data):
        assert any(query._for_update_arg is not None for query in queries)
        return {"status": "model_unavailable"}

    monkeypatch.setattr(db_session, "execute", capture)
    monkeypatch.setattr(risk, "run_inference", infer)
    response = await client.post(f"/api/v1/patients/{patient.id}/risk-screening", json={})
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "model_unavailable"


@pytest.mark.asyncio
async def test_revoked_consent_blocks_processing(client, db_session):
    patient, consent = await screening_fixture(db_session)
    owner = await db_session.get(User, patient.user_id)
    await ComplianceService.revoke_consent(db_session, consent.id, actor=owner)
    response = await client.post(f"/api/v1/patients/{patient.id}/risk-screening", json={})
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_invalid_http_input_not_persisted(client, db_session, features, monkeypatch):
    patient, _ = await screening_fixture(db_session)
    monkeypatch.setattr(risk, "_model_loaded", True)
    features["Age"] = 59
    response = await client.post(f"/api/v1/patients/{patient.id}/risk-screening", json=features)
    assert response.status_code == 200
    assert response.json()["status"] == "validation_failed"
    assert hasattr(all_models, "RiskScreening")
    assert not (await db_session.execute(select(all_models.RiskScreening))).scalars().all()
    audits = (await db_session.execute(select(AuditLog))).scalars().all()
    assert len(audits) == 1
    assert audits[0].details["status"] == "validation_failed"
    assert not set(FEATURES).intersection(audits[0].details)


@pytest.mark.asyncio
async def test_audit_failure_rolls_back_success(client, db_session, features, monkeypatch):
    patient, _ = await screening_fixture(db_session)
    async with app.router.lifespan_context(app):
        async def fail_audit(*args, **kwargs):
            raise RuntimeError("isolated audit failure")

        monkeypatch.setattr(ComplianceService, "log_audit_access", fail_audit)
        response = await client.post(f"/api/v1/patients/{patient.id}/risk-screening", json=features)
        assert response.status_code == 503
        assert hasattr(all_models, "RiskScreening")
        assert not (await db_session.execute(select(all_models.RiskScreening))).scalars().all()


@pytest.mark.asyncio
async def test_screening_erased_after_consent_grace(client, db_session, features):
    patient, consent = await screening_fixture(db_session)
    async with app.router.lifespan_context(app):
        response = await client.post(f"/api/v1/patients/{patient.id}/risk-screening", json=features)
        assert response.json()["status"] == "ok"
    assert hasattr(all_models, "RiskScreening")
    consent.revoked_at = datetime.now(timezone.utc) - timedelta(days=31)
    await db_session.commit()
    await RetentionService.run_maintenance(db_session)
    assert not (await db_session.execute(select(all_models.RiskScreening))).scalars().all()
    assert len((await db_session.execute(select(AuditLog))).scalars().all()) == 1

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest
import sqlalchemy as sa


def test_real_cli_requires_explicit_extraction_authorization_without_connecting(tmp_path):
    output = tmp_path / "candidate.joblib"
    environment = {**os.environ, "ADAPTIVE_TRAIN_DATABASE_URL": "invalid://secret-must-not-appear"}
    result = subprocess.run([sys.executable, "train_adaptive.py", "--mode", "real", "--output", str(output)],
                            env=environment, capture_output=True, text=True)
    assert result.returncode == 2
    assert "authorization_required" in result.stdout
    assert "secret-must-not-appear" not in result.stdout + result.stderr
    assert not output.exists()


def test_real_extraction_requires_active_game_consent_and_allowlist(tmp_path):
    from train_adaptive import extract_real
    from app.models.base import Base
    from app.models.all_models import GameSession, DifficultyAdjustmentLog, GameLevelConfig, PatientProfile
    from app.models.compliance import ConsentRecord
    from app.models.user import User
    from datetime import timedelta
    from uuid import uuid4
    from tests.test_adaptive_features import NOW

    engine = sa.create_engine("sqlite://")
    Base.metadata.create_all(engine)
    allowed, revoked, unlisted = uuid4(), uuid4(), uuid4()
    with engine.begin() as connection:
        for patient in (allowed, revoked, unlisted):
            connection.execute(PatientProfile.__table__.insert().values(id=patient, name="Fixture"))
            connection.execute(ConsentRecord.__table__.insert().values(
                patient_id=patient, scope="game_data", granted_at=NOW - timedelta(days=20),
                revoked_at=NOW - timedelta(days=1) if patient == revoked else None))
            for index in range(3):
                completed = NOW - timedelta(days=index + 1)
                connection.execute(GameSession.__table__.insert().values(
                    patient_id=patient, game_type="match_it", difficulty_level=1,
                    started_at=completed - timedelta(seconds=60), completed_at=completed,
                    accuracy_pct=90, raw_event_log=[]))
            connection.execute(GameSession.__table__.insert().values(
                patient_id=patient, game_type="match_it", difficulty_level=2,
                started_at=NOW + timedelta(hours=1), completed_at=NOW + timedelta(hours=1, seconds=60), accuracy_pct=90))
            connection.execute(DifficultyAdjustmentLog.__table__.insert().values(
                patient_id=patient, game_type="match_it", old_difficulty=1, new_difficulty=2,
                adjusted_at=NOW, reason="fixture"))
    queries = []
    sa.event.listen(engine, "before_cursor_execute", lambda conn, cursor, statement, parameters, context, executemany: queries.append(statement))
    with engine.connect() as connection:
        examples, counts, _ = extract_real(connection, [allowed, revoked], NOW - timedelta(days=10), NOW + timedelta(days=2))
    assert len(examples) == 1
    assert examples[0].patient_id == str(allowed)
    assert examples[0].label == 1
    assert all("risk_screenings" not in query and "clinical_features" not in query and " JOIN patients" not in query for query in queries)
    assert counts["patients_without_active_game_consent"] == 1
    with engine.begin() as connection:
        connection.execute(GameSession.__table__.insert().values(
            patient_id=allowed, game_type="match_it", difficulty_level=2,
            started_at=NOW - timedelta(days=11), completed_at=NOW + timedelta(minutes=5), accuracy_pct=50))
        examples, counts, _ = extract_real(connection, [allowed], NOW - timedelta(days=10), NOW + timedelta(days=2))
        assert examples == []
        assert counts["outcome_started_before_decision"] == 1
    engine.dispose()

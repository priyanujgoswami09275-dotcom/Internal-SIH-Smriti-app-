from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

import pytest
import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from alembic.script import ScriptDirectory


MIGRATIONS = Path(__file__).resolve().parents[1] / "alembic"


def test_risk_screening_migration_is_additive_and_cascades():
    script = ScriptDirectory(str(MIGRATIONS))
    revision = script.get_revision("0008_risk_screening")
    assert revision.down_revision == "0007_number_recall"
    engine = sa.create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            connection.execute(sa.text("PRAGMA foreign_keys=ON"))
            connection.execute(sa.text("CREATE TABLE patients (id UUID PRIMARY KEY)"))
            connection.execute(sa.text("CREATE TABLE consent_records (id UUID PRIMARY KEY, patient_id UUID, UNIQUE(id, patient_id))"))
            connection.execute(sa.text("INSERT INTO patients VALUES ('patient')"))
            connection.execute(sa.text("INSERT INTO consent_records VALUES ('consent', 'patient')"))
            with Operations.context(MigrationContext.configure(connection)):
                revision.module.upgrade()
            connection.execute(sa.text(
                "INSERT INTO risk_screenings (patient_id, consent_id, probability, risk_score, model_version, screened_at) "
                "VALUES ('patient', 'consent', 0.5, 50, 'sha256:test', CURRENT_TIMESTAMP)"
            ))
            assert connection.execute(sa.text("SELECT COUNT(*) FROM risk_screenings")).scalar() == 1
            connection.execute(sa.text("DELETE FROM patients WHERE id = 'patient'"))
            assert connection.execute(sa.text("SELECT COUNT(*) FROM risk_screenings")).scalar() == 0
            with Operations.context(MigrationContext.configure(connection)):
                revision.module.downgrade()
            assert "risk_screenings" not in sa.inspect(connection).get_table_names()
            assert "patients" in sa.inspect(connection).get_table_names()
    finally:
        engine.dispose()


def test_shadow_migration_preserves_legacy_rows_and_round_trips():
    script = ScriptDirectory(str(MIGRATIONS))
    assert script.get_heads() == ["0009_shadow_difficulty"]
    revision = script.get_revision("0009_shadow_difficulty")
    assert revision.down_revision == "0008_risk_screening"
    engine = sa.create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            connection.execute(sa.text("CREATE TABLE difficulty_adjustment_logs (id INTEGER PRIMARY KEY, reason TEXT NOT NULL)"))
            connection.execute(sa.text("INSERT INTO difficulty_adjustment_logs VALUES (1, 'legacy')"))
            for _ in range(2):
                with Operations.context(MigrationContext.configure(connection)):
                    revision.module.upgrade()
                row = connection.execute(sa.text("SELECT * FROM difficulty_adjustment_logs")).mappings().one()
                assert row["reason"] == "legacy"
                assert all(row[field] is None for field in ("source", "rule_version", "result", "shadow_probability", "shadow_model_version", "shadow_reason"))
                connection.execute(sa.text("UPDATE difficulty_adjustment_logs SET source='rule_fallback', result='hold', shadow_probability=0.4"))
                with Operations.context(MigrationContext.configure(connection)):
                    revision.module.downgrade()
                assert dict(connection.execute(sa.text("SELECT * FROM difficulty_adjustment_logs")).mappings().one()) == {"id": 1, "reason": "legacy"}
    finally:
        engine.dispose()


def test_every_alembic_revision_id_fits_version_num_column():
    script = ScriptDirectory(str(MIGRATIONS))
    revisions = list(script.walk_revisions())
    assert revisions
    assert len(script.get_heads()) == 1
    assert all(len(revision.revision) <= 32 for revision in revisions)


@pytest.mark.parametrize("existing", [False, True])
def test_clinical_intake_upgrade_preserves_existing_data(existing):
    spec = spec_from_file_location(
        "clinical_intake_migration",
        MIGRATIONS / "versions" / "0005_demo_clinical_intake_placeholder.py",
    )
    migration = module_from_spec(spec)
    spec.loader.exec_module(migration)
    engine = sa.create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            connection.execute(sa.text("CREATE TABLE patients (id INTEGER PRIMARY KEY)"))
            if existing:
                connection.execute(sa.text("ALTER TABLE patients ADD COLUMN clinical_features JSON"))
                connection.execute(sa.text(
                    "INSERT INTO patients (id, clinical_features) VALUES (1, :features)"
                ), {"features": '{"score": 7}'})
            else:
                connection.execute(sa.text("INSERT INTO patients (id) VALUES (1)"))
            with Operations.context(MigrationContext.configure(connection)):
                migration.upgrade()
            columns = sa.inspect(connection).get_columns("patients")
            assert sum(column["name"] == "clinical_features" for column in columns) == 1
            row = connection.execute(sa.text("SELECT id, clinical_features FROM patients")).one()
            assert row.id == 1
            assert row.clinical_features == ('{"score": 7}' if existing else None)
    finally:
        engine.dispose()

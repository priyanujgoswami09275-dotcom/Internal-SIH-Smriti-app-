from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

import pytest
import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from alembic.script import ScriptDirectory


MIGRATIONS = Path(__file__).resolve().parents[1] / "alembic"


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

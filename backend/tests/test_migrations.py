import os
import pathlib
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
from uuid import uuid4

import pytest
import sqlalchemy as sa
from alembic import command
from alembic.config import Config
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
    assert script.get_heads() == ["0015_rls_public_tables"]
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


def test_odd_one_out_migration_additive_and_round_trips():
    import json

    script = ScriptDirectory(str(MIGRATIONS))
    assert script.get_heads() == ["0015_rls_public_tables"]
    revision = script.get_revision("0010_odd_one_out")
    assert revision.revision == "0010_odd_one_out"
    assert revision.down_revision == "0009_shadow_difficulty"
    engine = sa.create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            connection.execute(sa.text(
                "CREATE TABLE game_sessions (id INTEGER PRIMARY KEY, game_type VARCHAR(50))"
            ))
            connection.execute(sa.text(
                "INSERT INTO game_sessions (id, game_type) VALUES (1, 'match_it')"
            ))
            connection.execute(sa.text(
                "CREATE TABLE game_level_config "
                "(game_type VARCHAR(50), level INTEGER, params JSON)"
            ))
            with Operations.context(MigrationContext.configure(connection)):
                revision.module.upgrade()
            columns = [
                column["name"]
                for column in sa.inspect(connection).get_columns("game_sessions")
            ]
            assert "board_snapshot" in columns
            row = connection.execute(sa.text(
                "SELECT id, game_type, board_snapshot FROM game_sessions"
            )).mappings().one()
            assert row["id"] == 1
            assert row["game_type"] == "match_it"
            assert row["board_snapshot"] is None
            seeds = connection.execute(sa.text(
                "SELECT level, params FROM game_level_config "
                "WHERE game_type = 'odd_one_out' ORDER BY level"
            )).mappings().all()
            assert [s["level"] for s in seeds] == [1, 2, 3]
            assert json.loads(seeds[0]["params"]) == {"items": 3, "target_seconds": 45}
            assert json.loads(seeds[1]["params"]) == {"items": 4, "target_seconds": 70}
            assert json.loads(seeds[2]["params"]) == {"items": 6, "target_seconds": 120}
            with Operations.context(MigrationContext.configure(connection)):
                revision.module.downgrade()
            assert connection.execute(sa.text(
                "SELECT COUNT(*) FROM game_level_config WHERE game_type = 'odd_one_out'"
            )).scalar() == 0
            legacy = connection.execute(sa.text(
                "SELECT id, game_type, board_snapshot FROM game_sessions"
            )).mappings().one()
            assert legacy["id"] == 1
            assert legacy["game_type"] == "match_it"
            assert legacy["board_snapshot"] is None
            assert "game_sessions" in sa.inspect(connection).get_table_names()
            with Operations.context(MigrationContext.configure(connection)):
                revision.module.upgrade()
            assert connection.execute(sa.text(
                "SELECT COUNT(*) FROM game_level_config WHERE game_type = 'odd_one_out'"
            )).scalar() == 3
            rele = connection.execute(sa.text(
                "SELECT id, game_type, board_snapshot FROM game_sessions"
            )).mappings().one()
            assert rele["id"] == 1
            assert rele["board_snapshot"] is None
    finally:
        engine.dispose()


def test_every_alembic_revision_id_fits_version_num_column():
    script = ScriptDirectory(str(MIGRATIONS))
    revisions = list(script.walk_revisions())
    assert revisions
    assert len(script.get_heads()) == 1
    assert all(len(revision.revision) <= 32 for revision in revisions)


def test_rls_migration_is_postgres_only_and_adds_no_policies():
    """The RLS revision must be a no-op off PostgreSQL and must never create a
    policy: a permissive policy would create a second authorization path that
    conflicts with the app-layer gates in app/deps.py."""
    script = ScriptDirectory(str(MIGRATIONS))
    revision = script.get_revision("0015_rls_public_tables")
    assert revision.down_revision == "0014_reminder_idempotency"
    source = revision.module.__file__
    text = pathlib.Path(source).read_text()
    assert "CREATE POLICY" not in text.upper()
    assert "FORCE ROW LEVEL SECURITY" not in text.upper()

    engine = sa.create_engine("sqlite://")
    try:
        with engine.begin() as connection:
            # SQLite has no RLS; upgrade() must skip rather than raise.
            with Operations.context(MigrationContext.configure(connection)):
                revision.module.upgrade()
            with Operations.context(MigrationContext.configure(connection)):
                revision.module.downgrade()
    finally:
        engine.dispose()


def test_rls_migration_enables_every_public_table_on_postgres():
    """Against real PostgreSQL, every application table must end up with RLS
    on and zero policies, and the owner role must still read its own rows."""
    pytest.importorskip("psycopg")
    url = os.environ.get("RLS_MIGRATION_POSTGRES_URL")
    if not url:
        pytest.skip("Set RLS_MIGRATION_POSTGRES_URL to a disposable PostgreSQL database")
    assert url.startswith("postgresql"), "RLS_MIGRATION_POSTGRES_URL must be a PostgreSQL URL"
    engine = sa.create_engine(url, poolclass=sa.pool.NullPool)
    try:
        config = Config()
        config.set_main_option("script_location", str(MIGRATIONS))
        config.set_main_option("sqlalchemy.url", url.replace("%", "%%"))
        command.upgrade(config, "head")
        with engine.begin() as connection:
            tables = [
                row[0]
                for row in connection.execute(
                    sa.text(
                        "SELECT tablename FROM pg_tables "
                        "WHERE schemaname='public' AND tablename <> 'alembic_version'"
                    )
                )
            ]
            assert tables, "no application tables found"
            unprotected = [
                row[0]
                for row in connection.execute(
                    sa.text(
                        "SELECT tablename FROM pg_tables "
                        "WHERE schemaname='public' AND tablename <> 'alembic_version' "
                        "AND NOT rowsecurity"
                    )
                )
            ]
            assert unprotected == [], f"tables without RLS: {unprotected}"
            # No policies: a non-owner role must read nothing.
            assert connection.execute(
                sa.text("SELECT count(*) FROM pg_policies WHERE schemaname='public'")
            ).scalar() == 0
            # The owner path the API actually uses must keep working.
            probe_phone = f"+919{uuid4().int % 10**8:08d}"
            connection.execute(
                sa.text(
                    "INSERT INTO users (id, password_hash, phone, role, preferred_language) "
                    "VALUES (gen_random_uuid(), 'test-only', :phone, 'patient', 'english')"
                ),
                {"phone": probe_phone},
            )
            assert connection.execute(
                sa.text("SELECT count(*) FROM users WHERE phone = :phone"),
                {"phone": probe_phone},
            ).scalar() == 1
            connection.execute(
                sa.text("DELETE FROM users WHERE phone = :phone"), {"phone": probe_phone}
            )
        command.downgrade(config, "0014_reminder_idempotency")
        with engine.connect() as connection:
            disabled = [
                row[0]
                for row in connection.execute(
                    sa.text(
                        "SELECT tablename FROM pg_tables "
                        "WHERE schemaname='public' AND tablename <> 'alembic_version' "
                        "AND rowsecurity"
                    )
                )
            ]
            assert disabled == [], f"downgrade left RLS enabled on: {disabled}"
        command.upgrade(config, "head")
    finally:
        engine.dispose()


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

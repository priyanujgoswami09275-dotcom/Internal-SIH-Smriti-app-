import os
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
from uuid import uuid4

import pytest
import sqlalchemy as sa
from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy.engine import URL, make_url


MIGRATIONS = Path(__file__).resolve().parents[1] / "alembic"
TEMP_ROOT = Path("/var/folders/p6/skhrv32s2nl4mtknn7s6mj9c0000gn/T/opencode")
PG_BIN = Path("/opt/homebrew/bin")
REVISION = "0008_risk_screening"
PREVIOUS = "0007_number_recall"
pytestmark = pytest.mark.skipif(
    os.environ.get("RUN_RISK_MIGRATION_POSTGRES") != "1",
    reason="Set RUN_RISK_MIGRATION_POSTGRES=1 to use disposable PostgreSQL",
)


def _isolated_url(value):
    url = make_url(value)
    socket = url.query.get("host", "")
    if (
        url.drivername != "postgresql+psycopg"
        or url.host
        or url.password
        or set(url.query) != {"host"}
        or not socket
        or not Path(socket).is_absolute()
        or not Path(socket).resolve().is_relative_to(TEMP_ROOT.resolve())
        or not (url.database or "").startswith("test_risk_migration_")
    ):
        pytest.fail("RISK_MIGRATION_POSTGRES_URL must name an isolated test_risk_migration_ database using only a private Unix socket under TEMP_ROOT")
    return url


@pytest.fixture(scope="module")
def postgres_url():
    supplied = os.environ.get("RISK_MIGRATION_POSTGRES_URL")
    if supplied:
        yield _isolated_url(supplied)
        return
    subprocess.run(["ls", str(TEMP_ROOT)], check=True)
    for executable in ("initdb", "pg_ctl", "postgres"):
        if not (PG_BIN / executable).is_file():
            pytest.fail(f"Required PostgreSQL executable unavailable: {PG_BIN / executable}")
    environment = {"PATH": f"{PG_BIN}:/usr/bin:/bin", "LC_ALL": "C"}
    with tempfile.TemporaryDirectory(prefix="pg-", dir=TEMP_ROOT) as directory:
        root = Path(directory)
        data = root / "data"
        socket = root / "s"
        socket.mkdir(mode=0o700)
        try:
            subprocess.run(
                [str(PG_BIN / "initdb"), "-D", str(data), "-U", "postgres",
                 "--auth-local=trust", "--auth-host=reject", "--no-locale", "--encoding=UTF8"],
                env=environment, check=True, timeout=60,
            )
            subprocess.run(
                [str(PG_BIN / "pg_ctl"), "-D", str(data), "-l", str(root / "server.log"),
                 "-o", f"-c listen_addresses='' -c unix_socket_directories='{socket}' -c unix_socket_permissions=0700",
                 "-w", "-t", "30", "start"],
                env=environment, check=True, timeout=40,
            )
            yield URL.create(
                "postgresql+psycopg", username="postgres", database="postgres",
                query={"host": str(socket)},
            )
        finally:
            if (data / "postmaster.pid").exists():
                subprocess.run(
                    [str(PG_BIN / "pg_ctl"), "-D", str(data), "-m", "immediate", "-w", "stop"],
                    env=environment, check=True, timeout=40,
                )
            assert not (data / "postmaster.pid").exists()
            print("Private PostgreSQL stopped; no postmaster.pid remains")
    assert not root.exists()
    print("Private PostgreSQL temporary directory removed")


@pytest.fixture
def migration_database(postgres_url, monkeypatch):
    for variable in tuple(os.environ):
        if variable.startswith("PG"):
            monkeypatch.delenv(variable)
    monkeypatch.setenv("PGPASSFILE", str(TEMP_ROOT / f"absent-pgpass-{uuid4().hex}"))
    monkeypatch.setenv("PGSERVICEFILE", os.devnull)
    admin = sa.create_engine(postgres_url, isolation_level="AUTOCOMMIT", poolclass=sa.pool.NullPool)
    name = f"test_risk_migration_{uuid4().hex}"
    engine = None
    created = False
    try:
        with admin.connect() as connection:
            assert connection.scalar(sa.text("SHOW listen_addresses")) == ""
            assert connection.scalar(sa.text("SELECT inet_server_addr()")) is None
            print(connection.scalar(sa.text("SELECT version()")))
            connection.execute(sa.text(f'CREATE DATABASE "{name}"'))
            created = True
        url = postgres_url.set(database=name)
        rendered = url.render_as_string(hide_password=False).replace("%2F", "/")
        monkeypatch.setenv("DATABASE_URL", rendered)
        config = Config()
        config.set_main_option("script_location", str(MIGRATIONS))
        config.set_main_option("sqlalchemy.url", rendered.replace("%", "%%"))
        engine = sa.create_engine(url, poolclass=sa.pool.NullPool)
        script = ScriptDirectory.from_config(config)
        assert script.get_heads() == [REVISION]
        print(f"Single Alembic head: {REVISION} ({len(REVISION)} characters)")
        assert script.get_revision(REVISION).down_revision == PREVIOUS
        assert all(len(revision.revision) <= 32 for revision in script.walk_revisions())
        command.upgrade(config, PREVIOUS)
        with engine.connect() as connection:
            assert connection.scalar(sa.text("SELECT version_num FROM alembic_version")) == PREVIOUS
            assert "risk_screenings" not in sa.inspect(connection).get_table_names()
        yield config, engine
    finally:
        if engine is not None:
            engine.dispose()
        try:
            if created:
                with admin.connect() as connection:
                    connection.execute(sa.text(f'DROP DATABASE "{name}" WITH (FORCE)'))
                    assert connection.scalar(
                        sa.text("SELECT count(*) FROM pg_database WHERE datname = :name"), {"name": name},
                    ) == 0
                print("Disposable migration database dropped")
        finally:
            admin.dispose()


def _seed(connection):
    user_id, patient_id, consent_id = uuid4(), uuid4(), uuid4()
    connection.execute(sa.text(
        "INSERT INTO users (id, password_hash, email) VALUES (:id, 'test-only', :email)"
    ), {"id": user_id, "email": f"{user_id}@example.invalid"})
    connection.execute(sa.text(
        "INSERT INTO patients (id, user_id, name, clinical_features) "
        "VALUES (:id, :user_id, 'Migration fixture', CAST(:features AS json))"
    ), {"id": patient_id, "user_id": user_id, "features": '{"score": 7}'})
    connection.execute(sa.text(
        "INSERT INTO consent_records (id, patient_id, grantor_id, scope) "
        "VALUES (:id, :patient_id, :user_id, 'health_data')"
    ), {"id": consent_id, "patient_id": patient_id, "user_id": user_id})
    return {"patient_id": patient_id, "consent_id": consent_id}


def _snapshot(connection):
    return {
        table: connection.execute(sa.text(f"SELECT * FROM {table} ORDER BY id")).mappings().all()
        for table in ("users", "patients", "consent_records", "game_level_config")
    }


def _screening(ids, **changes):
    return {
        **ids, "probability": 0.5, "risk_score": 50.0,
        "model_version": "sha256:" + "a" * 64,
        "screened_at": datetime(2026, 9, 17, 12, 0), **changes,
    }


def _insert(connection, values):
    connection.execute(sa.text(
        "INSERT INTO risk_screenings "
        "(patient_id, consent_id, probability, risk_score, model_version, screened_at) "
        "VALUES (:patient_id, :consent_id, :probability, :risk_score, :model_version, :screened_at)"
    ), values)


def test_risk_migration_populated_round_trip(migration_database):
    config, engine = migration_database
    with engine.begin() as connection:
        ids = _seed(connection)
        before = _snapshot(connection)
    command.upgrade(config, REVISION)
    with engine.begin() as connection:
        assert _snapshot(connection) == before
        assert connection.scalar(sa.text("SELECT version_num FROM alembic_version")) == REVISION
        _insert(connection, _screening(ids))
        assert dict(connection.execute(sa.text("SELECT * FROM risk_screenings")).mappings().one()) == _screening(ids)
    command.downgrade(config, PREVIOUS)
    with engine.connect() as connection:
        assert "risk_screenings" not in sa.inspect(connection).get_table_names()
        assert connection.scalar(sa.text("SELECT version_num FROM alembic_version")) == PREVIOUS
        assert _snapshot(connection) == before
    command.upgrade(config, REVISION)
    with engine.begin() as connection:
        assert connection.scalar(sa.text("SELECT version_num FROM alembic_version")) == REVISION
        assert connection.scalar(sa.text("SELECT count(*) FROM risk_screenings")) == 0
        assert _snapshot(connection) == before
        _insert(connection, _screening(ids))
        assert dict(connection.execute(sa.text("SELECT * FROM risk_screenings")).mappings().one()) == _screening(ids)


def test_risk_migration_constraints(migration_database):
    config, engine = migration_database
    with engine.begin() as connection:
        ids = _seed(connection)
    command.upgrade(config, REVISION)
    invalid = [
        ({"probability": -0.01}, "23514", "ck_risk_probability"),
        ({"probability": 1.01}, "23514", "ck_risk_probability"),
        ({"risk_score": -0.01}, "23514", "ck_risk_score"),
        ({"risk_score": 100.01}, "23514", "ck_risk_score"),
        ({"patient_id": uuid4()}, "23503", None),
        ({"consent_id": uuid4()}, "23503", None),
    ]
    invalid.extend(({column: None}, "23502", None) for column in _screening(ids))
    with engine.begin() as connection:
        for changes, sqlstate, constraint in invalid:
            with pytest.raises(sa.exc.IntegrityError) as error:
                with connection.begin_nested():
                    _insert(connection, _screening(ids, **changes))
            assert error.value.orig.sqlstate == sqlstate
            if constraint:
                assert error.value.orig.diag.constraint_name == constraint
        with pytest.raises(sa.exc.DataError) as error:
            with connection.begin_nested():
                _insert(connection, _screening(ids, model_version="a" * 72))
        assert error.value.orig.sqlstate == "22001"
        for probability, risk_score in ((0.0, 0.0), (1.0, 100.0)):
            _insert(connection, _screening(ids, probability=probability, risk_score=risk_score))
            with pytest.raises(sa.exc.IntegrityError) as error:
                with connection.begin_nested():
                    _insert(connection, _screening(ids))
            assert error.value.orig.sqlstate == "23505"
            connection.execute(sa.text("DELETE FROM risk_screenings"))


@pytest.fixture
def consent_cascade(migration_database):
    config, engine = migration_database
    with engine.begin() as connection:
        ids = _seed(connection)
        unrelated = _seed(connection)
    command.upgrade(config, REVISION)
    with engine.begin() as connection:
        _insert(connection, _screening(ids))
        _insert(connection, _screening(unrelated))
    return engine, ids, unrelated


@pytest.fixture
def patient_cascade(migration_database):
    config, engine = migration_database
    with engine.begin() as connection:
        owner = _seed(connection)
        patient_id = uuid4()
        connection.execute(sa.text(
            "INSERT INTO patients (id, name) VALUES (:id, 'Independent cascade fixture')"
        ), {"id": patient_id})
    command.upgrade(config, REVISION)
    ids = {"patient_id": patient_id, "consent_id": owner["consent_id"]}
    with engine.begin() as connection:
        _insert(connection, _screening(ids))
        _insert(connection, _screening(owner))
    return engine, ids, owner


def test_risk_migration_consent_fk_cascade(consent_cascade):
    engine, ids, unrelated = consent_cascade
    with engine.begin() as connection:
        patients = connection.execute(sa.text("SELECT * FROM patients ORDER BY id")).all()
        connection.execute(sa.text("DELETE FROM consent_records WHERE id = :consent_id"), ids)
        assert connection.execute(sa.text("SELECT patient_id FROM risk_screenings")).scalars().all() == [unrelated["patient_id"]]
        assert connection.execute(sa.text("SELECT * FROM patients ORDER BY id")).all() == patients
        assert connection.execute(sa.text("SELECT id FROM consent_records")).scalars().all() == [unrelated["consent_id"]]


def test_risk_migration_patient_fk_cascade(patient_cascade):
    engine, ids, owner = patient_cascade
    with engine.begin() as connection:
        consents = connection.execute(sa.text("SELECT * FROM consent_records ORDER BY id")).all()
        connection.execute(sa.text("DELETE FROM patients WHERE id = :patient_id"), ids)
        assert connection.execute(sa.text("SELECT patient_id FROM risk_screenings")).scalars().all() == [owner["patient_id"]]
        assert connection.execute(sa.text("SELECT * FROM consent_records ORDER BY id")).all() == consents
        assert connection.execute(sa.text("SELECT id FROM patients")).scalars().all() == [owner["patient_id"]]

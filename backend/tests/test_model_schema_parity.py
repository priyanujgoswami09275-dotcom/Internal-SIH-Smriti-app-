"""Models and the migration-built schema must agree.

A fresh `alembic upgrade head` is the only supported way to create a database,
so a column, nullability, or unique constraint that exists in the ORM models
but not in the migrated schema is a latent production failure (or vice versa:
a constraint the app does not know about). This compares the two directly
against a real PostgreSQL database.

Opt-in: set SCHEMA_PARITY_POSTGRES_URL to a disposable PostgreSQL database that
has had `alembic upgrade head` applied. CI runs the equivalent check by
starting a clean service, migrating, and running this module.
"""
import os

import pytest
import sqlalchemy as sa

from app.models.base import Base
import app.models.all_models  # noqa: F401  (registers mappers)
import app.models.compliance  # noqa: F401
import app.models.user  # noqa: F401

SCHEMA_PARITY_URL = os.environ.get("SCHEMA_PARITY_POSTGRES_URL", "")

pytestmark = pytest.mark.skipif(
    not SCHEMA_PARITY_URL,
    reason="Set SCHEMA_PARITY_POSTGRES_URL to a migrated disposable PostgreSQL database",
)


@pytest.fixture
def migrated_engine():
    assert SCHEMA_PARITY_URL.startswith("postgresql"), "SCHEMA_PARITY_POSTGRES_URL must be PostgreSQL"
    engine = sa.create_engine(SCHEMA_PARITY_URL, poolclass=sa.pool.NullPool)
    try:
        yield engine
    finally:
        engine.dispose()


def test_models_match_the_migrated_schema(migrated_engine):
    eng = migrated_engine
    insp = sa.inspect(eng)
    db_tables = set(insp.get_table_names()) - {"alembic_version"}
    model_tables = set(Base.metadata.tables)
    diffs = []
    assert not (model_tables - db_tables), f"tables only in model: {sorted(model_tables - db_tables)}"
    assert not (db_tables - model_tables), f"tables only in DB: {sorted(db_tables - model_tables)}"
    for t in sorted(model_tables):
        table = Base.metadata.tables[t]
        mcols = {c.name for c in table.columns}
        dcols = {c["name"] for c in insp.get_columns(t)}
        if mcols - dcols:
            diffs.append(f"{t}: model-only columns {sorted(mcols - dcols)}")
        if dcols - mcols:
            diffs.append(f"{t}: db-only columns {sorted(dcols - mcols)}")
        pk = {c.name for c in table.primary_key.columns}
        for c in insp.get_columns(t):
            col = table.columns.get(c["name"])
            if col is None or c["name"] in pk:
                continue
            if bool(col.nullable) != bool(c.get("nullable", True)):
                diffs.append(f"{t}.{c['name']}: nullable model={col.nullable} db={c.get('nullable')}")
        m_uniques = {
            tuple(sorted(k.name for k in u.columns))
            for u in table.constraints
            if type(u).__name__ == "UniqueConstraint"
        }
        d_uniques = {tuple(sorted(u["column_names"])) for u in insp.get_unique_constraints(t)}
        for u in sorted(m_uniques - d_uniques):
            diffs.append(f"{t}: UNIQUE in model only: {list(u)}")
        for u in sorted(d_uniques - m_uniques):
            diffs.append(f"{t}: UNIQUE in DB only: {list(u)}")
        m_idx = {
            tuple(sorted(c.name for c in i.columns))
            for i in table.indexes
            if i.unique
        }
        # A UNIQUE constraint is implemented as a backing index; exclude those so
        # constraints are not double-counted as standalone indexes.
        d_idx = {
            tuple(sorted(i["column_names"]))
            for i in insp.get_indexes(t)
            if i.get("unique") and not i.get("duplicates_constraint")
        }
        for u in sorted(m_idx - d_idx):
            diffs.append(f"{t}: UNIQUE INDEX in model only: {list(u)}")
        for u in sorted(d_idx - m_idx):
            diffs.append(f"{t}: UNIQUE INDEX in DB only: {list(u)}")
    assert not diffs, "model/schema drift:\n  " + "\n  ".join(diffs)


def test_every_migrated_table_has_row_level_security(migrated_engine):
    """A fresh `alembic upgrade head` must produce RLS on every application
    table with no policies, so a non-owner role cannot read clinical data even
    if it holds a table GRANT. The API connects as the owner and is unaffected.
    """
    with migrated_engine.connect() as connection:
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
        policies = connection.execute(
            sa.text("SELECT count(*) FROM pg_policies WHERE schemaname='public'")
        ).scalar()
        assert policies == 0, (
            f"{policies} RLS policies exist; the app layer is meant to be the "
            "only authorization path"
        )

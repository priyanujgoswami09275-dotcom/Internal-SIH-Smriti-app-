"""Enable row-level security on every application table.

RLS was previously applied out-of-band on the Supabase project, so a fresh
`alembic upgrade head` produced a schema where clinical tables stayed readable
by any role holding a table GRANT, and the table added by 0012
(`game_actions`) was missed entirely because it post-dated the manual step.

This migration makes the security posture reproducible from code. It enables
RLS and nothing else: no policies are created, so a non-owner role reads zero
rows. That is deliberate and matches the API-only access model documented in
CLAUDE.md — the FastAPI app layer connects as the table owner (owners bypass
RLS unless FORCE is set) and is the single authorization point. Adding
permissive policies here would introduce a second, weaker authorization path
that the application does not use.

Tables are discovered from the live catalog rather than hard-coded, so any
table added by a later migration is covered as long as this revision runs at
or after it. `ENABLE ROW LEVEL SECURITY` is idempotent, so re-running against
a project that was fixed by hand is safe.

Downgrade disables RLS. That is a deliberate security regression and exists
only to keep the migration chain reversible; it should not be run against a
deployed database.
"""
revision = "0015_rls_public_tables"
down_revision = "0014_reminder_idempotency"

import sqlalchemy as sa
from alembic import op


def _application_tables(bind):
    """Public tables in the current database, excluding Alembic's own state table."""
    rows = bind.execute(
        sa.text(
            """
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'public'
              AND tablename <> 'alembic_version'
            ORDER BY tablename
            """
        )
    )
    return [row[0] for row in rows]


def _set_row_level_security(bind, enable):
    if bind.dialect.name != "postgresql":
        # RLS is a PostgreSQL feature; SQLite-backed test runs must not fail.
        return
    keyword = "ENABLE" if enable else "DISABLE"
    for table in _application_tables(bind):
        op.execute(
            f'ALTER TABLE "public"."{table}" {keyword} ROW LEVEL SECURITY'
        )


def upgrade() -> None:
    _set_row_level_security(op.get_bind(), enable=True)


def downgrade() -> None:
    _set_row_level_security(op.get_bind(), enable=False)

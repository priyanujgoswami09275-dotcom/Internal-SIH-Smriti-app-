"""Odd-One-Out game type + level-config seeds + board snapshot column.

Adds the PG enum value (GameTypeEnum.ODD_ONE_OUT), a nullable
board_snapshot JSON column on game_sessions (server-held answer for
select_odd_item scoring), and the three canonical rows (items 3/4/6).
Downgrade removes the rows only; the PG enum value is retained (Postgres
cannot drop enum values) and the additive board_snapshot column stays.
"""
revision = "0010_odd_one_out"
down_revision = "0009_shadow_difficulty"

from alembic import op
import sqlalchemy as sa


SEEDS = [
    ("odd_one_out", 1, {"items": 3, "target_seconds": 45}),
    ("odd_one_out", 2, {"items": 4, "target_seconds": 70}),
    ("odd_one_out", 3, {"items": 6, "target_seconds": 120}),
]


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name == "postgresql":
        # Existence-guarded: enum values survive downgrade (PG cannot drop
        # them), so an unguarded ADD VALUE breaks the round-trip.
        op.execute(
            "DO $$ BEGIN "
            "IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid "
            "WHERE t.typname = 'gametypeenum' AND e.enumlabel = 'odd_one_out') THEN "
            "ALTER TYPE gametypeenum ADD VALUE 'odd_one_out'; "
            "END IF; END $$;"
        )
    columns = [
        column["name"]
        for column in sa.inspect(bind).get_columns("game_sessions")
    ]
    if "board_snapshot" not in columns:
        op.add_column("game_sessions", sa.Column("board_snapshot", sa.JSON(), nullable=True))
    config = sa.table(
        "game_level_config",
        sa.column("game_type", sa.String(50)),
        sa.column("level", sa.Integer()),
        sa.column("params", sa.JSON()),
    )
    op.bulk_insert(
        config,
        [{"game_type": g, "level": l, "params": p} for g, l, p in SEEDS],
    )


def downgrade() -> None:
    # PG enum value 'odd_one_out' is intentionally retained: Postgres
    # cannot drop enum values, and existing sessions may reference it.
    # The additive board_snapshot column is likewise retained.
    op.execute(
        "DELETE FROM game_level_config WHERE game_type = 'odd_one_out'"
    )

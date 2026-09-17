"""Phase 4: number_recall game type + level-config seeds.

Adds the PG enum value (GameTypeEnum.NUMBER_RECALL) and the three
canonical rows (lengths 3/4/6, 2s per item). Downgrade removes the rows;
the enum value is retained (Postgres cannot drop enum values).
"""
revision = "0007_number_recall"
down_revision = "0006_game_level_config"

from alembic import op
import sqlalchemy as sa


SEEDS = [
    ("number_recall", 1, {"sequence_length": 3, "show_seconds_per_item": 2, "target_seconds": 60}),
    ("number_recall", 2, {"sequence_length": 4, "show_seconds_per_item": 2, "target_seconds": 90}),
    ("number_recall", 3, {"sequence_length": 6, "show_seconds_per_item": 2, "target_seconds": 150}),
]


def upgrade() -> None:
    op.execute("ALTER TYPE gametypeenum ADD VALUE 'number_recall'")
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
    op.execute(
        "DELETE FROM game_level_config WHERE game_type = 'number_recall'"
    )

"""Phase 2: game_level_config — single source of truth for difficulty params.

Creates the table and seeds the canonical grids (mirroring
level_config_service.DEFAULT_LEVEL_CONFIG): match_it pairs 2/4/6,
routine steps 3/4/6 with icons on at every level.
"""
revision = "0006_game_level_config"
down_revision = "0005_clinical_intake"

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


SEEDS = [
    ("match_it", 1, {"pairs": 2, "grid": "2x2", "target_seconds": 90}),
    ("match_it", 2, {"pairs": 4, "grid": "4x2", "target_seconds": 150}),
    ("match_it", 3, {"pairs": 6, "grid": "4x3", "target_seconds": 240}),
    ("routine_sequencing", 1, {"steps": 3, "hints": True, "icons": True, "target_seconds": 45}),
    ("routine_sequencing", 2, {"steps": 4, "hints": True, "icons": True, "target_seconds": 70}),
    ("routine_sequencing", 3, {"steps": 6, "hints": False, "icons": True, "target_seconds": 120}),
]


def upgrade() -> None:
    op.create_table(
        "game_level_config",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("game_type", sa.String(50), nullable=False),
        sa.Column("level", sa.Integer(), nullable=False),
        sa.Column("params", sa.JSON(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("game_type", "level"),
    )
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
    op.drop_table("game_level_config")

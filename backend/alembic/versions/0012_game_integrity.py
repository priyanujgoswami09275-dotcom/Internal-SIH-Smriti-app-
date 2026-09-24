revision = "0012_game_integrity"
down_revision = "0011_sync_idempotency"

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


def upgrade() -> None:
    op.add_column(
        "game_sessions",
        sa.Column("server_state", sa.JSON(), nullable=True),
    )
    op.add_column(
        "game_sessions",
        sa.Column("idempotency_key", sa.String(length=200), nullable=True),
    )
    op.add_column(
        "game_sessions",
        sa.Column("replay_completed_at", sa.DateTime(), nullable=True),
    )
    op.add_column(
        "game_sessions",
        sa.Column("completion_idempotency_key", sa.String(length=200), nullable=True),
    )
    op.add_column(
        "game_sessions",
        sa.Column("completion_result", sa.JSON(), nullable=True),
    )
    op.create_unique_constraint(
        "uq_game_sessions_patient_idempotency_key",
        "game_sessions",
        ["patient_id", "idempotency_key"],
    )
    op.create_unique_constraint(
        "uq_game_sessions_completion_idempotency_key",
        "game_sessions",
        ["completion_idempotency_key"],
    )
    op.create_table(
        "game_actions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "session_id",
            UUID(as_uuid=True),
            sa.ForeignKey("game_sessions.id"),
            nullable=False,
        ),
        sa.Column("idempotency_key", sa.String(length=200), nullable=False),
        sa.Column("action_type", sa.String(length=100), nullable=False),
        sa.Column("action_data", sa.JSON(), nullable=False),
        sa.Column("is_correct", sa.Boolean(), nullable=True),
        sa.Column("response_time_ms", sa.Integer(), nullable=True),
        sa.Column("server_fields", sa.JSON(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.UniqueConstraint(
            "session_id",
            "idempotency_key",
            name="uq_game_actions_session_idempotency_key",
        ),
    )


def downgrade() -> None:
    op.drop_table("game_actions")
    op.drop_constraint(
        "uq_game_sessions_patient_idempotency_key",
        "game_sessions",
        type_="unique",
    )
    op.drop_constraint(
        "uq_game_sessions_completion_idempotency_key",
        "game_sessions",
        type_="unique",
    )
    op.drop_column("game_sessions", "completion_result")
    op.drop_column("game_sessions", "completion_idempotency_key")
    op.drop_column("game_sessions", "replay_completed_at")
    op.drop_column("game_sessions", "idempotency_key")
    op.drop_column("game_sessions", "server_state")

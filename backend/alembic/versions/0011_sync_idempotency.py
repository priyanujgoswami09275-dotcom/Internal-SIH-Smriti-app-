revision = "0011_sync_idempotency"
down_revision = "0010_odd_one_out"

from alembic import op
import sqlalchemy as sa


def upgrade() -> None:
    op.add_column(
        "sync_queue",
        sa.Column("idempotency_key", sa.String(length=36), nullable=True),
    )
    op.execute(
        "UPDATE sync_queue "
        "SET idempotency_key = CAST(id AS VARCHAR(36)) "
        "WHERE idempotency_key IS NULL"
    )
    op.alter_column(
        "sync_queue",
        "idempotency_key",
        existing_type=sa.String(length=36),
        nullable=False,
    )
    op.create_unique_constraint(
        "uq_sync_queue_patient_idempotency_key",
        "sync_queue",
        ["patient_id", "idempotency_key"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_sync_queue_patient_idempotency_key",
        "sync_queue",
        type_="unique",
    )
    op.drop_column("sync_queue", "idempotency_key")

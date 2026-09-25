revision = "0014_reminder_idempotency"
down_revision = "0013_rag_integrity"

from alembic import op
import sqlalchemy as sa


def upgrade() -> None:
    op.add_column(
        "reminder_events",
        sa.Column("occurrence_key", sa.String(length=16), nullable=True),
    )
    op.add_column(
        "alert_flags",
        sa.Column("dedup_key", sa.String(length=8), nullable=True),
    )
    op.create_unique_constraint(
        "uq_reminder_events_patient_schedule_occurrence",
        "reminder_events",
        ["patient_id", "schedule_id", "occurrence_key"],
    )
    op.create_unique_constraint(
        "uq_alert_flags_patient_trigger_dedup",
        "alert_flags",
        ["patient_id", "trigger_type", "dedup_key"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_alert_flags_patient_trigger_dedup",
        "alert_flags",
        type_="unique",
    )
    op.drop_constraint(
        "uq_reminder_events_patient_schedule_occurrence",
        "reminder_events",
        type_="unique",
    )
    op.drop_column("alert_flags", "dedup_key")
    op.drop_column("reminder_events", "occurrence_key")

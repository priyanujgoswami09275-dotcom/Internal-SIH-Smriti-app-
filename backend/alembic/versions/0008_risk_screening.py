"""Persist the latest successful preliminary risk screening per patient."""
from alembic import op
import sqlalchemy as sa

revision = "0008_risk_screening"
down_revision = "0007_number_recall"


def upgrade() -> None:
    op.create_table(
        "risk_screenings",
        sa.Column("patient_id", sa.UUID(), sa.ForeignKey("patients.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("consent_id", sa.UUID(), sa.ForeignKey("consent_records.id", ondelete="CASCADE"), nullable=False),
        sa.Column("probability", sa.Float(), nullable=False),
        sa.Column("risk_score", sa.Float(), nullable=False),
        sa.Column("model_version", sa.String(71), nullable=False),
        sa.Column("screened_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("probability >= 0 AND probability <= 1", name="ck_risk_probability"),
        sa.CheckConstraint("risk_score >= 0 AND risk_score <= 100", name="ck_risk_score"),
    )


def downgrade() -> None:
    op.drop_table("risk_screenings")

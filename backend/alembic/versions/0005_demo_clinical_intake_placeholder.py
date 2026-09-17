"""DEMO ONLY — placeholder storage for 32 screening inputs.

NOT a production intake form. This is a temporary JSON column on PatientProfile
so the risk-screening endpoint can exercise demo data for a pitch.
A real clinical intake (restricted to ASHA-worker / clinician tier) is still
needed before any actual patient data can be collected.
"""
revision = "0005_clinical_intake"
down_revision = '0004_notifications'

from alembic import op
import sqlalchemy as sa


def upgrade() -> None:
    columns = sa.inspect(op.get_bind()).get_columns("patients")
    if not any(column["name"] == "clinical_features" for column in columns):
        op.add_column("patients", sa.Column("clinical_features", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("patients", "clinical_features")

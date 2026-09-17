from alembic import op
import sqlalchemy as sa


revision = "0009_shadow_difficulty"
down_revision = "0008_risk_screening"
branch_labels = None
depends_on = None


def upgrade():
    for name, kind in (
        ("source", sa.String(50)), ("rule_version", sa.String(80)),
        ("result", sa.String(10)), ("shadow_probability", sa.Float()),
        ("shadow_model_version", sa.String(120)), ("shadow_reason", sa.String(80)),
    ):
        op.add_column("difficulty_adjustment_logs", sa.Column(name, kind, nullable=True))


def downgrade():
    for name in ("shadow_reason", "shadow_model_version", "shadow_probability", "result", "rule_version", "source"):
        op.drop_column("difficulty_adjustment_logs", name)

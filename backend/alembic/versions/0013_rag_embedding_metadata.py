revision = "0013_rag_integrity"
down_revision = "0012_game_integrity"

from alembic import op
import sqlalchemy as sa


def upgrade() -> None:
    op.add_column(
        "medical_documents",
        sa.Column("embedding_provider", sa.String(length=50), nullable=True),
    )
    op.add_column(
        "medical_documents",
        sa.Column("embedding_model", sa.String(length=255), nullable=True),
    )
    op.add_column(
        "medical_documents",
        sa.Column("embedding_dimensions", sa.Integer(), nullable=True),
    )
    op.alter_column(
        "medical_documents",
        "extracted_text",
        type_=sa.Text(),
        existing_type=sa.String(length=10000),
        existing_nullable=True,
    )
    op.create_check_constraint(
        "ck_medical_documents_embedding_dimensions_positive",
        "medical_documents",
        "embedding_dimensions IS NULL OR embedding_dimensions > 0",
    )
    op.create_check_constraint(
        "ck_medical_documents_embedding_provenance_complete",
        "medical_documents",
        "(embedding_provider IS NULL AND embedding_model IS NULL AND embedding_dimensions IS NULL) "
        "OR (embedding_provider IS NOT NULL AND embedding_model IS NOT NULL AND embedding_dimensions IS NOT NULL)",
    )


def downgrade() -> None:
    op.alter_column(
        "medical_documents",
        "extracted_text",
        type_=sa.String(length=10000),
        existing_type=sa.Text(),
        existing_nullable=True,
    )
    op.drop_constraint(
        "ck_medical_documents_embedding_provenance_complete",
        "medical_documents",
        type_="check",
    )
    op.drop_constraint(
        "ck_medical_documents_embedding_dimensions_positive",
        "medical_documents",
        type_="check",
    )
    op.drop_column("medical_documents", "embedding_dimensions")
    op.drop_column("medical_documents", "embedding_model")
    op.drop_column("medical_documents", "embedding_provider")

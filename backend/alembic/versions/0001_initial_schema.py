"""Initial schema — all core tables from app.models.

Revision ID: 0001
Revises:
Create Date: 2026-09-04

Hand-written from the SQLAlchemy models (backend/app/models/) to match the
metadata exactly: users, patients, caregiver_patient_links, consent_records,
audit_logs, game_sessions, difficulty_adjustment_logs, reminder_schedules,
reminder_events, alert_flags, sync_queue, symptom_logs, medical_documents,
document_chunks, voice_companion_configs.

Enum type names mirror what SQLAlchemy derives from the Python enum classes
(lowercased class name).
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, ENUM

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

NOW = sa.text("now()")
TRUE = sa.text("true")


# Explicit enum types (created once, referenced by tables with create_type=False).
role_enum = ENUM("patient", "family_caregiver", "asha_worker", "clinician", "admin", name="roleenum", create_type=False)
consent_type_enum = ENUM(
    "patient_self", "guardian", "joint", "game_data", "health_data", "voice_companion",
    name="consenttypeenum", create_type=False,
)
audit_action_enum = ENUM("read", "write", "delete", name="auditactionenum", create_type=False)
cognitive_baseline_enum = ENUM(
    "healthy", "MCI", "mild_dementia", "moderate_dementia",
    name="cognitivebaselineenum", create_type=False,
)
relationship_type_enum = ENUM("family", "asha", "clinician", name="relationshiptypeenum", create_type=False)
permission_tier_enum = ENUM("basic", "clinical", name="permissiontierenum", create_type=False)
game_type_enum = ENUM("match_it", "routine_sequencing", name="gametypeenum", create_type=False)
reminder_type_enum = ENUM("medicine", "water", "food", "exercise", name="remindertypeenum", create_type=False)
reminder_status_enum = ENUM(
    "pending", "acknowledged", "missed", "escalated",
    name="reminderstatusenum", create_type=False,
)
ack_method_enum = ENUM("button", "voice", name="acknowledgmentmethodenum", create_type=False)
alert_trigger_enum = ENUM(
    "missed_reminders", "cognitive_score_dip", "activity_drop",
    name="alerttriggertypeenum", create_type=False,
)
alert_severity_enum = ENUM("info", "warning", "critical", name="alertseverityenum", create_type=False)
sync_resource_enum = ENUM(
    "game_session", "reminder_event", "offline_symptom",
    name="syncresourcetypeenum", create_type=False,
)
sync_operation_enum = ENUM("create", "update", "delete", name="syncoperationenum", create_type=False)
symptom_source_enum = ENUM(
    "manual_caregiver", "manual_asha", "manual_clinician",
    name="symptomentrysourceenum", create_type=False,
)
document_type_enum = ENUM(
    "pdf", "scanned_image", "report", "prescription",
    name="documenttypeenum", create_type=False,
)
embedding_status_enum = ENUM(
    "pending", "processing", "completed", "failed",
    name="embeddingstatusenum", create_type=False,
)

_ALL_ENUMS = [
    role_enum, consent_type_enum, audit_action_enum, cognitive_baseline_enum,
    relationship_type_enum, permission_tier_enum, game_type_enum,
    reminder_type_enum, reminder_status_enum, ack_method_enum,
    alert_trigger_enum, alert_severity_enum, sync_resource_enum,
    sync_operation_enum, symptom_source_enum, document_type_enum,
    embedding_status_enum,
]


def upgrade() -> None:
    for enum in _ALL_ENUMS:
        enum.create(op.get_bind(), checkfirst=True)

    # ---------- users ----------
    op.create_table(
        "users",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("phone", sa.String(20), nullable=True),
        sa.Column("email", sa.String(255), nullable=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("role", role_enum, nullable=False, server_default="patient"),
        sa.Column("preferred_language", sa.String(20), nullable=False, server_default="english"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=TRUE),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=NOW),
        sa.UniqueConstraint("phone", name="uq_users_phone"),
        sa.UniqueConstraint("email", name="uq_users_email"),
    )

    # ---------- patients ----------
    op.create_table(
        "patients",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("dob", sa.Date(), nullable=True),
        sa.Column("cognitive_baseline", cognitive_baseline_enum, nullable=False, server_default="healthy"),
        sa.Column("region", sa.String(100), nullable=True),
        sa.Column("district", sa.String(100), nullable=True),
        sa.Column("routine", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=NOW),
    )

    # ---------- caregiver_patient_links ----------
    op.create_table(
        "caregiver_patient_links",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("caregiver_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=False),
        sa.Column("relationship_type", relationship_type_enum, nullable=False),
        sa.Column("permission_tier", permission_tier_enum, nullable=False, server_default="basic"),
        sa.Column("consent_granted_at", sa.DateTime(), nullable=False, server_default=NOW),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=TRUE),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
    )

    # ---------- consent_records ----------
    op.create_table(
        "consent_records",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=False),
        sa.Column("consent_type", consent_type_enum, nullable=False, server_default="patient_self"),
        sa.Column("grantor_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("guardian_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("scope", sa.String(50), nullable=False, server_default="all"),
        sa.Column("granted_at", sa.DateTime(), nullable=False, server_default=NOW),
        sa.Column("revoked_at", sa.DateTime(), nullable=True),
        sa.Column("reason_for_revocation", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
    )

    # ---------- audit_logs ----------
    op.create_table(
        "audit_logs",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("action", audit_action_enum, nullable=False),
        sa.Column("resource_type", sa.String(50), nullable=False),
        sa.Column("resource_id", UUID(as_uuid=True), nullable=False),
        sa.Column("timestamp", sa.DateTime(), nullable=False, server_default=NOW),
        sa.Column("ip_address", sa.String(45), nullable=True),
        sa.Column("details", sa.JSON(), nullable=True),
    )

    # ---------- game_sessions ----------
    op.create_table(
        "game_sessions",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=False),
        sa.Column("game_type", game_type_enum, nullable=False),
        sa.Column("difficulty_level", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("content_pack_id", sa.String(100), nullable=True),
        sa.Column("routine_id", sa.String(100), nullable=True),
        sa.Column("started_at", sa.DateTime(), nullable=False, server_default=NOW),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("correct_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("incorrect_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("accuracy_pct", sa.Float(), nullable=True),
        sa.Column("avg_response_time_ms", sa.Float(), nullable=True),
        sa.Column("raw_event_log", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
    )

    # ---------- difficulty_adjustment_logs ----------
    op.create_table(
        "difficulty_adjustment_logs",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=False),
        sa.Column("game_type", game_type_enum, nullable=False),
        sa.Column("old_difficulty", sa.Integer(), nullable=False),
        sa.Column("new_difficulty", sa.Integer(), nullable=False),
        sa.Column("reason", sa.String(255), nullable=False),
        sa.Column("adjusted_at", sa.DateTime(), nullable=False, server_default=NOW),
        sa.Column("triggered_at", sa.DateTime(), nullable=False, server_default=NOW),
    )

    # ---------- reminder_schedules ----------
    op.create_table(
        "reminder_schedules",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=False),
        sa.Column("reminder_type", reminder_type_enum, nullable=False),
        sa.Column("cadence", sa.String(100), nullable=False),
        sa.Column("created_by", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=TRUE),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
    )

    # ---------- reminder_events ----------
    op.create_table(
        "reminder_events",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("schedule_id", UUID(as_uuid=True), sa.ForeignKey("reminder_schedules.id"), nullable=False),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=False),
        sa.Column("scheduled_at", sa.DateTime(), nullable=False),
        sa.Column("delivered_at", sa.DateTime(), nullable=True),
        sa.Column("acknowledged_at", sa.DateTime(), nullable=True),
        sa.Column("acknowledgment_method", ack_method_enum, nullable=True),
        sa.Column("status", reminder_status_enum, nullable=False, server_default="pending"),
        sa.Column("synced_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
    )

    # ---------- alert_flags ----------
    op.create_table(
        "alert_flags",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=False),
        sa.Column("trigger_type", alert_trigger_enum, nullable=False),
        sa.Column("threshold_detail", sa.JSON(), nullable=True),
        sa.Column("severity", alert_severity_enum, nullable=False),
        sa.Column("alert_summary", sa.String(500), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
        sa.Column("acknowledged_by", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("acknowledged_at", sa.DateTime(), nullable=True),
    )

    # ---------- sync_queue ----------
    op.create_table(
        "sync_queue",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=False),
        sa.Column("resource_type", sync_resource_enum, nullable=False),
        sa.Column("operation", sync_operation_enum, nullable=False),
        sa.Column("resource_id", UUID(as_uuid=True), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
        sa.Column("synced_at", sa.DateTime(), nullable=True),
        sa.Column("retry_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_error", sa.String(500), nullable=True),
    )

    # ---------- symptom_logs ----------
    op.create_table(
        "symptom_logs",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=False),
        sa.Column("entered_by", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("entry_source", symptom_source_enum, nullable=False, server_default="manual_caregiver"),
        sa.Column("notes", sa.String(2000), nullable=False),
        sa.Column("severity", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("timestamp", sa.DateTime(), nullable=False, server_default=NOW),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
    )

    # ---------- medical_documents ----------
    op.create_table(
        "medical_documents",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=False),
        sa.Column("uploaded_by", UUID(as_uuid=True), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("title", sa.String(255), nullable=True, server_default="Medical Document"),
        sa.Column("file_ref", sa.String(500), nullable=False),
        sa.Column("doc_type", document_type_enum, nullable=False, server_default="report"),
        sa.Column("embedding_status", embedding_status_enum, nullable=False, server_default="pending"),
        sa.Column("extracted_text", sa.String(10000), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
    )

    # ---------- document_chunks ----------
    op.create_table(
        "document_chunks",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("document_id", UUID(as_uuid=True), sa.ForeignKey("medical_documents.id"), nullable=False),
        sa.Column("patient_id", UUID(as_uuid=True), sa.ForeignKey("patients.id"), nullable=True),
        sa.Column("chunk_text", sa.String(2000), nullable=False),
        sa.Column("embedding", sa.JSON(), nullable=True),
        sa.Column("page_ref", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
    )

    # ---------- voice_companion_configs ----------
    op.create_table(
        "voice_companion_configs",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column("version", sa.String(50), nullable=False),
        sa.Column("system_prompt", sa.String(5000), nullable=False),
        sa.Column("persona_name", sa.String(100), nullable=False, server_default="Saathi"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=TRUE),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=NOW),
        sa.UniqueConstraint("version", name="uq_voice_companion_configs_version"),
    )


def downgrade() -> None:
    for table in [
        "document_chunks",
        "medical_documents",
        "symptom_logs",
        "sync_queue",
        "alert_flags",
        "reminder_events",
        "reminder_schedules",
        "difficulty_adjustment_logs",
        "game_sessions",
        "audit_logs",
        "consent_records",
        "caregiver_patient_links",
        "patients",
        "users",
        "voice_companion_configs",
    ]:
        op.drop_table(table)

    for enum in reversed(_ALL_ENUMS):
        enum.drop(op.get_bind(), checkfirst=True)

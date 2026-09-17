from sqlalchemy import Column, String, Date, JSON, DateTime, func, ForeignKey, Enum as SQLEnum, Boolean, Integer, Float, UniqueConstraint, CheckConstraint
from sqlalchemy.dialects.postgresql import UUID
import uuid
from enum import Enum
from app.models.base import Base, enum_values
from app.models.user import User, RoleEnum
from app.models.compliance import (
    ConsentRecord, ConsentTypeEnum, ConsentScopeEnum,
    AuditLog, AuditActionEnum
)

class CognitiveBaselineEnum(str, Enum):
    HEALTHY = "healthy"
    MCI = "MCI"
    MILD_DEMENTIA = "mild_dementia"
    MODERATE_DEMENTIA = "moderate_dementia"

class RelationshipTypeEnum(str, Enum):
    FAMILY = "family"
    ASHA = "asha"
    CLINICIAN = "clinician"

class PermissionTierEnum(str, Enum):
    BASIC = "basic"
    CLINICAL = "clinical"

class PatientProfile(Base):
    __tablename__ = "patients"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    name = Column(String(255), nullable=False)
    dob = Column(Date, nullable=True)
    cognitive_baseline = Column(SQLEnum(CognitiveBaselineEnum, values_callable=enum_values), nullable=False, default=CognitiveBaselineEnum.HEALTHY)
    region = Column(String(100), nullable=True)
    district = Column(String(100), nullable=True)
    routine = Column(JSON, nullable=True)
    clinical_features = Column(JSON, nullable=True)  # DEMO ONLY — placeholder for 32 screening inputs (age/bmi/mmse/etc). Real clinical intake form (ASHA/clinician tier) still needed.
    created_at = Column(DateTime, default=func.now(), nullable=False)
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now(), nullable=False)

class CaregiverPatientLink(Base):
    __tablename__ = "caregiver_patient_links"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    caregiver_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False)
    relationship_type = Column(SQLEnum(RelationshipTypeEnum, values_callable=enum_values), nullable=False)
    permission_tier = Column(SQLEnum(PermissionTierEnum, values_callable=enum_values), nullable=False, default=PermissionTierEnum.BASIC)
    consent_granted_at = Column(DateTime, default=func.now(), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)

class GameTypeEnum(str, Enum):
    MATCH_IT = "match_it"
    ROUTINE_SEQUENCING = "routine_sequencing"
    NUMBER_RECALL = "number_recall"

class GameSession(Base):
    __tablename__ = "game_sessions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False)
    game_type = Column(SQLEnum(GameTypeEnum, values_callable=enum_values), nullable=False)
    difficulty_level = Column(Integer, nullable=False, default=1)
    content_pack_id = Column(String(100), nullable=True)
    routine_id = Column(String(100), nullable=True)
    started_at = Column(DateTime, default=func.now(), nullable=False)
    completed_at = Column(DateTime, nullable=True)
    attempts = Column(Integer, nullable=False, default=0)
    correct_count = Column(Integer, nullable=False, default=0)
    incorrect_count = Column(Integer, nullable=False, default=0)
    accuracy_pct = Column(Float, nullable=True)
    avg_response_time_ms = Column(Float, nullable=True)
    raw_event_log = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=func.now(), nullable=False)

class DifficultyAdjustmentLog(Base):
    __tablename__ = "difficulty_adjustment_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False)
    game_type = Column(SQLEnum(GameTypeEnum, values_callable=enum_values), nullable=False)
    old_difficulty = Column(Integer, nullable=False)
    new_difficulty = Column(Integer, nullable=False)
    reason = Column(String(255), nullable=False)
    adjusted_at = Column(DateTime, default=func.now(), nullable=False)
    triggered_at = Column(DateTime, default=func.now(), nullable=False)
    source = Column(String(50), nullable=True)
    rule_version = Column(String(80), nullable=True)
    result = Column(String(10), nullable=True)
    shadow_probability = Column(Float, nullable=True)
    shadow_model_version = Column(String(120), nullable=True)
    shadow_reason = Column(String(80), nullable=True)

class GameLevelConfig(Base):
    """Single source of truth for per-game difficulty parameters.

    Board generators resolve values through level_config_service (DB row,
    else DEFAULT_LEVEL_CONFIG fallback); mobile mirrors via
    GET /games/level-config with a bundled fallback. No other module may
    hardcode pair/step counts.
    """
    __tablename__ = "game_level_config"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    game_type = Column(String(50), nullable=False)
    level = Column(Integer, nullable=False)
    params = Column(JSON, nullable=False)
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now(), nullable=False)

    __table_args__ = (UniqueConstraint("game_type", "level"),)

class ReminderTypeEnum(str, Enum):
    MEDICINE = "medicine"
    WATER = "water"
    FOOD = "food"
    EXERCISE = "exercise"

class ReminderStatusEnum(str, Enum):
    PENDING = "pending"
    ACKNOWLEDGED = "acknowledged"
    MISSED = "missed"
    ESCALATED = "escalated"

class AcknowledgmentMethodEnum(str, Enum):
    BUTTON = "button"
    VOICE = "voice"

class ReminderSchedule(Base):
    __tablename__ = "reminder_schedules"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False)
    reminder_type = Column(SQLEnum(ReminderTypeEnum, values_callable=enum_values), nullable=False)
    cadence = Column(String(100), nullable=False)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)

class ReminderEvent(Base):
    __tablename__ = "reminder_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    schedule_id = Column(UUID(as_uuid=True), ForeignKey("reminder_schedules.id"), nullable=False)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False)
    scheduled_at = Column(DateTime, nullable=False)
    delivered_at = Column(DateTime, nullable=True)
    acknowledged_at = Column(DateTime, nullable=True)
    acknowledgment_method = Column(SQLEnum(AcknowledgmentMethodEnum, values_callable=enum_values), nullable=True)
    status = Column(SQLEnum(ReminderStatusEnum, values_callable=enum_values), nullable=False, default=ReminderStatusEnum.PENDING)
    synced_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=func.now(), nullable=False)

class AlertTriggerTypeEnum(str, Enum):
    MISSED_REMINDERS = "missed_reminders"
    COGNITIVE_SCORE_DIP = "cognitive_score_dip"
    ACTIVITY_DROP = "activity_drop"

class AlertSeverityEnum(str, Enum):
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"

class AlertFlag(Base):
    __tablename__ = "alert_flags"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False)
    trigger_type = Column(SQLEnum(AlertTriggerTypeEnum, values_callable=enum_values), nullable=False)
    threshold_detail = Column(JSON, nullable=True)
    severity = Column(SQLEnum(AlertSeverityEnum, values_callable=enum_values), nullable=False)
    alert_summary = Column(String(500), nullable=True)
    created_at = Column(DateTime, default=func.now(), nullable=False)
    acknowledged_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    acknowledged_at = Column(DateTime, nullable=True)

class SyncResourceTypeEnum(str, Enum):
    GAME_SESSION = "game_session"
    REMINDER_EVENT = "reminder_event"
    OFFLINE_SYMPTOM = "offline_symptom"

class SyncOperationEnum(str, Enum):
    CREATE = "create"
    UPDATE = "update"
    DELETE = "delete"

class SyncQueue(Base):
    __tablename__ = "sync_queue"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False)
    resource_type = Column(SQLEnum(SyncResourceTypeEnum, values_callable=enum_values), nullable=False)
    operation = Column(SQLEnum(SyncOperationEnum, values_callable=enum_values), nullable=False)
    resource_id = Column(UUID(as_uuid=True), nullable=False)
    payload = Column(JSON, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)
    synced_at = Column(DateTime, nullable=True)
    retry_count = Column(Integer, default=0, nullable=False)
    last_error = Column(String(500), nullable=True)

class SymptomEntrySourceEnum(str, Enum):
    MANUAL_CAREGIVER = "manual_caregiver"
    MANUAL_ASHA = "manual_asha"
    MANUAL_CLINICIAN = "manual_clinician"

class SymptomLog(Base):
    __tablename__ = "symptom_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False)
    entered_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    entry_source = Column(SQLEnum(SymptomEntrySourceEnum, values_callable=enum_values), default=SymptomEntrySourceEnum.MANUAL_CAREGIVER, nullable=False)
    notes = Column(String(2000), nullable=False)  # Encrypted at rest
    severity = Column(Integer, default=1, nullable=False)  # 1-5 scale
    timestamp = Column(DateTime, default=func.now(), nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)

class DocumentTypeEnum(str, Enum):
    PDF = "pdf"
    SCANNED_IMAGE = "scanned_image"
    REPORT = "report"
    PRESCRIPTION = "prescription"

class EmbeddingStatusEnum(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"

class MedicalDocument(Base):
    __tablename__ = "medical_documents"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False)
    uploaded_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    title = Column(String(255), nullable=True, default="Medical Document")
    file_ref = Column(String(500), nullable=False)
    doc_type = Column(SQLEnum(DocumentTypeEnum, values_callable=enum_values), nullable=False, default=DocumentTypeEnum.REPORT)
    embedding_status = Column(SQLEnum(EmbeddingStatusEnum, values_callable=enum_values), nullable=False, default=EmbeddingStatusEnum.PENDING)
    extracted_text = Column(String(10000), nullable=True)
    created_at = Column(DateTime, default=func.now(), nullable=False)

class DocumentChunk(Base):
    __tablename__ = "document_chunks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    document_id = Column(UUID(as_uuid=True), ForeignKey("medical_documents.id"), nullable=False)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=True)
    chunk_text = Column(String(2000), nullable=False)
    embedding = Column(JSON, nullable=True)  # List of floats or pgvector
    page_ref = Column(Integer, default=1, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)


class WeeklyReport(Base):
    """P7 — persisted weekly clinical summary (one per patient per week)."""

    __tablename__ = "weekly_reports"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False, index=True)
    week_start = Column(DateTime, nullable=False, index=True)  # Monday 00:00 UTC
    generated_at = Column(DateTime, default=func.now(), nullable=False)
    report_json = Column(JSON, nullable=False)  # ReportService summary payload

class UserDeviceToken(Base):
    __tablename__ = "user_device_tokens"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    fcm_token = Column(String(500), nullable=True)
    phone = Column(String(50), nullable=True)
    platform = Column(String(20), nullable=False, default="android")
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now(), nullable=False)

class NotificationDeliveryStatusEnum(str, Enum):
    SENT = "sent"
    FAILED = "failed"

class NotificationKindEnum(str, Enum):
    REPROMPT = "reprompt"
    ALERT = "alert"

class NotificationDelivery(Base):
    __tablename__ = "notification_deliveries"
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    provider = Column(String(20), nullable=False)
    kind = Column(SQLEnum(NotificationKindEnum, values_callable=enum_values), nullable=False)
    event_id = Column(UUID(as_uuid=True), nullable=True)
    recipient_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    address = Column(String(500), nullable=True)
    status = Column(SQLEnum(NotificationDeliveryStatusEnum, values_callable=enum_values), nullable=False, default=NotificationDeliveryStatusEnum.SENT)
    created_at = Column(DateTime, default=func.now(), nullable=False)

class RiskScreening(Base):
    __tablename__ = "risk_screenings"

    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id", ondelete="CASCADE"), primary_key=True)
    consent_id = Column(UUID(as_uuid=True), ForeignKey("consent_records.id", ondelete="CASCADE"), nullable=False)
    probability = Column(Float, nullable=False)
    risk_score = Column(Float, nullable=False)
    model_version = Column(String(71), nullable=False)
    screened_at = Column(DateTime, default=func.now(), nullable=False)

    __table_args__ = (
        CheckConstraint("probability >= 0 AND probability <= 1", name="ck_risk_probability"),
        CheckConstraint("risk_score >= 0 AND risk_score <= 100", name="ck_risk_score"),
    )


class VoiceCompanionConfig(Base):
    __tablename__ = "voice_companion_configs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    version = Column(String(50), nullable=False, unique=True)
    system_prompt = Column(String(5000), nullable=False)
    persona_name = Column(String(100), default="Saathi", nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)


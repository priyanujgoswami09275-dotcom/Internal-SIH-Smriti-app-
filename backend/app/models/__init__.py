"""Model registry for the private, API-owned database.

Tracked backend, mobile, and dashboard source does not consume a Supabase
anon/publishable key or expose a direct-table client. The server-side
``DATABASE_URL`` is used only by the backend, and direct Supabase table access
must remain disabled. Migrations create tables in the database's default public
schema. This repository defines no RLS policies or SQL GRANT/REVOKE statements;
remote Supabase/RLS/grant state must be verified separately.
"""

from app.models.base import Base
from app.models.user import User, RoleEnum
from app.models.compliance import ConsentRecord, AuditLog, ConsentTypeEnum, ConsentScopeEnum, AuditActionEnum
from app.models.all_models import (
    PatientProfile, CaregiverPatientLink, GameSession, DifficultyAdjustmentLog,
    ReminderSchedule, ReminderEvent, AlertFlag, SyncQueue,
    SymptomLog, MedicalDocument, DocumentChunk, VoiceCompanionConfig, WeeklyReport,
    UserDeviceToken, NotificationDelivery, RiskScreening,
    CognitiveBaselineEnum, RelationshipTypeEnum, PermissionTierEnum,
    GameTypeEnum, ReminderTypeEnum, ReminderStatusEnum, AcknowledgmentMethodEnum,
    AlertTriggerTypeEnum, AlertSeverityEnum, SyncResourceTypeEnum, SyncOperationEnum,
    SymptomEntrySourceEnum, DocumentTypeEnum, EmbeddingStatusEnum,
    NotificationDeliveryStatusEnum, NotificationKindEnum,
)

__all__ = [
    "Base", "User", "RoleEnum",
    "PatientProfile", "CaregiverPatientLink",
    "ConsentRecord", "AuditLog",
    "GameSession", "DifficultyAdjustmentLog",
    "ReminderSchedule", "ReminderEvent",
    "AlertFlag", "SyncQueue",
    "SymptomLog", "MedicalDocument", "DocumentChunk", "VoiceCompanionConfig",
    "WeeklyReport", "UserDeviceToken", "NotificationDelivery", "RiskScreening",
]

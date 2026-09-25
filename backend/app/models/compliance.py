from sqlalchemy import Column, String, Boolean, DateTime, func, ForeignKey, Enum as SQLEnum, JSON, event
from sqlalchemy.dialects.postgresql import UUID
import uuid
from enum import Enum
from app.models.base import Base, enum_values

class ConsentTypeEnum(str, Enum):
    PATIENT_SELF = "patient_self"
    GUARDIAN = "guardian"
    JOINT = "joint"
    GAME_DATA = "game_data"
    HEALTH_DATA = "health_data"
    VOICE_COMPANION = "voice_companion"

class ConsentScopeEnum(str, Enum):
    ALL = "all"
    GAME_DATA = "game_data"
    HEALTH_DATA = "health_data"
    VOICE_COMPANION = "voice_companion"
    PATIENT_SELF = "patient_self"
    GUARDIAN = "guardian"
    JOINT = "joint"

class ConsentRecord(Base):
    __tablename__ = "consent_records"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("patients.id"), nullable=False)
    consent_type = Column(SQLEnum(ConsentTypeEnum, values_callable=enum_values), nullable=False, default=ConsentTypeEnum.PATIENT_SELF)
    grantor_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    guardian_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    scope = Column(String(50), nullable=False, default="all")
    granted_at = Column(DateTime, default=func.now(), nullable=False)
    revoked_at = Column(DateTime, nullable=True)
    reason_for_revocation = Column(String(500), nullable=True)
    created_at = Column(DateTime, default=func.now(), nullable=False)

class AuditActionEnum(str, Enum):
    READ = "read"
    WRITE = "write"
    DELETE = "delete"

class AuditLog(Base):
    """Audit event that is append-only through SQLAlchemy ORM objects.

    This application guard does not protect SQLAlchemy Core bulk statements or
    database roles. No database trigger or grant-based immutability has been
    verified for this deployment.
    """

    __tablename__ = "audit_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    action = Column(SQLEnum(AuditActionEnum, values_callable=enum_values), nullable=False)
    resource_type = Column(String(50), nullable=False)
    resource_id = Column(UUID(as_uuid=True), nullable=False)
    timestamp = Column(DateTime, default=func.now(), nullable=False)
    ip_address = Column(String(45), nullable=True)
    details = Column(JSON, nullable=True)


class AuditLogMutationError(RuntimeError):
    pass


def _reject_audit_log_mutation(mapper, connection, target) -> None:
    raise AuditLogMutationError("AuditLog rows are append-only through the application ORM")


event.listen(AuditLog, "before_update", _reject_audit_log_mutation)
event.listen(AuditLog, "before_delete", _reject_audit_log_mutation)

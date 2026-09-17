"""Model instantiation tests — verify all models construct without DB."""
import uuid
from sqlalchemy import Enum as SQLEnum

from app.models.base import Base, enum_values
from app.models.user import User, RoleEnum
from app.models.all_models import (
    PatientProfile, CaregiverPatientLink, GameSession,
    ReminderSchedule, ReminderEvent, AlertFlag, SyncQueue,
    CognitiveBaselineEnum, RelationshipTypeEnum, PermissionTierEnum,
    GameTypeEnum, ReminderTypeEnum, ReminderStatusEnum,
    AlertTriggerTypeEnum, AlertSeverityEnum,
    SyncResourceTypeEnum, SyncOperationEnum,
)
from app.models.compliance import ConsentRecord, AuditLog, ConsentTypeEnum, ConsentScopeEnum, AuditActionEnum


def test_all_enum_columns_persist_lowercase_values():
    """Regression: every Enum column must store values ("patient", "match_it"),
    not member names ("PATIENT", "MATCH_IT").

    Without values_callable, SQLAlchemy persists enum member NAMES, which
    Postgres native enums (created by migration 0001 with lowercase values)
    reject with InvalidTextRepresentation. SQLite tests never catch this
    because SQLite renders CHECK constraints, so this guard introspects the
    metadata instead.
    """
    offenders = []
    for table in Base.metadata.sorted_tables:
        for col in table.columns:
            if isinstance(col.type, SQLEnum) and not col.type.values_callable:
                offenders.append(f"{table.name}.{col.name}")
    assert not offenders, (
        "Enum columns missing values_callable=enum_values "
        f"(would break on Postgres native enums): {offenders}"
    )
    # Sanity: enum_values yields the lowercase values the migration declares.
    assert enum_values(RoleEnum) == ["patient", "family_caregiver", "asha_worker", "clinician", "admin"]
    assert enum_values(GameTypeEnum) == ["match_it", "routine_sequencing", "number_recall"]


def test_user_model():
    u = User(phone="+919876543210", role=RoleEnum.PATIENT, preferred_language="assamese")
    assert u.role == RoleEnum.PATIENT
    assert u.preferred_language == "assamese"


def test_patient_model():
    p = PatientProfile(name="Phukan Borah", cognitive_baseline=CognitiveBaselineEnum.MCI, region="Assam", district="Kamrup")
    assert p.name == "Phukan Borah"
    assert p.cognitive_baseline == CognitiveBaselineEnum.MCI


def test_caregiver_link():
    # Column ``default=True`` is applied at INSERT time by SQLAlchemy, so
    # construct-time assertion needs the value passed explicitly.
    link = CaregiverPatientLink(
        caregiver_id=uuid.uuid4(),
        patient_id=uuid.uuid4(),
        relationship_type=RelationshipTypeEnum.FAMILY,
        permission_tier=PermissionTierEnum.BASIC,
        is_active=True,
    )
    assert link.relationship_type == RelationshipTypeEnum.FAMILY
    assert link.is_active is True


def test_consent_record():
    c = ConsentRecord(
        patient_id=uuid.uuid4(),
        consent_type=ConsentTypeEnum.HEALTH_DATA,
        grantor_id=uuid.uuid4(),
        scope=ConsentScopeEnum.GUARDIAN,
    )
    assert c.consent_type == ConsentTypeEnum.HEALTH_DATA
    assert c.scope == ConsentScopeEnum.GUARDIAN


def test_audit_log():
    log = AuditLog(
        user_id=uuid.uuid4(),
        action=AuditActionEnum.READ,
        resource_type="patient_profile",
        resource_id=uuid.uuid4(),
    )
    assert log.action == AuditActionEnum.READ


def test_game_session():
    gs = GameSession(
        patient_id=uuid.uuid4(),
        game_type=GameTypeEnum.MATCH_IT,
        difficulty_level=2,
        correct_count=6,
        incorrect_count=1,
    )
    assert gs.game_type == GameTypeEnum.MATCH_IT
    assert gs.correct_count == 6


def test_sync_queue():
    sq = SyncQueue(
        patient_id=uuid.uuid4(),
        resource_type=SyncResourceTypeEnum.GAME_SESSION,
        operation=SyncOperationEnum.CREATE,
        resource_id=uuid.uuid4(),
        payload={"score": 90},
    )
    assert sq.resource_type == SyncResourceTypeEnum.GAME_SESSION
    assert sq.synced_at is None

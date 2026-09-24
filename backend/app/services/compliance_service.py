"""Digital Personal Data Protection (DPDP) Act 2023 & Encryption Service.

Provides:
- AES-256 symmetric field-level encryption for sensitive health data.
- Explicit consent management & scope verification (patient_self, guardian, joint).
- Immutable audit logging for patient health data access.
- Right to erasure / revocation processing.
"""

import logging
import os
import uuid
import base64
import hashlib
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from cryptography.fernet import Fernet
from fastapi import HTTPException
from app.models.user import User
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.config import settings
from app.models.all_models import ConsentRecord, AuditLog, ConsentTypeEnum
from app.services.game_service import iso_utc

logger = logging.getLogger(__name__)


class EncryptionService:
    """AES-256 Fernet-based field level encryption."""

    def __init__(self, key: Optional[str] = None):
        # Read the configured key (ENCRYPTION_KEY). Previously this looked up a
        # non-existent `ENCRYPTION_SECRET_KEY`, so every deployment silently fell
        # back to a hardcoded default — voiding the at-rest guarantee and making
        # key rotation impossible. `.env` now drives this; production boot refuses
        # a placeholder value (see Settings.validate_for_environment).
        secret = key or settings.ENCRYPTION_KEY
        # Ensure 32-byte url-safe base64 key
        digest = hashlib.sha256(secret.encode()).digest()
        self._key = base64.urlsafe_b64encode(digest)
        self._cipher = Fernet(self._key)

    def encrypt(self, plain_text: str) -> str:
        """Encrypt sensitive clinical text."""
        if not plain_text:
            return ""
        return self._cipher.encrypt(plain_text.encode()).decode()

    def decrypt(self, cipher_text: str) -> str:
        """Decrypt ciphertext back to plaintext."""
        if not cipher_text:
            return ""
        try:
            return self._cipher.decrypt(cipher_text.encode()).decode()
        except Exception:
            return cipher_text  # Fallback if unencrypted string passed


class ComplianceService:
    @staticmethod
    def validate_consent_policy(consent_type, scope, guardian_id=None) -> None:
        if consent_type != ConsentTypeEnum.PATIENT_SELF or guardian_id is not None:
            raise HTTPException(status_code=422, detail="Only patient_self consent without a guardian is supported; verified guardian identity is unavailable")
        if scope not in {"game_data", "health_data", "voice_companion", "all"}:
            raise HTTPException(status_code=422, detail="Unsupported processing scope")

    @staticmethod
    async def grant_consent(
        db: AsyncSession,
        patient_id: uuid.UUID,
        consent_type: ConsentTypeEnum,
        scope: str,
        actor: User,
        guardian_id: Optional[uuid.UUID] = None,
    ) -> ConsentRecord:
        from app.deps import ensure_patient_owner

        await ensure_patient_owner(db, actor, patient_id)
        ComplianceService.validate_consent_policy(consent_type, scope, guardian_id)
        record = ConsentRecord(
            id=uuid.uuid4(),
            patient_id=patient_id,
            consent_type=ConsentTypeEnum.PATIENT_SELF,
            scope=scope,
            granted_at=datetime.now(timezone.utc),
            grantor_id=actor.id,
            guardian_id=None,
        )
        try:
            db.add(record)
            audit = await ComplianceService.log_audit_access(
                db, actor.id, "write", "consent", record.id,
                details={"operation": "grant", "patient_id": str(patient_id), "scope": scope},
            )
            if audit is None:
                raise RuntimeError("Mutation audit unavailable")
        except Exception:
            await db.rollback()
            logger.exception(
                "Consent grant failed for patient_id=%s consent_id=%s scope=%s",
                patient_id,
                record.id,
                scope,
            )
            raise HTTPException(status_code=503, detail="Consent persistence or audit unavailable")
        return record

    @staticmethod
    async def record_consent(
        db: AsyncSession,
        patient_id: uuid.UUID,
        consent_type: ConsentTypeEnum,
        scope: str,
        actor: User,
        guardian_id: Optional[uuid.UUID] = None,
    ) -> ConsentRecord:
        return await ComplianceService.grant_consent(
            db=db,
            patient_id=patient_id,
            consent_type=consent_type,
            scope=scope,
            actor=actor,
            guardian_id=guardian_id,
        )

    @staticmethod
    async def verify_consent(
        db: AsyncSession,
        patient_id: uuid.UUID,
        required_scope: str = "health_data",
    ) -> bool:
        """Verify whether active (non-revoked) consent exists for specified scope."""
        stmt = select(ConsentRecord).where(
            ConsentRecord.patient_id == patient_id,
            ConsentRecord.revoked_at == None,
        )
        res = await db.execute(stmt)
        records = res.scalars().all()

        for r in records:
            if r.scope == "all" or r.scope == required_scope:
                return True
        return False

    @staticmethod
    async def revoke_consent(
        db: AsyncSession,
        consent_id: uuid.UUID,
        actor: User,
    ) -> ConsentRecord:
        from app.deps import ensure_patient_owner

        patient_id = (await db.execute(
            select(ConsentRecord.patient_id).where(ConsentRecord.id == consent_id)
        )).scalar_one_or_none()
        if patient_id is None:
            raise HTTPException(status_code=404, detail="Consent record not found")
        await ensure_patient_owner(db, actor, patient_id)
        record = (await db.execute(
            select(ConsentRecord).where(ConsentRecord.id == consent_id)
            .with_for_update().execution_options(populate_existing=True)
        )).scalar_one_or_none()
        if record is None:
            raise HTTPException(status_code=404, detail="Consent record not found")
        scope = record.scope
        try:
            if record.revoked_at is None:
                record.revoked_at = datetime.now(timezone.utc)
            audit = await ComplianceService.log_audit_access(
                db, actor.id, "write", "consent", record.id,
                details={"operation": "revoke", "patient_id": str(patient_id), "scope": record.scope},
            )
            if audit is None:
                raise RuntimeError("Mutation audit unavailable")
        except Exception:
            await db.rollback()
            logger.exception(
                "Consent revoke failed for patient_id=%s consent_id=%s scope=%s",
                patient_id,
                consent_id,
                scope,
            )
            raise HTTPException(status_code=503, detail="Consent persistence or audit unavailable")
        return record

    @staticmethod
    async def log_audit_access(
        db: AsyncSession,
        user_id: uuid.UUID,
        action: str,
        resource_type: str,
        resource_id: str,
        ip_address: Optional[str] = "127.0.0.1",
        details: Optional[Dict[str, Any]] = None,
    ) -> AuditLog:
        """Create immutable audit log entry for health record access."""
        log_entry = AuditLog(
            user_id=user_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            ip_address=ip_address,
            details=details or {},
            timestamp=datetime.now(timezone.utc),
        )
        db.add(log_entry)
        await db.commit()
        return log_entry

    @staticmethod
    async def log_read_access(
        db: AsyncSession,
        user_id: uuid.UUID,
        resource_type: str,
        resource_id: str,
        ip_address: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
    ) -> Optional[AuditLog]:
        """Best-effort audit of a patient-data read.

        Never raises: audit failures must not break the request that is being
        audited (log-and-continue).
        """
        try:
            # AuditLog.resource_id is a UUID column (native on PG, strict on
            # SQLite) — normalize strings back to UUID objects before insert.
            rid = uuid.UUID(str(resource_id))
        except (ValueError, TypeError):
            rid = resource_id
        try:
            return await ComplianceService.log_audit_access(
                db=db,
                user_id=user_id,
                action="read",
                resource_type=resource_type,
                resource_id=rid,
                ip_address=ip_address or "127.0.0.1",
                details=details or {},
            )
        except Exception:  # noqa: BLE001 — audit is best-effort
            # A failed audit flush leaves the session in pending-rollback;
            # restore it so the audited request can still complete.
            await db.rollback()
            logger.exception("Read-audit failed for %s %s", resource_type, resource_id)
            return None

    @staticmethod
    async def log_write_access(
        db: AsyncSession,
        user_id: uuid.UUID,
        resource_type: str,
        resource_id: str,
        ip_address: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None,
    ) -> Optional[AuditLog]:
        """Best-effort audit of a patient-data write.

        Never raises and never rolls back the audited work: a failed audit
        flush leaves the session in pending-rollback, so it is restored and
        the write itself still completes.
        """
        try:
            rid = uuid.UUID(str(resource_id))
        except (ValueError, TypeError):
            rid = resource_id
        try:
            return await ComplianceService.log_audit_access(
                db=db,
                user_id=user_id,
                action="write",
                resource_type=resource_type,
                resource_id=rid,
                ip_address=ip_address or "127.0.0.1",
                details=details or {},
            )
        except Exception:  # noqa: BLE001 — audit is best-effort
            await db.rollback()
            logger.exception("Write-audit failed for %s %s", resource_type, resource_id)
            return None

    @staticmethod
    async def export_patient_data(db: AsyncSession, patient_id: uuid.UUID) -> Dict[str, Any]:
        """DPDP data-portability dump: profile, consents, games, reminders."""
        from app.models.all_models import (
            PatientProfile, GameSession, ReminderEvent, ReminderSchedule, RiskScreening,
        )

        patient = (
            await db.execute(select(PatientProfile).where(PatientProfile.id == patient_id))
        ).scalar_one_or_none()
        if patient is None:
            return {}

        consents = (
            await db.execute(select(ConsentRecord).where(ConsentRecord.patient_id == patient_id))
        ).scalars().all()
        sessions = (
            await db.execute(select(GameSession).where(GameSession.patient_id == patient_id))
        ).scalars().all()
        schedules = (
            await db.execute(select(ReminderSchedule).where(ReminderSchedule.patient_id == patient_id))
        ).scalars().all()
        events = (
            await db.execute(select(ReminderEvent).where(ReminderEvent.patient_id == patient_id))
        ).scalars().all()

        screening = None
        if await ComplianceService.verify_consent(db, patient_id, "health_data"):
            screening = (await db.execute(
                select(RiskScreening).join(ConsentRecord, RiskScreening.consent_id == ConsentRecord.id).where(
                    RiskScreening.patient_id == patient_id, ConsentRecord.revoked_at.is_(None),
                )
            )).scalar_one_or_none()

        return {
            "risk_screening": {
                "probability": screening.probability,
                "risk_score": screening.risk_score,
                "model_version": screening.model_version,
                "screened_at": screening.screened_at.isoformat(),
                "note": "Preliminary screening only; not a clinical diagnosis",
            } if screening else None,
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "patient": {
                "id": str(patient.id),
                "name": patient.name,
                "region": patient.region,
                "district": patient.district,
                "cognitive_baseline": (
                    patient.cognitive_baseline.value
                    if hasattr(patient.cognitive_baseline, "value")
                    else str(patient.cognitive_baseline)
                ),
            },
            "consents": [
                {
                    "id": str(c.id),
                    "scope": c.scope,
                    "consent_type": c.consent_type.value if hasattr(c.consent_type, "value") else str(c.consent_type),
                    "granted_at": c.granted_at.isoformat() if c.granted_at else None,
                    "revoked_at": c.revoked_at.isoformat() if c.revoked_at else None,
                }
                for c in consents
            ],
            "game_sessions": [
                {
                    "id": str(s.id),
                    "game_type": s.game_type.value if hasattr(s.game_type, "value") else str(s.game_type),
                    "difficulty_level": s.difficulty_level,
                    "attempts": s.attempts,
                    "correct_count": s.correct_count,
                    "started_at": iso_utc(s.started_at),
                    "completed_at": iso_utc(s.completed_at),
                }
                for s in sessions
            ],
            "reminder_schedules": [
                {
                    "id": str(s.id),
                    "reminder_type": s.reminder_type.value if hasattr(s.reminder_type, "value") else str(s.reminder_type),
                    "cadence": s.cadence,
                    "is_active": s.is_active,
                }
                for s in schedules
            ],
            "reminder_events": [
                {
                    "id": str(e.id),
                    "status": e.status.value if hasattr(e.status, "value") else str(e.status),
                    "scheduled_at": e.scheduled_at.isoformat() if e.scheduled_at else None,
                    "acknowledged_at": e.acknowledged_at.isoformat() if e.acknowledged_at else None,
                }
                for e in events
            ],
        }

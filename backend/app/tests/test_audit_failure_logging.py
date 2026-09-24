import logging
import uuid

import pytest
from fastapi import HTTPException
from sqlalchemy import text

from app.models.all_models import ConsentTypeEnum, PatientProfile
from app.models.user import RoleEnum, User
from app.services.compliance_service import ComplianceService


@pytest.mark.asyncio
async def test_write_audit_failure_logs_error_and_restores_session(
    db_session, monkeypatch, caplog
):
    caplog.set_level(logging.ERROR, logger="app.services.compliance_service")

    async def fail_audit(*args, **kwargs):
        raise RuntimeError("audit insert failed")

    monkeypatch.setattr(ComplianceService, "log_audit_access", fail_audit)

    result = await ComplianceService.log_write_access(
        db_session, uuid.uuid4(), "medical_document", uuid.uuid4()
    )

    assert result is None
    records = [
        record
        for record in caplog.records
        if record.levelname == "ERROR"
        and record.name == "app.services.compliance_service"
        and "Write-audit failed" in record.getMessage()
    ]
    assert records
    assert records[-1].exc_info is not None

    result = await db_session.execute(text("SELECT 1"))
    assert result.scalar_one() == 1


@pytest.mark.asyncio
async def test_grant_consent_audit_failure_logs_error(db_session, monkeypatch, caplog):
    caplog.set_level(logging.ERROR, logger="app.services.compliance_service")
    actor = User(
        id=uuid.uuid4(),
        password_hash="unused",
        role=RoleEnum.PATIENT,
        is_active=True,
    )
    patient = PatientProfile(id=uuid.uuid4(), user_id=actor.id, name="Audit Failure")
    patient_id = patient.id
    db_session.add_all([actor, patient])
    await db_session.commit()

    async def fail_audit(*args, **kwargs):
        raise RuntimeError("audit insert failed")

    monkeypatch.setattr(ComplianceService, "log_audit_access", fail_audit)

    with pytest.raises(HTTPException) as error:
        await ComplianceService.grant_consent(
            db=db_session,
            patient_id=patient_id,
            consent_type=ConsentTypeEnum.PATIENT_SELF,
            scope="health_data",
            actor=actor,
        )

    assert error.value.status_code == 503
    records = [
        record
        for record in caplog.records
        if record.levelname == "ERROR"
        and record.name == "app.services.compliance_service"
    ]
    assert records
    assert records[-1].exc_info is not None
    message = records[-1].getMessage()
    assert "grant" in message.lower()
    assert str(patient_id) in message

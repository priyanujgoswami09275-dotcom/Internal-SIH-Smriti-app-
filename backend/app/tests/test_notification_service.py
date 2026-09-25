"""Tests for NotificationProvider — console mock transport + alert fan-out."""
import uuid

import pytest

from app.config import settings
from app.models.all_models import (
    AlertFlag,
    AlertSeverityEnum,
    AlertTriggerTypeEnum,
    CaregiverPatientLink,
    PatientProfile,
    RelationshipTypeEnum,
)
from app.models.user import RoleEnum, User
from app.services.notification_service import (
    ConsoleNotificationProvider,
    get_notification_provider,
    notify_escalation_results,
)


async def _seed_patient_with_caregivers(db, roles=("family_caregiver", "asha_worker")):
    patient_user = User(phone=f"+91{uuid.uuid4().int % 10**10}", password_hash="x",
                        role=RoleEnum.PATIENT)
    db.add(patient_user)
    await db.flush()
    patient = PatientProfile(user_id=patient_user.id, name="Aai", region="assam")
    db.add(patient)
    await db.flush()

    caregivers = []
    for role in roles:
        u = User(phone=f"+91{uuid.uuid4().int % 10**10}", password_hash="x",
                 role=RoleEnum(role))
        db.add(u)
        await db.flush()
        db.add(CaregiverPatientLink(
            caregiver_id=u.id, patient_id=patient.id,
            relationship_type=RelationshipTypeEnum.FAMILY if role == "family_caregiver"
            else RelationshipTypeEnum.ASHA,
            is_active=True,
        ))
        caregivers.append(u)
    await db.flush()
    return patient, caregivers


@pytest.mark.asyncio
async def test_console_provider_records_deliveries():
    provider = ConsoleNotificationProvider()
    await provider.send_reminder_reprompt(patient_id=uuid.uuid4(),
                                          event_id=uuid.uuid4(), reminder_type="medicine")
    await provider.send_alert(patient_id=uuid.uuid4(), alert_id=uuid.uuid4(),
                              severity="critical", trigger="missed_reminders",
                              summary="missed 3 medicine reminders",
                              recipients=[{"user_id": "1", "role": "family_caregiver"}])
    assert len(provider.deliveries) == 2
    assert provider.deliveries[0]["kind"] == "reprompt"
    assert provider.deliveries[1]["kind"] == "alert"


@pytest.mark.asyncio
async def test_fan_out_sends_alert_to_linked_family_and_asha(db_session):
    patient, caregivers = await _seed_patient_with_caregivers(db_session)
    alert = AlertFlag(patient_id=patient.id,
                      trigger_type=AlertTriggerTypeEnum.MISSED_REMINDERS,
                      severity=AlertSeverityEnum.CRITICAL,
                      alert_summary="Patient missed 3 medicine reminders in 7 days.")
    db_session.add(alert)
    await db_session.flush()

    provider = ConsoleNotificationProvider()
    result = {"alerts": [alert]}
    delivery = await notify_escalation_results(db_session, patient.id, result,
                                               provider=provider)
    assert delivery["recipients_resolved"] == 2
    assert delivery["confirmed_deliveries"] == 0
    assert delivery["delivery_state"] == "not_configured"
    assert len(provider.deliveries) == 1
    assert provider.deliveries[0]["kind"] == "alert"
    assert set(provider.deliveries[0]["recipients"]) == {"family_caregiver", "asha_worker"}
    assert alert.id in {provider.deliveries[0]["alert_id"]}


@pytest.mark.asyncio
async def test_fan_out_skips_when_no_links(db_session):
    patient_user = User(phone=f"+91{uuid.uuid4().int % 10**10}", password_hash="x",
                        role=RoleEnum.PATIENT)
    db_session.add(patient_user)
    await db_session.flush()
    patient = PatientProfile(user_id=patient_user.id, name="NoLinks", region="assam")
    db_session.add(patient)
    await db_session.flush()

    alert = AlertFlag(patient_id=patient.id,
                      trigger_type=AlertTriggerTypeEnum.ACTIVITY_DROP,
                      severity=AlertSeverityEnum.WARNING, alert_summary="activity drop")
    db_session.add(alert)
    await db_session.flush()

    provider = ConsoleNotificationProvider()
    delivery = await notify_escalation_results(db_session, patient.id, {"alerts": [alert]},
                                               provider=provider)
    assert delivery["delivery_state"] == "no_recipients"
    assert delivery["recipients_resolved"] == 0
    assert delivery["confirmed_deliveries"] == 0
    assert provider.deliveries == []


@pytest.mark.asyncio
async def test_fan_out_noop_when_no_alerts(db_session):
    patient, _ = await _seed_patient_with_caregivers(db_session)
    provider = ConsoleNotificationProvider()
    delivery = await notify_escalation_results(
        db_session, patient.id, {"alerts": []}, provider=provider
    )
    assert delivery["delivery_state"] == "not_applicable"
    assert delivery["recipients_resolved"] == 0
    assert delivery["confirmed_deliveries"] == 0
    assert provider.deliveries == []


def test_default_provider_is_console():
    assert isinstance(get_notification_provider(), ConsoleNotificationProvider)


def test_unknown_provider_falls_back_to_console(monkeypatch):
    monkeypatch.setattr(settings, "NOTIFICATION_PROVIDER", "sms")
    assert isinstance(get_notification_provider(), ConsoleNotificationProvider)


@pytest.mark.asyncio
async def test_delivery_audit_failure_is_logged_not_swallowed(caplog):
    """An audit insert failure must be recorded at ERROR level.

    The notification still must not raise, but losing the audit row silently
    is a compliance gap, so the exception is logged with a traceback.
    """
    import logging

    from app.services.notification_service import FCMNotificationProvider

    class _BrokenSession:
        async def execute(self, *args, **kwargs):
            raise RuntimeError("audit table unavailable")

    provider = FCMNotificationProvider(db=_BrokenSession())
    caplog.set_level(logging.ERROR, logger="app.services.notification_service")

    await provider._audit(
        provider="fcm", kind="alert", event_id=uuid.uuid4(),
        recipient=uuid.uuid4(), address="token", status="FAILED",
    )

    errors = [r for r in caplog.records if r.levelname == "ERROR"]
    assert errors, "delivery-audit failure must be logged at error level"
    assert any("audit failed" in r.getMessage() for r in errors)
    assert any(r.exc_info for r in errors), "log should carry the traceback"

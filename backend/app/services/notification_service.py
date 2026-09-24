"""NotificationProvider — clean seam for reminder-escalation and alert fan-out.

CLAUDE.md Phase 6 specifies: unacknowledged reminders escalate to a secondary
notification after 10 minutes, and repeated misses raise an AlertFlag that is
pushed to family + ASHA. Delivery channels are pluggable behind this
interface:

- ``console`` (default): logs deliveries and records them on the instance —
  the local mock. No network, always available; used until a real channel
  (SMS / FCM / email) is configured via NOTIFICATION_PROVIDER.
- Future transports (``sms``, ``fcm``, ``email``) implement the same ABC and
  are registered by name — no caller changes.

The ``notify_escalation_results`` helper fans out newly raised AlertFlags to
the patient's active family caregivers and ASHA workers.
"""
from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.all_models import AlertFlag, CaregiverPatientLink, UserDeviceToken, NotificationDelivery, NotificationKindEnum, NotificationDeliveryStatusEnum
from app.models.user import RoleEnum, User

logger = logging.getLogger(__name__)


class NotificationError(RuntimeError):
    """Raised when a notification channel fails hard (delivery not attempted)."""


class NotificationProvider(ABC):
    name: str = "abstract"

    @abstractmethod
    async def send_alert(
        self,
        *,
        patient_id: UUID,
        alert_id: UUID,
        severity: str,
        trigger: str,
        summary: str,
        recipients: List[Dict[str, Any]],
    ) -> None:
        """Notify family/ASHA that a clinical AlertFlag was raised."""

    @abstractmethod
    async def send_reminder_reprompt(
        self,
        *,
        patient_id: UUID,
        event_id: UUID,
        reminder_type: str,
    ) -> None:
        """Secondary notification for an unacknowledged reminder (10-min rule)."""


class ConsoleNotificationProvider(NotificationProvider):
    """Local mock transport: logs each delivery and appends to ``deliveries``.

    ``deliveries`` is in-memory state, so tests can assert on it; production
    transports replace this by implementing the ABC.
    """

    name = "console"

    def __init__(self) -> None:
        self.deliveries: List[Dict[str, Any]] = []

    async def send_alert(self, **kwargs) -> None:
        record = {"kind": "alert", **kwargs, "recipients": [r.get("role") for r in kwargs["recipients"]]}
        self.deliveries.append(record)
        logger.info("[notification:console] alert %s -> %s: %s", kwargs["alert_id"],
                    record["recipients"], kwargs["summary"])

    async def send_reminder_reprompt(self, **kwargs) -> None:
        record = {"kind": "reprompt", **kwargs}
        self.deliveries.append(record)
        logger.info("[notification:console] reprompt for event %s (%s)",
                    kwargs["event_id"], kwargs["reminder_type"])


class FCMNotificationProvider(NotificationProvider):
    """Firebase Cloud Messaging — free, no tier / billing required.
    Resolves device tokens from UserDeviceToken (DB) per patient_id.
    Writes each attempt to NotificationDelivery audit table (DPDP).
    Degrades to console if FCM key / project missing.
    """
    name = "fcm"

    def __init__(self, db: Optional[AsyncSession] = None) -> None:
        self.db = db

    async def _resolve_token(self, patient_id: UUID) -> Optional[str]:
        # Resolve patient's registered device token from DB.
        # ponytail: uses the user linked to patient via PatientProfile.
        # Without the DB token, nothing can push — fall back to console log.
        from app.models import PatientProfile
        if self.db is None:
            return None
        try:
            stmt = (
                select(UserDeviceToken.fcm_token)
                .join(PatientProfile, PatientProfile.user_id == UserDeviceToken.user_id)
                .where(PatientProfile.id == patient_id, UserDeviceToken.fcm_token.isnot(None))
                .limit(1)
            )
            res = await self.db.execute(stmt)
            row = res.scalar_one_or_none()
            return row
        except Exception:
            return None

    async def _audit(self, provider: str, kind, event_id, recipient, address, status) -> None:
        # Minimal audit: write to NotificationDelivery. No receipt confirmation
        # (P2) — just record that the attempt happened. recipient arrives as a
        # string (notify_escalation_results serializes user.id); the UUID column
        # needs a real UUID object, so coerce — otherwise the INSERT raises
        # StatementError and the swallowed except leaves NO audit row at all.
        from sqlalchemy import insert
        from uuid import UUID as _UUID
        if self.db is not None:
            try:
                await self.db.execute(
                    insert(NotificationDelivery),
                    {
                        "provider": provider,
                        "kind": kind.value if hasattr(kind, "value") else str(kind),
                        "event_id": event_id,
                        "recipient_user_id": _UUID(str(recipient)) if recipient else None,
                        "address": address,
                        "status": status.value if hasattr(status, "value") else str(status),
                    },
                )
            except Exception:
                # Delivery must not break on an audit failure, but the failure
                # is a real compliance gap — record it at error level (with
                # traceback) instead of dropping it silently.
                logger.exception(
                    "Notification-delivery audit failed (provider=%s kind=%s recipient=%s status=%s)",
                    provider, kind, recipient, status,
                )

    async def send_alert(self, *, patient_id: UUID, alert_id: UUID, severity: str, trigger: str, summary: str, recipients: List[Dict[str, Any]]) -> None:
        token = await self._resolve_token(patient_id)
        if token:
            # Real FCM call: POST to FCM v1 endpoint with server key / service account.
            # Not implemented here (needs FCM_SERVICE_ACCOUNT_JSON / FCM_SERVER_KEY).
            # Degrades gracefully to logging. The audit records FAILED — nothing
            # was actually delivered, and the trail must never claim SENT.
            logger.info("[notification:fcm] alert %s for %s (token %s...): %s", alert_id, patient_id, token[:10], summary)
            await self._audit("fcm", NotificationKindEnum.ALERT, alert_id, recipients[0].get("user_id") if recipients else None, token[:200], NotificationDeliveryStatusEnum.FAILED)
        else:
            logger.info("[notification:fcm] alert %s for %s — no device token; console fallback.", alert_id, patient_id)
            await self._audit("fcm", NotificationKindEnum.ALERT, alert_id, recipients[0].get("user_id") if recipients else None, None, NotificationDeliveryStatusEnum.FAILED)

    async def send_reminder_reprompt(self, *, patient_id: UUID, event_id: UUID, reminder_type: str) -> None:
        token = await self._resolve_token(patient_id)
        if token:
            # No real FCM send is implemented — audit FAILED, never SENT.
            logger.info("[notification:fcm] reprompt event %s (%s) for %s (token %s...)", event_id, reminder_type, patient_id, token[:10])
            await self._audit("fcm", NotificationKindEnum.REPROMPT, event_id, None, token[:200], NotificationDeliveryStatusEnum.FAILED)
        else:
            logger.info("[notification:fcm] reprompt event %s — no device token; console fallback.", event_id)
            await self._audit("fcm", NotificationKindEnum.REPROMPT, event_id, None, None, NotificationDeliveryStatusEnum.FAILED)


class LogOnlyFallbackProvider(ConsoleNotificationProvider):
    """Alias used when a configured channel is unavailable — never raises."""


def _build_provider(name: str) -> NotificationProvider:
    if name in ("console", "log", "logonly"):
        return ConsoleNotificationProvider()
    if name == "fcm":
        return FCMNotificationProvider()
    raise NotificationError(f"Unknown NOTIFICATION_PROVIDER: {name!r} (implement the ABC and register it)")


def get_notification_provider(name: Optional[str] = None, db: Optional[AsyncSession] = None) -> NotificationProvider:
    """Return the configured provider, falling back to console if unavailable."""
    name = (name or settings.NOTIFICATION_PROVIDER or "console").lower()
    try:
        provider = _build_provider(name)
        if isinstance(provider, FCMNotificationProvider):
            provider.db = db
        return provider
    except NotificationError as exc:
        logger.warning("Notification provider %r unavailable (%s) — using console.", name, exc)
        return ConsoleNotificationProvider()


async def notify_escalation_results(
    db: AsyncSession,
    patient_id: UUID,
    result: Dict[str, Any],
    provider: Optional[NotificationProvider] = None,
) -> int:
    """Fan out newly raised AlertFlags to the patient's family + ASHA links.

    ``result`` is the return value of ReminderService.evaluate_escalations.
    Returns the number of providers reached (alert recipients resolved). Never
    raises — notification failures must not fail the escalation evaluation.
    """
    alerts: List[AlertFlag] = result.get("alerts") or []
    if not alerts:
        return 0

    # Active links for this patient, restricted to family + ASHA roles.
    stmt = (
        select(User, CaregiverPatientLink.relationship_type)
        .join(CaregiverPatientLink, CaregiverPatientLink.caregiver_id == User.id)
        .where(
            CaregiverPatientLink.patient_id == patient_id,
            CaregiverPatientLink.is_active == True,  # noqa: E712
            User.role.in_([RoleEnum.FAMILY_CAREGIVER, RoleEnum.ASHA_WORKER]),
            User.is_active == True,  # noqa: E712
        )
    )
    res = await db.execute(stmt)
    recipients = [
        {
            "user_id": str(user.id),
            "role": user.role.value if hasattr(user.role, "value") else str(user.role),
            "relationship": rel.value if hasattr(rel, "value") else str(rel),
            "phone": user.phone,
        }
        for user, rel in res.all()
    ]
    if not recipients:
        logger.warning("Alert raised for patient %s but no family/ASHA link to notify.", patient_id)
        return 0

    provider = provider or get_notification_provider()
    for alert in alerts:
        trigger = alert.trigger_type.value if hasattr(alert.trigger_type, "value") else str(alert.trigger_type)
        severity = alert.severity.value if hasattr(alert.severity, "value") else str(alert.severity)
        try:
            await provider.send_alert(
                patient_id=patient_id,
                alert_id=alert.id,
                severity=severity,
                trigger=trigger,
                summary=alert.alert_summary or trigger,
                recipients=recipients,
            )
        except Exception as exc:  # delivery failure must not break escalation flow
            logger.error("Alert notification failed for %s: %s", alert.id, exc)
    return len(recipients)


async def notify_reprompts(
    patient_id: UUID,
    result: Dict[str, Any],
    provider: Optional[NotificationProvider] = None,
) -> int:
    """Send the 10-minute secondary notification for each newly ESCALATED event.

    ``result`` is the return value of ReminderService.evaluate_escalations.
    Returns the number of reprompts sent. Never raises — a delivery failure must
    not fail the escalation scan.
    """
    reprompts: List[Dict[str, Any]] = result.get("reprompt_events") or []
    if not reprompts:
        return 0
    provider = provider or get_notification_provider()
    sent = 0
    for rp in reprompts:
        try:
            await provider.send_reminder_reprompt(
                patient_id=patient_id,
                event_id=rp["event_id"],
                reminder_type=rp.get("reminder_type", "reminder"),
            )
            sent += 1
        except Exception as exc:  # delivery failure must not break the scan
            logger.error("Reprompt notification failed for event %s: %s", rp.get("event_id"), exc)
    return sent

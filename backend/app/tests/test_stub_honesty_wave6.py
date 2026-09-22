"""Wave 6 stub honesty — no path reports success it didn't perform.

- FCM provider with a device token audits FAILED (no real FCM send is
  implemented) — the delivery trail must never claim SENT.
- cosine_similarity is true cosine (scale-independent; equals the raw dot
  product on the unit vectors the providers emit).
- Sarvam TTS validates against the Bulbul-covered subset — Assamese (NMT/ASR
  only) fails fast with UnsupportedLanguageError, no network call.
- /language/asr and /language/tts responses carry the honest provider name.
"""
import uuid
from unittest.mock import patch

import pytest
from sqlalchemy import select

from app.models.all_models import NotificationDelivery, NotificationKindEnum
from app.services.language_service import SarvamLanguageService, UnsupportedLanguageError
from app.services.notification_service import FCMNotificationProvider, NotificationDeliveryStatusEnum
from app.services.rag_service import RAGService


@pytest.mark.asyncio
async def test_fcm_token_present_audits_failed_not_sent(db_session):
    """With a resolved token, the audit row says FAILED — no real send exists."""
    provider = FCMNotificationProvider(db=db_session)
    with patch.object(FCMNotificationProvider, "_resolve_token", return_value="tok-123"):
        await provider.send_alert(
            patient_id=uuid.uuid4(), alert_id=uuid.uuid4(),
            severity="warning", trigger="missed_reminders", summary="Test",
            recipients=[{"user_id": str(uuid.uuid4())}],
        )
    rows = (await db_session.execute(
        select(NotificationDelivery).where(
            NotificationDelivery.kind == NotificationKindEnum.ALERT)
    )).scalars().all()
    assert len(rows) == 1
    assert rows[0].status == NotificationDeliveryStatusEnum.FAILED

    with patch.object(FCMNotificationProvider, "_resolve_token", return_value="tok-123"):
        await provider.send_reminder_reprompt(
            patient_id=uuid.uuid4(), event_id=uuid.uuid4(), reminder_type="medicine")
    rows = (await db_session.execute(
        select(NotificationDelivery).where(
            NotificationDelivery.kind == NotificationKindEnum.REPROMPT)
    )).scalars().all()
    assert len(rows) == 1
    assert rows[0].status == NotificationDeliveryStatusEnum.FAILED


def test_cosine_similarity_is_true_cosine():
    # Non-unit vectors: scale-independent (true cosine), not the raw dot product.
    a = [3.0, 4.0]
    b = [6.0, 8.0]  # same direction, double magnitude
    assert RAGService.cosine_similarity(a, b) == pytest.approx(1.0, abs=1e-9)
    assert RAGService.cosine_similarity(a, b) != pytest.approx(50.0)  # raw dot would be 50
    # Anti-correlated vectors score negative (dropped by a 0.0 threshold).
    assert RAGService.cosine_similarity([1.0, 0.0], [-1.0, 0.0]) == pytest.approx(-1.0, abs=1e-9)
    # Degenerate inputs stay 0.0.
    assert RAGService.cosine_similarity([], [1.0]) == 0.0
    assert RAGService.cosine_similarity([0.0, 0.0], [1.0, 0.0]) == 0.0
    assert RAGService.cosine_similarity([1.0, 2.0], [1.0]) == 0.0


def test_sarvam_tts_gated_bulbul_subset():
    service = SarvamLanguageService(api_key="sk-test-key-123")
    with pytest.raises(UnsupportedLanguageError) as exc:
        import asyncio
        asyncio.run(service.text_to_speech("hello", "assamese"))
    assert "not yet available" in str(exc.value)
    # Hindi is Bulbul-covered: validation passes (the request would then hit
    # the network — not exercised here; only the gate is).
    code = service._tts_lang_code("hindi")
    assert code == "hi-IN"

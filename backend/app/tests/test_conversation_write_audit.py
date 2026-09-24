import uuid

import pytest
from sqlalchemy import select

from app.deps import get_current_user
from app.main import app
from app.models.all_models import AuditActionEnum, AuditLog
from app.models.user import User
from app.routes import voice_companion as voice_companion_route
from app.services.conversation_store import ConversationStore


@pytest.mark.parametrize(
    ("endpoint", "request_body", "service_method", "result", "stored_user_message"),
    [
        pytest.param(
            "text",
            {"message": "private text message", "language": "english"},
            "chat",
            {"reply_text": "private text reply", "fallback": False},
            "private text message",
            id="text",
        ),
        pytest.param(
            "voice",
            {
                "audio_base64": "cHJpdmF0ZSBhdWRpbw==",
                "language": "english",
            },
            "voice_chat_pipeline",
            {
                "recognized_query": "private recognized query",
                "reply_text": "private voice reply",
                "fallback": False,
            },
            "private recognized query",
            id="voice",
        ),
    ],
)
@pytest.mark.asyncio
async def test_successful_chat_writes_conversation_audit(
    endpoint,
    request_body,
    service_method,
    result,
    stored_user_message,
    client,
    db_session,
    monkeypatch,
):
    from app.tests.conftest import create_consented_patient

    profile = await create_consented_patient(client, "Conversation Audit Patient")
    patient_id = uuid.UUID(profile["id"])
    user_id = uuid.UUID(profile["user_id"])
    actor = await db_session.get(User, user_id)
    app.dependency_overrides[get_current_user] = lambda: actor

    async def successful_chat(self, **kwargs):
        return result

    store = ConversationStore()

    async def get_store():
        return store

    monkeypatch.setattr(
        voice_companion_route.VoiceCompanionService,
        service_method,
        successful_chat,
    )
    monkeypatch.setattr(
        voice_companion_route,
        "get_conversation_store",
        get_store,
    )

    response = await client.post(
        f"/api/v1/companion/chat/{endpoint}",
        json={"patient_id": str(patient_id), **request_body},
    )

    assert response.status_code == 200, response.text
    assert await store.get(patient_id) == [
        {"role": "user", "content": stored_user_message},
        {"role": "assistant", "content": result["reply_text"]},
    ]
    audits = (
        await db_session.execute(
            select(AuditLog).where(
                AuditLog.user_id == user_id,
                AuditLog.resource_id == patient_id,
            )
        )
    ).scalars().all()
    assert len(audits) == 1
    assert audits[0].resource_type == "conversation"
    assert audits[0].action == AuditActionEnum.WRITE
    assert audits[0].details == {"channel": endpoint}
    assert not any(audit.action == AuditActionEnum.READ for audit in audits)

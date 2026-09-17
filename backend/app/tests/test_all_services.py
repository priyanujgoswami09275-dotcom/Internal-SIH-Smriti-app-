"""End-to-End Suite for SIH 26 Elder-Care Cognitive Platform."""

import pytest
import uuid
from datetime import datetime, timedelta, timezone

from app.models.all_models import (
    User, PatientProfile, GameSession, ReminderSchedule,
    ReminderEvent, AlertFlag, ConsentRecord,
    RoleEnum, CognitiveBaselineEnum, GameTypeEnum,
    ReminderTypeEnum, ReminderStatusEnum, ConsentTypeEnum
)
from app.services.game_engine_service import GameEngineService
from app.services.reminder_service import ReminderService
from app.services.dashboard_service import DashboardService
from app.services.language_service import MockLanguageService
from app.services.voice_companion_service import VoiceCompanionService
from app.services.rag_service import RAGService
from app.services.report_service import ReportService
from app.services.compliance_service import EncryptionService, ComplianceService
from app.utils.auth_utils import hash_password, verify_password, create_access_token, decode_access_token


@pytest.mark.asyncio
async def test_auth_and_tokens():
    """Verify password hashing and JWT encoding/decoding."""
    raw_pw = "SuperSecurePassword123"
    hashed = hash_password(raw_pw)
    assert verify_password(raw_pw, hashed) is True
    assert verify_password("wrong_password", hashed) is False

    user_id = str(uuid.uuid4())
    token = create_access_token(user_id=user_id, role="asha_worker")
    payload = decode_access_token(token)
    assert payload["sub"] == user_id
    assert payload["role"] == "asha_worker"


@pytest.mark.asyncio
async def test_game_engine_and_adaptive_difficulty(db_session):
    """Test game session logging and rule-based difficulty adjustment."""
    patient_id = uuid.uuid4()
    patient = PatientProfile(
        id=patient_id,
        name="Biren Sharma",
        cognitive_baseline=CognitiveBaselineEnum.MCI,
        region="Assam",
        district="Kamrup",
    )
    db_session.add(patient)
    await db_session.commit()

    # Log 3 consecutive high accuracy game sessions (>85% accuracy, <4000ms speed)
    for _ in range(3):
        await GameEngineService.log_game_session(
            db=db_session,
            patient_id=patient_id,
            game_type=GameTypeEnum.MATCH_IT,
            difficulty_level=1,
            attempts=10,
            correct_count=9,
            incorrect_count=1,
            avg_response_time_ms=3200.0,
        )

    # Evaluate adaptive difficulty upgrade
    next_diff, reason = await GameEngineService.compute_next_difficulty(
        db=db_session,
        patient_id=patient_id,
        game_type=GameTypeEnum.MATCH_IT,
        current_difficulty=1,
    )
    assert next_diff == 2
    assert "Advancing" in reason


@pytest.mark.asyncio
async def test_reminder_escalation_rules(db_session):
    """Test reminder acknowledgment and multi-day alert escalation."""
    patient_id = uuid.uuid4()
    creator_id = uuid.uuid4()

    schedule = await ReminderService.create_schedule(
        db=db_session,
        patient_id=patient_id,
        reminder_type=ReminderTypeEnum.MEDICINE,
        cadence="08:00 AM Daily",
        created_by=creator_id,
    )
    assert schedule.id is not None

    # Simulate 3 missed events in past 7 days
    now = datetime.now(timezone.utc)
    for i in range(3):
        event = ReminderEvent(
            schedule_id=schedule.id,
            patient_id=patient_id,
            scheduled_at=now - timedelta(days=i + 1),
            status=ReminderStatusEnum.MISSED,
        )
        db_session.add(event)
    await db_session.commit()

    # Evaluate escalations
    escalation_report = await ReminderService.evaluate_escalations(db_session, patient_id)
    assert escalation_report["raised_alerts"] >= 1
    assert "medicine" in escalation_report["summary"].lower()


@pytest.mark.asyncio
async def test_dashboard_analytics_summary(db_session):
    """Test aggregation of cognitive metrics, compliance, and clinical flags."""
    patient_id = uuid.uuid4()
    patient = PatientProfile(
        id=patient_id,
        name="Lakshmi Borah",
        cognitive_baseline=CognitiveBaselineEnum.HEALTHY,
        region="Assam",
        district="Jorhat",
    )
    db_session.add(patient)
    await db_session.commit()

    summary = await DashboardService.get_patient_summary(db_session, patient_id)
    assert summary["patient_id"] == str(patient_id)
    assert "accuracy_pct" in summary
    assert "compliance_pct" in summary
    assert "clinical_flags" in summary


@pytest.mark.asyncio
async def test_bhashini_and_voice_companion():
    """Test Speech Service Provider and Voice Companion Chat."""
    lang_service = MockLanguageService()

    # ASR
    recognized = await lang_service.speech_to_text("dummy_audio", "assamese")
    assert len(recognized) > 0

    # TTS
    tts = await lang_service.text_to_speech("নমস্কাৰ", "assamese")
    assert len(tts) > 0

    # Claude Voice Companion
    companion = VoiceCompanionService(lang_service=lang_service)
    chat_result = await companion.chat(
        user_message="I forgot where my reading glasses are.",
        patient_name="Biren",
        patient_language="assamese",
    )
    assert "reply_text" in chat_result


@pytest.mark.asyncio
async def test_rag_and_weekly_reports(db_session):
    """Test Medical Document RAG chunking and Clinical Report generation."""
    patient_id = uuid.uuid4()
    doc = await RAGService.ingest_document(
        db=db_session,
        patient_id=patient_id,
        uploaded_by=uuid.uuid4(),
        file_ref="reports/prescription_2026.pdf",
        doc_type="prescription",
        extracted_text="Patient prescribed Donepezil 5mg once daily at bedtime for mild cognitive impairment.",
    )
    assert doc.id is not None

    matches = await RAGService.query_medical_context(
        db=db_session,
        patient_id=patient_id,
        query="Donepezil dosage",
        top_k=1,
    )
    assert len(matches) == 1
    assert "Donepezil" in matches[0]["text"]

    # Generate Weekly Clinical Report
    report = await ReportService.generate_weekly_clinical_summary(db_session, patient_id)
    assert report["patient_id"] == str(patient_id)
    assert "cognitive_metrics" in report
    assert "clinical_recommendations" in report


@pytest.mark.asyncio
async def test_dpdp_compliance_and_encryption(db_session):
    """Test AES-256 field encryption and DPDP consent validation."""
    # Field Encryption
    enc_service = EncryptionService()
    sensitive_data = "Patient experiences mild wandering at 5 PM."
    encrypted = enc_service.encrypt(sensitive_data)
    assert encrypted != sensitive_data
    decrypted = enc_service.decrypt(encrypted)
    assert decrypted == sensitive_data

    # Consent lifecycle
    patient_id = uuid.uuid4()
    owner = User(id=uuid.uuid4(), password_hash="unused", role=RoleEnum.PATIENT, is_active=True)
    db_session.add(owner)
    await db_session.flush()
    db_session.add(PatientProfile(id=patient_id, user_id=owner.id, name="Consent owner"))
    await db_session.commit()
    consent = await ComplianceService.record_consent(
        db=db_session,
        patient_id=patient_id,
        actor=owner,
        consent_type=ConsentTypeEnum.PATIENT_SELF,
        scope="health_data",
    )
    assert consent.id is not None

    has_consent = await ComplianceService.verify_consent(db_session, patient_id, "health_data")
    assert has_consent is True

    # Revoke consent
    revoked = await ComplianceService.revoke_consent(db_session, consent.id, actor=owner)
    assert revoked.revoked_at is not None

    has_consent_after = await ComplianceService.verify_consent(db_session, patient_id, "health_data")
    assert has_consent_after is False

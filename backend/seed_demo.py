"""Seed a SYNTHETIC demo dataset for local development and demos.

This script SEEDS data; it is not a startup guide. For the September 30 demo
runbook (Homebrew PostgreSQL localhost:5432/eldercare, system id
7681754862742343790, existing 13 patients / 10 documents), see the "Run —
September 30 demo" section of DEPLOYMENT.md. Do NOT reseed or reset the demo
database for the demo — this script is not part of that runbook.

All clinical-looking content below is fabricated placeholder data — clearly
labeled "[SYNTHETIC DEMO]" — so the RAG pipeline, reminder escalation, and
dashboard can be exercised without real patient data. Do not put real patient
records through this script.

Usage (backend running against the DB you want seeded):
    cd backend
    DATABASE_URL=postgresql+psycopg://postgres@localhost:5433/eldercare \
        .venv/bin/python seed_demo.py

Idempotent: existing rows keyed by phone are reused, not duplicated.
Prints demo credentials at the end.
"""
import asyncio
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from app.database import async_session_maker
from app.models.all_models import (
    CaregiverPatientLink,
    ConsentRecord,
    ConsentTypeEnum,
    MedicalDocument,
    PatientProfile,
    RelationshipTypeEnum,
    ReminderEvent,
    ReminderSchedule,
    ReminderStatusEnum,
    ReminderTypeEnum,
)
from app.models.user import RoleEnum, User
from app.services.auth_service import AuthService
from app.services.rag_service import RAGService

SYN = "[SYNTHETIC DEMO]"
PHONES = {
    "patient": "919876543001",
    "caregiver": "919876543002",
    "clinician": "919876543003",
}
PASSWORD = "DemoPass123"

ROUTINE_STEPS = [
    {"step_id": "wake", "order": 1, "time": "06:30",
     "title_en": "Wake up and stretch", "title_as": "শুই উঠি হাত ভৰি মেলা",
     "title_bn": "ঘুম থেকে উঠে শরীর চর্চা", "title_hi": "उठकर हल्का व्यायाम", "icon": "wb_sunny"},
    {"step_id": "tea", "order": 2, "time": "07:00",
     "title_en": "Morning tea with family", "title_as": "পৰিয়ালৰ সৈতে পুৱাৰ চাহ",
     "title_bn": "পরিবারের সাথে সকালের চা", "title_hi": "परिवार के साथ चाय", "icon": "local_cafe"},
    {"step_id": "meds", "order": 3, "time": "08:00",
     "title_en": "Morning medicines", "title_as": "পুৱাৰ ঔষধ",
     "title_bn": "সকালের ওষুধ", "title_hi": "सुबह की दवाई", "icon": "medication"},
    {"step_id": "walk", "order": 4, "time": "16:30",
     "title_en": "Evening walk", "title_as": "গধূলি খোজ কাঢ়া",
     "title_bn": "সন্ধ্যার হাঁটা", "title_hi": "शाम की सैर", "icon": "directions_walk"},
]

# --- Synthetic clinical documents (fabricated, clearly labeled) -------------
DOC_1 = {
    "file_ref": "synth-rx-0001.pdf",
    "doc_type": "prescription",
    "title": f"{SYN} Cardiology prescription",
    "text": (
        "SYNTHETIC DEMO RECORD — not a real patient. Diagnosis: controlled "
        "hypertension with mild cognitive impairment follow-up. Take one tablet "
        "of Amlodipine 5 mg every morning after food. Take Metformin 500 mg "
        "twice daily with meals. Vitamin D3 60K once weekly. If dizziness or "
        "swelling occurs, stop and contact the clinic. Target blood pressure "
        "below 140/90. Next review in three months with a cognition assessment."
    ),
}
DOC_2 = {
    "file_ref": "synth-note-0002.pdf",
    "doc_type": "report",
    "title": f"{SYN} Cognition assessment (bilingual sample)",
    "text": (
        "SYNTHETIC DEMO NOTE. Montreal Cognitive Assessment score 23/30 — mild "
        "impairment domain in delayed recall. Memory strategies advised: keep a "
        "visible routine, use a pillbox, involve family for medication "
        "supervision. পুনৰীক্ষণ তিনি মাহৰ পাছত। বাংলা নির্দেশিকা: প্রতিদিন "
        "একই সময়ে ওষুধ খান। Hindi guidance: रोज़ एक ही समय पर दवा लें। "
        "Family should watch for missed doses and mood changes and report to "
        "the ASHA worker during home visits."
    ),
}


async def _get_or_create_user(phone: str, role: str, name_hint: str) -> User:
    async with async_session_maker() as db:
        res = await db.execute(select(User).where(User.phone == phone))
        user = res.scalar_one_or_none()
        if user:
            return user
        user = User(
            phone=phone,
            email=f"{name_hint}.demo@example.in",
            password_hash=AuthService.hash_password(PASSWORD),
            role=RoleEnum(role),
            preferred_language="assamese",
            is_active=True,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
        return user


async def main() -> None:
    now = datetime.now(timezone.utc)
    async with async_session_maker() as db:
        patient_user = await _get_or_create_user(PHONES["patient"], "patient", "ranjana")
        caregiver_user = await _get_or_create_user(PHONES["caregiver"], "family_caregiver", "priyam")
        clinician_user = await _get_or_create_user(PHONES["clinician"], "clinician", "dr.bora")

        # Patient profile (bound to the patient account) with a bilingual routine.
        res = await db.execute(
            select(PatientProfile).where(PatientProfile.user_id == patient_user.id)
        )
        patient = res.scalar_one_or_none()
        if patient is None:
            patient = PatientProfile(
                user_id=patient_user.id,
                name="Ranjana Devi",
                dob=datetime(1948, 3, 15).date(),
                cognitive_baseline="MCI",
                region="assam",
                district="kamrup",
                routine={"steps": ROUTINE_STEPS},
            )
            db.add(patient)
            await db.commit()
            await db.refresh(patient)
        pid = patient.id

        # DPDP consent (self).
        res = await db.execute(
            select(ConsentRecord).where(
                ConsentRecord.patient_id == pid, ConsentRecord.revoked_at.is_(None)
            )
        )
        if res.scalar_one_or_none() is None:
            db.add(ConsentRecord(
                patient_id=pid, consent_type=ConsentTypeEnum.PATIENT_SELF,
                scope="all", granted_at=now,
            ))

        # Family caregiver link.
        res = await db.execute(
            select(CaregiverPatientLink).where(
                CaregiverPatientLink.patient_id == pid,
                CaregiverPatientLink.caregiver_id == caregiver_user.id,
            )
        )
        if res.scalar_one_or_none() is None:
            db.add(CaregiverPatientLink(
                caregiver_id=caregiver_user.id, patient_id=pid,
                relationship_type=RelationshipTypeEnum.FAMILY, is_active=True,
            ))

        # Reminder schedule + history: 2 acknowledged, 1 pending >10 min (for
        # the escalation demo), plus an old one to trigger a missed-3 AlertFlag
        # only if the clinician demo asks for it.
        res = await db.execute(
            select(ReminderSchedule).where(
                ReminderSchedule.patient_id == pid, ReminderSchedule.is_active == True  # noqa: E712
            )
        )
        sched = res.scalar_one_or_none()
        if sched is None:
            sched = ReminderSchedule(
                patient_id=pid, reminder_type=ReminderTypeEnum.MEDICINE,
                cadence="08:00,14:00,20:00", created_by=clinician_user.id,
                is_active=True,
            )
            db.add(sched)
            await db.commit()
            await db.refresh(sched)

        existing_events = (
            await db.execute(
                select(ReminderEvent).where(ReminderEvent.schedule_id == sched.id)
            )
        ).scalars().all()
        if not existing_events:
            day = now.date()
            db.add(ReminderEvent(
                schedule_id=sched.id, patient_id=pid,
                scheduled_at=datetime(day.year, day.month, day.day, 8, 0, tzinfo=timezone.utc),
                delivered_at=now - timedelta(hours=3),
                acknowledged_at=now - timedelta(hours=3),
                status=ReminderStatusEnum.ACKNOWLEDGED,
            ))
            db.add(ReminderEvent(
                schedule_id=sched.id, patient_id=pid,
                scheduled_at=now - timedelta(minutes=45),
                delivered_at=now - timedelta(minutes=45),
                acknowledged_at=now - timedelta(minutes=42),
                status=ReminderStatusEnum.ACKNOWLEDGED,
            ))
            # Pending longer than 10 minutes -> escalate on next evaluation.
            db.add(ReminderEvent(
                schedule_id=sched.id, patient_id=pid,
                scheduled_at=now - timedelta(minutes=15),
                delivered_at=now - timedelta(minutes=15),
                status=ReminderStatusEnum.PENDING,
            ))
        await db.commit()

        # RAG corpus — two synthetic documents (EN + bilingual).
        for doc in (DOC_1, DOC_2):
            existing = (
                await db.execute(
                    select(MedicalDocument).where(MedicalDocument.file_ref == doc["file_ref"])
                )
            ).scalar_one_or_none()
            if existing is None:
                await RAGService.ingest_document(
                    db=db, patient_id=pid, uploaded_by=clinician_user.id,
                    file_ref=doc["file_ref"], doc_type=doc["doc_type"],
                    extracted_text=doc["text"], title=doc["title"],
                )

        print(f"Seeded {SYN} dataset:")
        print(f"  patient   id={pid}  user={patient_user.id}")
        print(f"  caregiver user={caregiver_user.id}   clinician user={clinician_user.id}")
        print(f"  documents: {len([d for d in (DOC_1, DOC_2)])} synthetic RAG docs ingested")
        print("\nDemo login credentials (all roles):")
        for label, phone in PHONES.items():
            print(f"  {label:9s} phone={phone}  password={PASSWORD}")


if __name__ == "__main__":
    asyncio.run(main())

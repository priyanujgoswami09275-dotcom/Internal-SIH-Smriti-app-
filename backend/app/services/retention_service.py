"""Data-retention & deletion maintenance (DPDP Act 2023, Phase 11).

Applies the retention policy from CLAUDE.md:
- game_sessions:        2 years (kept for clinical trend value)
- symptom_logs:         1 year
- reminder_events:      6 months
- medical_documents:    5 years (per clinician note, whichever first) + chunks
- sync_queue:           synced outbox rows purged after 7 days
- consent_records:      revoked consents hard-deleted after the 30-day grace
- audit_logs:           never deleted (immutable compliance trail)

``run_maintenance`` is a plain async function — safe to call from a route, a
scheduler (APScheduler/cron), or a management command. Idempotent.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Dict, Optional
from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.all_models import (
    ConsentRecord,
    DocumentChunk,
    GameSession,
    MedicalDocument,
    ReminderEvent,
    RiskScreening,
    SymptomLog,
    SyncQueue,
)

RETENTION = {
    "game_sessions": timedelta(days=365 * 2),
    "symptom_logs": timedelta(days=365),
    "reminder_events": timedelta(days=182),  # ~6 months
    "medical_documents": timedelta(days=365 * 5),
    "sync_queue": timedelta(days=7),
    "consent_grace": timedelta(days=30),
}


class RetentionService:
    @staticmethod
    async def run_maintenance(db: AsyncSession, now: Optional[datetime] = None) -> Dict[str, int]:
        """Delete expired records per the retention policy. Returns counts removed."""
        now = now or datetime.now(timezone.utc)
        counts: Dict[str, int] = {}

        # game_sessions (2y, based on completion)
        cutoff = now - RETENTION["game_sessions"]
        res = await db.execute(
            delete(GameSession).where(
                GameSession.completed_at.isnot(None),
                GameSession.completed_at < cutoff,
            )
        )
        counts["game_sessions"] = res.rowcount or 0

        # symptom_logs (1y)
        cutoff = now - RETENTION["symptom_logs"]
        res = await db.execute(delete(SymptomLog).where(SymptomLog.created_at < cutoff))
        counts["symptom_logs"] = res.rowcount or 0

        # reminder_events (6mo)
        cutoff = now - RETENTION["reminder_events"]
        res = await db.execute(delete(ReminderEvent).where(ReminderEvent.scheduled_at < cutoff))
        counts["reminder_events"] = res.rowcount or 0

        # medical_documents (5y) + their chunks (chunks have no cascade in schema)
        cutoff = now - RETENTION["medical_documents"]
        doc_ids = (
            await db.execute(
                select(MedicalDocument.id).where(MedicalDocument.created_at < cutoff)
            )
        ).scalars().all()
        if doc_ids:
            res = await db.execute(
                delete(DocumentChunk).where(DocumentChunk.document_id.in_(doc_ids))
            )
            counts["document_chunks"] = res.rowcount or 0
            res = await db.execute(
                delete(MedicalDocument).where(MedicalDocument.id.in_(doc_ids))
            )
            counts["medical_documents"] = res.rowcount or 0
        else:
            counts["document_chunks"] = 0
            counts["medical_documents"] = 0

        # synced sync_queue rows (7d) — pending (synced_at NULL) rows are kept
        cutoff = now - RETENTION["sync_queue"]
        res = await db.execute(
            delete(SyncQueue).where(
                SyncQueue.synced_at.isnot(None),
                SyncQueue.synced_at < cutoff,
            )
        )
        counts["sync_queue"] = res.rowcount or 0

        # revoked consents past the 30-day grace period -> hard delete
        cutoff = now - RETENTION["consent_grace"]
        expired_consents = select(ConsentRecord.id).where(
            ConsentRecord.revoked_at.isnot(None), ConsentRecord.revoked_at < cutoff,
        )
        res = await db.execute(delete(RiskScreening).where(RiskScreening.consent_id.in_(expired_consents)))
        counts["risk_screenings"] = res.rowcount or 0
        res = await db.execute(
            delete(ConsentRecord).where(
                ConsentRecord.revoked_at.isnot(None),
                ConsentRecord.revoked_at < cutoff,
            )
        )
        counts["consent_records"] = res.rowcount or 0

        # alert_flags are not in the retention table; keep (clinical history).
        await db.commit()
        counts["alert_flags"] = 0
        return counts

"""Medical Documents RAG & Clinical Reports API Routes (Phase 10)."""

import uuid
from typing import List, Dict, Any, Optional
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import require_role
from app.database import get_db
from app.deps import ensure_clinical_access, ensure_consent
from app.models.all_models import DocumentTypeEnum, MedicalDocument, User
from app.services.compliance_service import ComplianceService
from app.services.document_extraction import MAX_UPLOAD_BYTES, extract_document_text
from app.services.rag_service import RAGService
from app.services.report_service import ReportService
from app.services.llm_client import LLMClient

router = APIRouter(prefix="/reports", tags=["Medical Documents & Clinical Reports"])

require_staff = require_role("family_caregiver", "asha_worker", "clinician")


class DocumentUploadRequest(BaseModel):
    patient_id: uuid.UUID
    file_ref: str
    doc_type: str = "prescription"
    extracted_text: str
    title: Optional[str] = None
    chunk_size: int = 500
    chunk_overlap: int = 100

    @field_validator("doc_type")
    @classmethod
    def _validate_doc_type(cls, v: str) -> str:
        try:
            DocumentTypeEnum(v)
        except ValueError:
            raise ValueError(
                f"Invalid doc_type '{v}'. Must be one of: "
                + ", ".join(e.value for e in DocumentTypeEnum)
            )
        return v


class DocumentQueryRequest(BaseModel):
    patient_id: uuid.UUID
    query: str
    top_k: int = 3
    min_similarity: float = 0.0


class DocumentAnswerRequest(BaseModel):
    patient_id: uuid.UUID
    question: str
    top_k: int = 3
    min_similarity: float = 0.0


@router.post("/documents/ingest")
async def ingest_medical_document(
    req: DocumentUploadRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Ingest, chunk, and embed medical reports or prescriptions for RAG."""
    await ensure_clinical_access(db, current_user, req.patient_id)
    await ensure_consent(db, req.patient_id, "health_data")
    doc = await RAGService.ingest_document(
        db=db,
        patient_id=req.patient_id,
        uploaded_by=current_user.id,
        file_ref=req.file_ref,
        doc_type=req.doc_type,
        extracted_text=req.extracted_text,
        title=req.title,
        chunk_size=req.chunk_size,
        chunk_overlap=req.chunk_overlap,
    )
    return {
        "message": "Document ingested and embedded successfully",
        "document_id": str(doc.id),
        "embedding_status": doc.embedding_status.value if hasattr(doc.embedding_status, "value") else str(doc.embedding_status),
    }


@router.post("/documents/upload")
async def upload_medical_document(
    patient_id: uuid.UUID,
    doc_type: str = "prescription",
    title: Optional[str] = None,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Upload a PDF/text medical document; extract, encrypt, chunk, and embed it.

    Same access, consent, and audit gates as /documents/ingest — extraction is
    the only difference (multipart file -> extracted_text -> existing pipeline).
    """
    await ensure_clinical_access(db, current_user, patient_id)
    await ensure_consent(db, patient_id, "health_data")

    raw = await file.read()
    if len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File exceeds the {MAX_UPLOAD_BYTES // (1024*1024)} MB limit.",
        )
    if not raw:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    try:
        extracted_text = extract_document_text(file.filename or "document", raw)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))

    doc = await RAGService.ingest_document(
        db=db,
        patient_id=patient_id,
        uploaded_by=current_user.id,
        file_ref=file.filename or "uploaded.pdf",
        doc_type=doc_type,
        extracted_text=extracted_text,
        title=title,
    )
    return {
        "message": "Document uploaded, extracted, and embedded successfully",
        "document_id": str(doc.id),
        "file_name": file.filename,
        "chars_extracted": len(extracted_text),
        "embedding_status": doc.embedding_status.value
        if hasattr(doc.embedding_status, "value")
        else str(doc.embedding_status),
    }


@router.post("/documents/query")
async def query_medical_documents(
    req: DocumentQueryRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Perform semantic similarity search on the patient's indexed medical records."""
    await ensure_clinical_access(db, current_user, req.patient_id)
    await ensure_consent(db, req.patient_id, "health_data")
    await ComplianceService.log_read_access(db, current_user.id, "medical_document", req.patient_id)
    results = await RAGService.query_medical_context(
        db=db,
        patient_id=req.patient_id,
        query=req.query,
        top_k=req.top_k,
        min_similarity=req.min_similarity,
    )
    return {"query": req.query, "matches": results}


@router.post("/documents/answer")
async def answer_medical_question(
    req: DocumentAnswerRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Answer a clinical question grounded in the patient's documents.

    Uses Claude for synthesis when an API key is configured; otherwise
    returns an extractive, cited summary. Never a diagnosis.
    """
    await ensure_clinical_access(db, current_user, req.patient_id)
    await ensure_consent(db, req.patient_id, "health_data")
    await ComplianceService.log_read_access(db, current_user.id, "medical_document", req.patient_id)
    result = await RAGService.answer_question(
        db=db,
        patient_id=req.patient_id,
        question=req.question,
        top_k=req.top_k,
        min_similarity=req.min_similarity,
        llm=LLMClient(),
    )
    return result


@router.get("/patients/{patient_id}/documents")
async def list_patient_documents(
    patient_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """List a patient's ingested medical documents (metadata only).

    Same gates as the read/query paths — clinical tier, health_data consent,
    DPDP read audit. Projects only the six metadata columns, so the encrypted
    `extracted_text` column is never loaded, and it is never returned.
    """
    await ensure_clinical_access(db, current_user, patient_id)
    await ensure_consent(db, patient_id, "health_data")
    await ComplianceService.log_read_access(db, current_user.id, "medical_document", str(patient_id))

    res = await db.execute(
        select(
            MedicalDocument.id,
            MedicalDocument.title,
            MedicalDocument.file_ref,
            MedicalDocument.doc_type,
            MedicalDocument.embedding_status,
            MedicalDocument.created_at,
        )
        .where(MedicalDocument.patient_id == patient_id)
        .order_by(MedicalDocument.created_at.desc(), MedicalDocument.id.desc())
        .limit(50)
    )
    documents = [
        {
            "document_id": str(doc_id),
            "title": title,
            "file_name": file_ref,
            "doc_type": doc_type.value if hasattr(doc_type, "value") else str(doc_type),
            "embedding_status": (
                embedding_status.value
                if hasattr(embedding_status, "value")
                else str(embedding_status)
            ),
            "created_at": created_at.isoformat() if created_at else None,
        }
        for doc_id, title, file_ref, doc_type, embedding_status, created_at in res.all()
    ]
    return {"documents": documents, "count": len(documents)}


@router.get("/patients/{patient_id}/latest")
async def get_latest_weekly_report(
    patient_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Most recent persisted weekly clinical report for a patient (falls back
    to generating this week's report on demand when the job hasn't run yet)."""
    await ensure_clinical_access(db, current_user, patient_id)
    await ensure_consent(db, patient_id, "health_data")
    await ComplianceService.log_read_access(db, current_user.id, "weekly_report", patient_id)

    report = await ReportService.get_latest_report(db, patient_id)
    if report is None:
        report = await ReportService.generate_and_save_weekly_report(db, patient_id)
    return {
        "report_id": str(report.id),
        "patient_id": str(report.patient_id),
        "week_start": report.week_start.isoformat(),
        "generated_at": report.generated_at.isoformat(),
        "report": report.report_json,
    }


@router.get("/patients/{patient_id}/weekly-summary")
async def get_weekly_clinical_report(
    patient_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """Generate structured weekly cognitive and clinical evaluation report."""
    await ensure_clinical_access(db, current_user, patient_id)
    await ensure_consent(db, patient_id, "health_data")
    await ComplianceService.log_read_access(db, current_user.id, "weekly_report", patient_id)
    report = await ReportService.generate_weekly_clinical_summary(db, patient_id)
    return report

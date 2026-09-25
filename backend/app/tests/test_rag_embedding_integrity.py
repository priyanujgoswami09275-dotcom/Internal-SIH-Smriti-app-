import io
import uuid

import pytest
from sqlalchemy import func, select

import app.services.rag_service as rag_service
from app.models.all_models import (
    AuditLog,
    DocumentChunk,
    EmbeddingStatusEnum,
    MedicalDocument,
)
from app.services.compliance_service import EncryptionService
from app.services.document_extraction import MAX_EXTRACTED_CHARS
from app.services.embedding_provider import HeuristicEmbeddingProvider
from app.services.llm_client import LLMClient


async def _add_provenance_free_document(db_session, patient_id):
    text = "Patient takes Donepezil 5 mg at bedtime for mild cognitive impairment."
    document = MedicalDocument(
        patient_id=patient_id,
        uploaded_by=uuid.uuid4(),
        title="Legacy prescription",
        file_ref="legacy-prescription.txt",
        doc_type="prescription",
        extracted_text=EncryptionService().encrypt(text),
        embedding_status=EmbeddingStatusEnum.COMPLETED,
    )
    db_session.add(document)
    await db_session.flush()
    chunk = DocumentChunk(
        document_id=document.id,
        patient_id=patient_id,
        chunk_text=text,
        embedding=HeuristicEmbeddingProvider().embed(text),
        page_ref=1,
    )
    db_session.add(chunk)
    await db_session.commit()
    return document, chunk


@pytest.mark.asyncio
async def test_provenance_free_document_refuses_retrieval_with_rebuild_guidance(
    db_session,
):
    patient_id = uuid.uuid4()
    await _add_provenance_free_document(db_session, patient_id)

    with pytest.raises(RuntimeError) as exc_info:
        await rag_service.RAGService.query_medical_context(
            db_session,
            patient_id=patient_id,
            query="What is the Donepezil dosage?",
        )

    message = str(exc_info.value)
    assert "without embedding provenance" in message
    assert "must be rebuilt" in message
    assert "python -m app.services.rag_service reindex" in message


@pytest.mark.asyncio
async def test_different_dimension_provider_refuses_to_score_stored_document(
    db_session,
    monkeypatch,
):
    patient_id = uuid.uuid4()
    await rag_service.RAGService.ingest_document(
        db_session,
        patient_id=patient_id,
        uploaded_by=uuid.uuid4(),
        file_ref="space.txt",
        doc_type="report",
        extracted_text="Patient takes Donepezil 5 mg at bedtime.",
    )
    monkeypatch.setattr(
        rag_service,
        "get_embedding_provider",
        lambda: HeuristicEmbeddingProvider(dimensions=384),
    )

    with pytest.raises(RuntimeError) as exc_info:
        await rag_service.RAGService.query_medical_context(
            db_session,
            patient_id=patient_id,
            query="Donepezil dosage",
        )

    message = str(exc_info.value)
    assert "1536d" in message
    assert "384d" in message
    assert "python -m app.services.rag_service reindex" in message


@pytest.mark.asyncio
async def test_model_switch_in_same_dimension_refuses_to_score(
    db_session,
    monkeypatch,
):
    patient_id = uuid.uuid4()
    await rag_service.RAGService.ingest_document(
        db_session,
        patient_id=patient_id,
        uploaded_by=uuid.uuid4(),
        file_ref="model-space.txt",
        doc_type="report",
        extracted_text="Patient takes Donepezil 5 mg at bedtime.",
    )
    changed_model = HeuristicEmbeddingProvider(dimensions=1536)
    changed_model.model = "md5-tf-v2"
    monkeypatch.setattr(
        rag_service,
        "get_embedding_provider",
        lambda: changed_model,
    )

    with pytest.raises(RuntimeError, match="md5-tf-v1.*md5-tf-v2"):
        await rag_service.RAGService.query_medical_context(
            db_session,
            patient_id=patient_id,
            query="Donepezil dosage",
        )


@pytest.mark.asyncio
async def test_matching_space_preserves_extractive_citations_and_disclaimer(db_session):
    patient_id = uuid.uuid4()
    await rag_service.RAGService.ingest_document(
        db_session,
        patient_id=patient_id,
        uploaded_by=uuid.uuid4(),
        file_ref="donepezil.txt",
        doc_type="prescription",
        extracted_text="Prescribed Donepezil 5 mg once daily at bedtime for MCI.",
    )

    result = await rag_service.RAGService.answer_question(
        db_session,
        patient_id=patient_id,
        question="What is the Donepezil dosage?",
        llm=LLMClient(api_key=""),
    )

    assert result["synthesized"] is False
    assert len(result["citations"]) == 1
    assert "Donepezil 5 mg" in result["citations"][0]["text"]
    assert "(1)" in result["answer"]
    assert result["disclaimer"] == rag_service.DISCLAIMER


def test_cosine_similarity_raises_on_dimension_mismatch():
    with pytest.raises(ValueError, match="Embedding dimension mismatch"):
        rag_service.RAGService.cosine_similarity([1.0, 0.0], [1.0, 0.0, 0.0])


@pytest.mark.asyncio
async def test_reindex_backfills_provenance_and_restores_citations(db_session):
    patient_id = uuid.uuid4()
    document, chunk = await _add_provenance_free_document(db_session, patient_id)
    document_id = document.id
    chunk_id = chunk.id
    reindex = getattr(rag_service.RAGService, "reindex_patient_documents", None)
    assert callable(reindex), "patient reindex path is missing"

    result = await reindex(
        db_session,
        patient_id=patient_id,
        actor_id=uuid.uuid4(),
    )

    assert result["documents_reindexed"] == 1
    assert result["documents_skipped"] == 0
    await db_session.refresh(document)
    await db_session.refresh(chunk)
    assert document.embedding_provider == "heuristic"
    assert document.embedding_model == "md5-tf-v1"
    assert document.embedding_dimensions == 1536

    matches = await rag_service.RAGService.query_medical_context(
        db_session,
        patient_id=patient_id,
        query="What is the Donepezil dosage?",
    )
    assert len(matches) == 1
    assert matches[0]["document_id"] == str(document_id)
    assert matches[0]["chunk_id"] == str(chunk_id)
    assert "Donepezil 5 mg" in matches[0]["text"]
    assert matches[0]["similarity"] > 0.0


@pytest.mark.asyncio
async def test_second_patient_reindex_is_a_noop(db_session):
    patient_id = uuid.uuid4()
    await _add_provenance_free_document(db_session, patient_id)
    reindex = getattr(rag_service.RAGService, "reindex_patient_documents", None)
    assert callable(reindex), "patient reindex path is missing"
    actor_id = uuid.uuid4()

    first = await reindex(db_session, patient_id=patient_id, actor_id=actor_id)
    embeddings_before = (
        await db_session.execute(select(DocumentChunk.embedding))
    ).scalars().all()
    audit_count_before = await db_session.scalar(
        select(func.count()).select_from(AuditLog).where(AuditLog.user_id == actor_id)
    )
    second = await reindex(db_session, patient_id=patient_id, actor_id=actor_id)
    embeddings_after = (
        await db_session.execute(select(DocumentChunk.embedding))
    ).scalars().all()
    audit_count_after = await db_session.scalar(
        select(func.count()).select_from(AuditLog).where(AuditLog.user_id == actor_id)
    )

    assert first["documents_reindexed"] == 1
    assert second["documents_reindexed"] == 0
    assert second["documents_skipped"] == 1
    assert embeddings_after == embeddings_before
    assert audit_count_after == audit_count_before


async def _clinician_with_patient(client):
    from app.tests.conftest import create_consented_patient, provision_staff_user

    user = await provision_staff_user()
    login = await client.post(
        "/api/v1/auth/login",
        json={"phone": user["phone"], "password": "Passw0rd123"},
    )
    assert login.status_code == 200, login.text
    patient = await create_consented_patient(client, "RAG Integrity Patient")
    return {"Authorization": f"Bearer {login.json()['access_token']}"}, patient["id"]


@pytest.mark.asyncio
async def test_upload_over_extraction_limit_is_rejected_before_persistence(
    client,
    db_session,
):
    headers, patient_id = await _clinician_with_patient(client)
    response = await client.post(
        "/api/v1/reports/documents/upload",
        params={"patient_id": patient_id},
        headers=headers,
        files={
            "file": (
                "oversized-extraction.txt",
                io.BytesIO(b"x" * (MAX_EXTRACTED_CHARS + 1)),
                "text/plain",
            )
        },
    )

    assert response.status_code == 413
    assert str(MAX_EXTRACTED_CHARS) in response.json()["detail"]
    assert "split" in response.json()["detail"].lower()
    assert (await db_session.scalar(select(func.count()).select_from(MedicalDocument))) == 0


@pytest.mark.asyncio
async def test_new_chunk_text_is_encrypted_at_rest(db_session):
    patient_id = uuid.uuid4()
    text = "Patient takes Donepezil 5 mg at bedtime."
    await rag_service.RAGService.ingest_document(
        db_session,
        patient_id=patient_id,
        uploaded_by=uuid.uuid4(),
        file_ref="encrypted-chunk.txt",
        doc_type="prescription",
        extracted_text=text,
    )

    chunk = await db_session.scalar(select(DocumentChunk))
    assert chunk.chunk_text.startswith("gAAAA")
    assert chunk.chunk_text != text
    assert EncryptionService().decrypt(chunk.chunk_text) == text


@pytest.mark.asyncio
async def test_legacy_plaintext_chunk_still_scores_and_cites(db_session):
    patient_id = uuid.uuid4()
    text = "Legacy plaintext mentions Donepezil 5 mg at bedtime."
    provider = HeuristicEmbeddingProvider()
    document = MedicalDocument(
        patient_id=patient_id,
        uploaded_by=uuid.uuid4(),
        title="Legacy plaintext chunk",
        file_ref="legacy.txt",
        doc_type="prescription",
        extracted_text=EncryptionService().encrypt(text),
        embedding_status=EmbeddingStatusEnum.COMPLETED,
        embedding_provider=provider.name,
        embedding_model=provider.model,
        embedding_dimensions=provider.dimensions,
    )
    db_session.add(document)
    await db_session.flush()
    db_session.add(
        DocumentChunk(
            document_id=document.id,
            patient_id=patient_id,
            chunk_text=text,
            embedding=provider.embed(text),
            page_ref=1,
        )
    )
    await db_session.commit()

    matches = await rag_service.RAGService.query_medical_context(
        db_session,
        patient_id=patient_id,
        query="Donepezil dosage",
    )

    assert len(matches) == 1
    assert matches[0]["text"] == text


@pytest.mark.asyncio
async def test_query_api_returns_actionable_409_for_embedding_space_mismatch(
    client,
    monkeypatch,
):
    headers, patient_id = await _clinician_with_patient(client)
    upload = await client.post(
        "/api/v1/reports/documents/upload",
        params={"patient_id": patient_id},
        headers=headers,
        files={
            "file": (
                "space-mismatch.txt",
                io.BytesIO(b"Patient takes Donepezil 5 mg at bedtime."),
                "text/plain",
            )
        },
    )
    assert upload.status_code == 200, upload.text
    monkeypatch.setattr(
        rag_service,
        "get_embedding_provider",
        lambda: HeuristicEmbeddingProvider(dimensions=384),
    )

    response = await client.post(
        "/api/v1/reports/documents/query",
        headers=headers,
        json={"patient_id": patient_id, "query": "Donepezil dosage"},
    )

    assert response.status_code == 409
    detail = response.json()["detail"]
    assert "1536d" in detail
    assert "384d" in detail
    assert "must be rebuilt" in detail or "Rebuild the index" in detail
    assert "python -m app.services.rag_service reindex" in detail
    assert "No relevant records" not in detail

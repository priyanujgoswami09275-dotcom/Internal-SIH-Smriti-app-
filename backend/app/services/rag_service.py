"""RAG (Retrieval Augmented Generation) Service for Medical Documents.

At-rest encryption: source ``extracted_text`` and each ``DocumentChunk`` are
stored AES-256 encrypted (DPDP column-level encryption). Retrieval decrypts a
legacy plaintext chunk only when constructing a citation.

Phase 10 pipeline:
1. Ingest: store the medical document, split text into overlapping chunks.
2. Embed: through the pluggable EmbeddingProvider (default: deterministic
   md5-TF hashing — stable across processes so stored vectors match fresh
   query vectors; local/openai semantic backends are config-driven and
   degrade gracefully to the default).
3. Retrieve: cosine similarity over the patient's indexed chunks with an
   optional relevance threshold.
4. Synthesize: answer clinical questions grounded in retrieved chunks — via
   Claude when configured (LLMClient), otherwise an extractive summary with
   citations. Never diagnoses: always defers to the caregiver/clinician.

Storage stays portable (JSON vector column) so tests run on SQLite and the
same code works on PostgreSQL; a pgvector index can be layered on later.

Rebuild a patient's index after changing embedding provider/model settings:

    python -m app.services.rag_service reindex \
        --patient-id <patient-uuid> --actor-id <operator-user-uuid>
"""

import uuid
from typing import List, Dict, Any, Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.all_models import MedicalDocument, DocumentChunk, EmbeddingStatusEnum
from app.models.compliance import AuditActionEnum, AuditLog
from app.services.compliance_service import EncryptionService
from app.services.embedding_provider import get_embedding_provider
from app.services.document_extraction import enforce_extracted_text_limit
from app.services.llm_client import LLMClient

DISCLAIMER = (
    "This answer is generated from the patient's stored medical records for "
    "caregiver/clinician reference only and is not a diagnosis or prescription. "
    "Please verify with a qualified clinician."
)
REINDEX_COMMAND = (
    "python -m app.services.rag_service reindex "
    "--patient-id <patient-id> --actor-id <operator-user-id>"
)
FERNET_TOKEN_PREFIX = "gAAAA"


class EmbeddingDimensionMismatchError(ValueError):
    pass


class EmbeddingCompatibilityError(RuntimeError):
    pass


class RAGService:
    # =====================================================================
    # Embedding (delegates to the configured EmbeddingProvider)
    # =====================================================================

    @staticmethod
    def _embed(text: str) -> List[float]:
        """Embed via the configured provider (heuristic default; local/openai optional)."""
        return get_embedding_provider().embed(text)

    @staticmethod
    def _assert_embedding_compatible(
        document: MedicalDocument,
        provider_name: str,
        model_name: str,
        dimensions: int,
    ) -> None:
        if (
            document.embedding_provider is None
            or document.embedding_model is None
            or document.embedding_dimensions is None
        ):
            raise EmbeddingCompatibilityError(
                f"Document {document.id} was indexed without embedding provenance and "
                f"must be rebuilt before retrieval. Run: {REINDEX_COMMAND}"
            )
        stored = (
            document.embedding_provider,
            document.embedding_model,
            document.embedding_dimensions,
        )
        active = (provider_name, model_name, dimensions)
        if stored != active:
            raise EmbeddingCompatibilityError(
                f"Document {document.id} embedding space is {stored[0]}/{stored[1]}/"
                f"{stored[2]}d, but the active space is {active[0]}/{active[1]}/"
                f"{active[2]}d. The index must be rebuilt with: {REINDEX_COMMAND}"
            )

    @staticmethod
    def _decrypt_chunk_text(value: str) -> str:
        if not value.startswith(FERNET_TOKEN_PREFIX):
            return value
        plaintext = EncryptionService().decrypt(value)
        if plaintext == value:
            raise EmbeddingCompatibilityError(
                "A document chunk is marked encrypted but cannot be decrypted. "
                f"Restore the source document and rebuild the index with: {REINDEX_COMMAND}"
            )
        return plaintext

    @staticmethod
    def _chunk_text_is_encrypted(value: str) -> bool:
        if not value.startswith(FERNET_TOKEN_PREFIX):
            return False
        return EncryptionService().decrypt(value) != value

    @staticmethod
    def generate_embedding(text: str, dim: int = None) -> List[float]:
        """Embedding vector via the configured provider.

        Kept as a static convenience (used by callers that need a bare vector);
        ``dim`` is accepted for backward compatibility with the old signature
        but the provider owns the vector width.
        """
        if dim is not None:
            # Explicit-width requests use the heuristic provider at that width.
            from app.services.embedding_provider import HeuristicEmbeddingProvider

            return HeuristicEmbeddingProvider(dimensions=dim).embed(text)
        return RAGService._embed(text)

    @staticmethod
    def cosine_similarity(a: List[float], b: List[float]) -> float:
        """True cosine similarity: scale-independent (providers emit unit
        vectors, where this equals the raw dot product; non-normalized
        vectors are normalized here so scores stay comparable)."""
        if not a or not b:
            return 0.0
        if len(a) != len(b):
            raise EmbeddingDimensionMismatchError(
                f"Embedding dimension mismatch: {len(a)} != {len(b)}"
            )
        dot = sum(x * y for x, y in zip(a, b))
        norm_a = sum(x * x for x in a) ** 0.5
        norm_b = sum(y * y for y in b) ** 0.5
        if norm_a == 0.0 or norm_b == 0.0:
            return 0.0
        return dot / (norm_a * norm_b)

    # =====================================================================
    # Chunking
    # =====================================================================

    @staticmethod
    def chunk_text(text: str, chunk_size: int = 500, overlap: int = 100) -> List[str]:
        """Split text into character-sized chunks with overlap for continuity."""
        text = (text or "").strip()
        if not text:
            return []
        if chunk_size <= 0:
            chunk_size = 500
        overlap = max(0, min(overlap, chunk_size // 2))

        chunks: List[str] = []
        start = 0
        n = len(text)
        while start < n:
            end = min(start + chunk_size, n)
            if end == n:
                chunks.append(text[start:].strip())
                break
            # Prefer breaking on a word boundary near the end of the window.
            cut = text.rfind(" ", start, end)
            if cut > start + chunk_size // 2:
                end = cut
            chunks.append(text[start:end].strip())
            start = max(end - overlap, start + 1)
        return [c for c in chunks if c]

    # =====================================================================
    # Ingest & search
    # =====================================================================

    @staticmethod
    async def ingest_document(
        db: AsyncSession,
        patient_id: uuid.UUID,
        uploaded_by: uuid.UUID,
        file_ref: str,
        doc_type: str,
        extracted_text: str,
        title: Optional[str] = None,
        chunk_size: int = 500,
        chunk_overlap: int = 100,
    ) -> MedicalDocument:
        """Store a medical document and index chunk embeddings for RAG search.

        ``extracted_text`` and chunk text are stored AES-256 encrypted at rest;
        chunking and embedding use plaintext only in memory.

        The document, its chunks, and its DPDP ``write`` audit row are added to
        one session and committed together, so this ingest is FAIL-CLOSED: if
        the audit row cannot be written the document is not stored either. That
        is deliberately stricter than ``ComplianceService.log_write_access``,
        which is best-effort and is used by the lower-risk write paths
        (reminders, alerts, sync materialization).
        """
        extracted_text = enforce_extracted_text_limit(extracted_text or "")
        encryption = EncryptionService()
        provider = get_embedding_provider()
        chunks = RAGService.chunk_text(
            extracted_text, chunk_size=chunk_size, overlap=chunk_overlap
        )
        dimensions = int(provider.dimensions)
        if dimensions <= 0:
            raise EmbeddingDimensionMismatchError(
                f"Embedding provider declared invalid dimension {dimensions}"
            )
        prepared_chunks: List[tuple[str, List[float]]] = []
        for chunk_text in chunks:
            vector = provider.embed(chunk_text)
            if not vector:
                raise EmbeddingDimensionMismatchError(
                    "Embedding provider returned an empty vector"
                )
            actual_dimensions = len(vector)
            if prepared_chunks and actual_dimensions != dimensions:
                raise EmbeddingDimensionMismatchError(
                    f"Embedding dimension mismatch: expected {dimensions}, "
                    f"received {actual_dimensions}"
                )
            dimensions = actual_dimensions
            prepared_chunks.append((chunk_text, vector))

        doc = MedicalDocument(
            patient_id=patient_id,
            uploaded_by=uploaded_by,
            title=title or "Medical Document",
            file_ref=file_ref,
            doc_type=doc_type,
            extracted_text=encryption.encrypt(extracted_text),
            embedding_status=EmbeddingStatusEnum.PENDING,
            embedding_provider=provider.name,
            embedding_model=provider.model,
            embedding_dimensions=dimensions,
        )
        db.add(doc)
        await db.flush()
        db.add(
            AuditLog(
                user_id=uploaded_by,
                action=AuditActionEnum.WRITE,
                resource_type="medical_document",
                resource_id=doc.id,
                ip_address="127.0.0.1",
                details={},
            )
        )

        for idx, (chunk_text, vector) in enumerate(prepared_chunks):
            chunk_record = DocumentChunk(
                document_id=doc.id,
                patient_id=doc.patient_id,
                chunk_text=encryption.encrypt(chunk_text),
                embedding=vector,
                page_ref=idx + 1,
            )
            db.add(chunk_record)

        doc.embedding_status = EmbeddingStatusEnum.COMPLETED
        await db.commit()
        await db.refresh(doc)
        return doc

    @staticmethod
    async def reindex_patient_documents(
        db: AsyncSession,
        patient_id: uuid.UUID,
        actor_id: uuid.UUID,
    ) -> Dict[str, Any]:
        provider = get_embedding_provider()
        documents = (
            await db.execute(
                select(MedicalDocument)
                .where(MedicalDocument.patient_id == patient_id)
                .order_by(MedicalDocument.created_at, MedicalDocument.id)
            )
        ).scalars().all()
        encryption = EncryptionService()
        reindexed_documents = 0
        skipped_documents = 0
        reindexed_chunks = 0
        active_dimensions = int(provider.dimensions)

        for document in documents:
            chunks = (
                await db.execute(
                    select(DocumentChunk)
                    .where(DocumentChunk.document_id == document.id)
                    .order_by(DocumentChunk.page_ref, DocumentChunk.id)
                )
            ).scalars().all()
            provenance_matches = (
                document.embedding_provider == provider.name
                and document.embedding_model == provider.model
                and document.embedding_dimensions is not None
            )
            vectors_match = all(
                chunk.embedding
                and len(chunk.embedding) == document.embedding_dimensions
                for chunk in chunks
            )
            texts_encrypted = all(
                RAGService._chunk_text_is_encrypted(chunk.chunk_text)
                for chunk in chunks
            )
            if provenance_matches and vectors_match and texts_encrypted:
                skipped_documents += 1
                active_dimensions = int(document.embedding_dimensions)
                continue

            dimensions = int(provider.dimensions)
            if dimensions <= 0:
                raise EmbeddingDimensionMismatchError(
                    f"Embedding provider declared invalid dimension {dimensions}"
                )
            prepared_chunks: List[tuple[str, List[float]]] = []
            for chunk in chunks:
                plaintext = RAGService._decrypt_chunk_text(chunk.chunk_text)
                vector = provider.embed(plaintext)
                if not vector:
                    raise EmbeddingDimensionMismatchError(
                        "Embedding provider returned an empty vector"
                    )
                actual_dimensions = len(vector)
                if prepared_chunks and actual_dimensions != dimensions:
                    raise EmbeddingDimensionMismatchError(
                        f"Embedding dimension mismatch: expected {dimensions}, "
                        f"received {actual_dimensions}"
                    )
                dimensions = actual_dimensions
                prepared_chunks.append((plaintext, vector))

            document.embedding_provider = provider.name
            document.embedding_model = provider.model
            document.embedding_dimensions = dimensions
            document.embedding_status = EmbeddingStatusEnum.COMPLETED
            active_dimensions = dimensions
            for chunk, (plaintext, vector) in zip(chunks, prepared_chunks):
                chunk.chunk_text = encryption.encrypt(plaintext)
                chunk.embedding = vector
            reindexed_chunks += len(prepared_chunks)
            reindexed_documents += 1
            db.add(
                AuditLog(
                    user_id=actor_id,
                    action=AuditActionEnum.WRITE,
                    resource_type="medical_document",
                    resource_id=document.id,
                    ip_address="127.0.0.1",
                    details={
                        "operation": "rag_reindex",
                        "patient_id": str(patient_id),
                        "embedding_provider": provider.name,
                        "embedding_model": provider.model,
                        "embedding_dimensions": dimensions,
                    },
                )
            )

        if reindexed_documents:
            await db.commit()
        return {
            "patient_id": str(patient_id),
            "documents_reindexed": reindexed_documents,
            "documents_skipped": skipped_documents,
            "chunks_reindexed": reindexed_chunks,
            "embedding_provider": provider.name,
            "embedding_model": provider.model,
            "embedding_dimensions": active_dimensions,
        }

    @staticmethod
    async def query_medical_context(
        db: AsyncSession,
        patient_id: uuid.UUID,
        query: str,
        top_k: int = 3,
        min_similarity: float = 0.0,
    ) -> List[Dict[str, Any]]:
        """Retrieve the most relevant chunks for a patient's clinical query."""
        provider = get_embedding_provider()
        query_embedding = provider.embed(query)
        if not query_embedding:
            raise EmbeddingDimensionMismatchError(
                "Embedding provider returned an empty query vector"
            )
        query_dimensions = len(query_embedding)

        stmt = (
            select(MedicalDocument, DocumentChunk)
            .outerjoin(DocumentChunk, DocumentChunk.document_id == MedicalDocument.id)
            .where(MedicalDocument.patient_id == patient_id)
        )
        res = await db.execute(stmt)
        rows = res.all()

        scored: List[Dict[str, Any]] = []
        for doc, chunk in rows:
            RAGService._assert_embedding_compatible(
                doc,
                provider.name,
                provider.model,
                query_dimensions,
            )
            if chunk is None:
                continue
            if not chunk.embedding:
                raise EmbeddingCompatibilityError(
                    f"Document {doc.id} has a chunk without an embedding. "
                    f"Rebuild the index with: {REINDEX_COMMAND}"
                )
            try:
                similarity = RAGService.cosine_similarity(
                    query_embedding, chunk.embedding
                )
            except EmbeddingDimensionMismatchError as exc:
                raise EmbeddingCompatibilityError(
                    f"Document {doc.id} contains an embedding with the wrong dimension. "
                    f"Rebuild the index with: {REINDEX_COMMAND}"
                ) from exc
            if similarity < min_similarity:
                continue
            scored.append(
                {
                    "chunk_id": str(chunk.id),
                    "document_id": str(doc.id),
                    "title": doc.title,
                    "file_ref": doc.file_ref,
                    "doc_type": doc.doc_type.value if hasattr(doc.doc_type, "value") else str(doc.doc_type),
                    "page_ref": chunk.page_ref,
                    "text": RAGService._decrypt_chunk_text(chunk.chunk_text),
                    "similarity": round(similarity, 4),
                }
            )

        scored.sort(key=lambda x: x["similarity"], reverse=True)
        return scored[: max(0, top_k)]

    # =====================================================================
    # Answer synthesis
    # =====================================================================

    @staticmethod
    async def answer_question(
        db: AsyncSession,
        patient_id: uuid.UUID,
        question: str,
        top_k: int = 3,
        min_similarity: float = 0.0,
        llm: Optional[LLMClient] = None,
    ) -> Dict[str, Any]:
        """Answer a clinical question grounded in the patient's documents.

        Uses Claude when `llm.enabled`; otherwise returns an extractive
        summary citing the retrieved chunks. Never replaces clinician advice.
        """
        citations = await RAGService.query_medical_context(
            db, patient_id, question, top_k=top_k, min_similarity=min_similarity
        )
        if not citations:
            return {
                "question": question,
                "answer": "No relevant records found for this patient to answer the question.",
                "synthesized": False,
                "citations": [],
                "disclaimer": DISCLAIMER,
            }

        client = llm or LLMClient()
        synthesized = False
        if client.enabled:
            context_blocks = "\n\n".join(
                f"[{i + 1}] (doc: {c['title'] or c['file_ref']}, similarity {c['similarity']}) {c['text']}"
                for i, c in enumerate(citations)
            )
            system_prompt = (
                "You are a clinical documentation assistant for caregivers and clinicians "
                "of elderly patients. Answer the user's question ONLY from the supplied "
                "retrieved record excerpts, citing each claim as [n] matching the excerpt "
                "numbers. If the excerpts do not contain the answer, say so plainly. Never "
                "diagnose or prescribe — end uncertain answers with a note to consult the "
                "treating clinician. Keep answers short, structured, and in simple language."
            )
            try:
                answer = await client.complete(
                    system=system_prompt,
                    messages=[
                        {
                            "role": "user",
                            "content": (
                                f"Question: {question}\n\nRetrieved records:\n{context_blocks}"
                            ),
                        }
                    ],
                    max_tokens=400,
                )
                synthesized = True
            except Exception:
                # Degrade to extractive rather than failing the request.
                answer = RAGService._extractive_answer(question, citations)
        else:
            answer = RAGService._extractive_answer(question, citations)

        return {
            "question": question,
            "answer": answer,
            "synthesized": synthesized,
            "citations": citations,
            "disclaimer": DISCLAIMER,
        }

    @staticmethod
    def _extractive_answer(question: str, citations: List[Dict[str, Any]]) -> str:
        parts = [f"({i + 1}) {c['text']}" for i, c in enumerate(citations)]
        return (
            f"Based on the patient's stored records, here is what was found "
            f"relevant to your question: {' '.join(parts)}. "
            f"Please confirm details with the treating clinician."
        )


def _build_reindex_parser():
    import argparse

    parser = argparse.ArgumentParser(description="Medical document RAG maintenance")
    subparsers = parser.add_subparsers(dest="command", required=True)
    reindex = subparsers.add_parser(
        "reindex",
        help="re-embed a patient's documents with the active provider",
    )
    reindex.add_argument("--patient-id", type=uuid.UUID, required=True)
    reindex.add_argument("--actor-id", type=uuid.UUID, required=True)
    return parser


async def _run_reindex(patient_id: uuid.UUID, actor_id: uuid.UUID) -> Dict[str, Any]:
    from app.database import async_session_maker, engine

    try:
        async with async_session_maker() as db:
            return await RAGService.reindex_patient_documents(
                db,
                patient_id=patient_id,
                actor_id=actor_id,
            )
    finally:
        await engine.dispose()


def main(argv: Optional[List[str]] = None) -> int:
    import asyncio
    import json

    args = _build_reindex_parser().parse_args(argv)
    if args.command == "reindex":
        result = asyncio.run(_run_reindex(args.patient_id, args.actor_id))
        print(json.dumps(result, sort_keys=True))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

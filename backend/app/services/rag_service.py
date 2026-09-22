"""RAG (Retrieval Augmented Generation) Service for Medical Documents.

At-rest encryption: the source ``extracted_text`` is stored AES-256 encrypted
(DPDP column-level encryption). Chunks are stored plaintext because retrieval
and citation rendering need the text at query time; the encrypted source
remains the durable record.

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
"""

import uuid
from typing import List, Dict, Any, Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.all_models import MedicalDocument, DocumentChunk, EmbeddingStatusEnum
from app.services.compliance_service import EncryptionService
from app.services.embedding_provider import get_embedding_provider
from app.services.llm_client import LLMClient

DISCLAIMER = (
    "This answer is generated from the patient's stored medical records for "
    "caregiver/clinician reference only and is not a diagnosis or prescription. "
    "Please verify with a qualified clinician."
)


class RAGService:
    # =====================================================================
    # Embedding (delegates to the configured EmbeddingProvider)
    # =====================================================================

    @staticmethod
    def _embed(text: str) -> List[float]:
        """Embed via the configured provider (heuristic default; local/openai optional)."""
        return get_embedding_provider().embed(text)

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
        if not a or not b or len(a) != len(b):
            return 0.0
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

        ``extracted_text`` is stored AES-256 encrypted at rest; chunking and
        embedding use the plaintext in memory before it is discarded.
        """
        doc = MedicalDocument(
            patient_id=patient_id,
            uploaded_by=uploaded_by,
            title=title or "Medical Document",
            file_ref=file_ref,
            doc_type=doc_type,
            extracted_text=EncryptionService().encrypt(extracted_text or ""),
            embedding_status=EmbeddingStatusEnum.PENDING,
        )
        db.add(doc)
        await db.commit()
        await db.refresh(doc)

        chunks = RAGService.chunk_text(
            extracted_text, chunk_size=chunk_size, overlap=chunk_overlap
        )
        for idx, chunk_text in enumerate(chunks):
            chunk_record = DocumentChunk(
                document_id=doc.id,
                patient_id=doc.patient_id,
                chunk_text=chunk_text,
                embedding=RAGService._embed(chunk_text),
                page_ref=idx + 1,
            )
            db.add(chunk_record)

        doc.embedding_status = EmbeddingStatusEnum.COMPLETED
        await db.commit()
        await db.refresh(doc)
        return doc

    @staticmethod
    async def query_medical_context(
        db: AsyncSession,
        patient_id: uuid.UUID,
        query: str,
        top_k: int = 3,
        min_similarity: float = 0.0,
    ) -> List[Dict[str, Any]]:
        """Retrieve the most relevant chunks for a patient's clinical query."""
        query_embedding = RAGService._embed(query)

        stmt = (
            select(DocumentChunk, MedicalDocument)
            .join(MedicalDocument, MedicalDocument.id == DocumentChunk.document_id)
            .where(MedicalDocument.patient_id == patient_id)
        )
        res = await db.execute(stmt)
        rows = res.all()

        scored: List[Dict[str, Any]] = []
        for chunk, doc in rows:
            if not chunk.embedding:
                continue
            similarity = RAGService.cosine_similarity(query_embedding, chunk.embedding)
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
                    "text": chunk.chunk_text,
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

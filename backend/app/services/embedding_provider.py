"""EmbeddingProvider — the seam between RAG retrieval and embedding backends.

Local-first design:

- ``heuristic`` (default): deterministic md5-weighted term-frequency hashing
  with no dependencies and no network. Vectors are identical across processes
  and restarts, so stored embeddings always match fresh query embeddings.
  Good enough to exercise the full RAG pipeline and to demo; NOT a semantic
  model — swap in ``local`` / ``openai`` for real retrieval.

- ``local``: sentence-transformers (e.g. multilingual-e5) — real multilingual
  semantic embeddings, runs on this host. Requires
  ``pip install sentence-transformers`` plus a one-time model download.

- ``openai``: hosted ``text-embedding-3-*`` API. Requires the ``openai``
  package and an ``OPENAI_API_KEY``.

Registry contract: ``get_embedding_provider()`` never raises for a missing
backend — if the configured provider is unavailable (package not installed /
key absent) it logs a warning and returns the heuristic provider, so RAG
always works. Callers persist provider/model/dimension provenance and reject
vectors from a different embedding space.

Vector persistence is intentionally a portable JSON float list. A pgvector
scale-up is not a transparent column swap: it requires a reviewed schema
migration, a vector-aware storage/provider adapter, an HNSW/IVFFlat benchmark,
and a complete backfill or reindex before retrieval changes.
"""
from __future__ import annotations

import hashlib
import importlib.util
import logging
import math
import os
from abc import ABC, abstractmethod
from typing import List, Optional

from app.config import settings

logger = logging.getLogger(__name__)


def tokenize(text: str) -> List[str]:
    """Lowercase alphanumeric word tokens (language-agnostic whitespace split)."""
    clean = "".join(ch.lower() if ch.isalnum() or ch.isspace() else " " for ch in text)
    return [w for w in clean.split() if w]


def _stable_token_hashes(text: str, dim: int) -> List[tuple]:
    """Yield (bucket, weight) pairs via stable md5 hashing.

    Weighted term frequency: earlier tokens and repeated mentions weigh more,
    which gives short clinical phrases a distinct signature.
    """
    out = []
    for i, token in enumerate(tokenize(text)):
        digest = hashlib.md5(token.encode("utf-8")).digest()
        bucket = int.from_bytes(digest[:8], "big") % dim
        weight = 1.0 / (1.0 + 0.5 * i) + 0.25
        out.append((bucket, weight))
    return out


class EmbeddingUnavailableError(RuntimeError):
    """Raised when a configured embedding backend cannot be used."""


class EmbeddingProvider(ABC):
    name: str = "abstract"
    model: str = "abstract"
    dimensions: int = 1536

    @abstractmethod
    def embed(self, text: str) -> List[float]:
        """Return a normalized embedding vector for a single text."""

    def embed_many(self, texts: List[str]) -> List[List[float]]:
        return [self.embed(t) for t in texts]


class HeuristicEmbeddingProvider(EmbeddingProvider):
    """Deterministic, dependency-free fallback embedder (md5-TF hashing)."""

    name = "heuristic"
    model = "md5-tf-v1"

    def __init__(self, dimensions: Optional[int] = None):
        self.dimensions = dimensions or settings.EMBEDDING_DIMENSIONS

    def embed(self, text: str) -> List[float]:
        vec = [0.0] * self.dimensions
        for bucket, weight in _stable_token_hashes(text, self.dimensions):
            vec[bucket] += weight
        norm = math.sqrt(sum(x * x for x in vec)) or 1.0
        return [x / norm for x in vec]


class LocalSentenceTransformerProvider(EmbeddingProvider):
    """Real multilingual embeddings via sentence-transformers (optional).

    Instantiation only checks for the package; the model loads lazily on the
    first ``embed`` call (one-time download of ~100 MB).
    """

    name = "local"

    def __init__(self, model: Optional[str] = None):
        if importlib.util.find_spec("sentence_transformers") is None:
            raise EmbeddingUnavailableError(
                "sentence-transformers is not installed. Run: pip install sentence-transformers"
            )
        self.model = model or settings.EMBEDDING_MODEL
        self._encoder = None
        # multilingual-e5-small -> 384 dims; expose so callers can size storage.
        self.dimensions = 384

    def _ensure_model(self):
        if self._encoder is None:
            from sentence_transformers import SentenceTransformer  # lazy import

            self._encoder = SentenceTransformer(self.model)
        return self._encoder

    def embed(self, text: str) -> List[float]:
        vector = self._ensure_model().encode(text, normalize_embeddings=True)
        return [float(x) for x in vector]


class OpenAIEmbeddingProvider(EmbeddingProvider):
    """Hosted embeddings via the OpenAI API (optional)."""

    name = "openai"

    def __init__(self, model: Optional[str] = None, api_key: Optional[str] = None):
        api_key = api_key or os.getenv("OPENAI_API_KEY")
        if importlib.util.find_spec("openai") is None or not api_key:
            raise EmbeddingUnavailableError(
                "OpenAI embeddings need the 'openai' package and OPENAI_API_KEY"
            )
        self.model = model or settings.EMBEDDING_MODEL or "text-embedding-3-small"
        self.dimensions = 1536  # text-embedding-3-small; adjust per model
        import openai  # lazy import

        self._client = openai.OpenAI(api_key=api_key)

    def embed(self, text: str) -> List[float]:
        resp = self._client.embeddings.create(model=self.model, input=text)
        return list(resp.data[0].embedding)


def _build_provider(name: str) -> EmbeddingProvider:
    if name == "heuristic":
        return HeuristicEmbeddingProvider()
    if name == "local":
        return LocalSentenceTransformerProvider()
    if name == "openai":
        return OpenAIEmbeddingProvider()
    raise EmbeddingUnavailableError(f"Unknown EMBEDDING_PROVIDER: {name!r}")


def get_embedding_provider(name: Optional[str] = None) -> EmbeddingProvider:
    """Return the configured provider, falling back to heuristic if unavailable.

    Never raises: a missing optional backend (package / key / model) degrades
    to the deterministic provider so the pipeline keeps working.
    """
    name = (name or settings.EMBEDDING_PROVIDER or "heuristic").lower()
    if name == "heuristic":
        return HeuristicEmbeddingProvider()
    try:
        return _build_provider(name)
    except EmbeddingUnavailableError as exc:
        logger.warning("Embedding provider %r unavailable (%s) — using heuristic.", name, exc)
        return HeuristicEmbeddingProvider()

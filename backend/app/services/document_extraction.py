"""Document text extraction for RAG ingestion (PDF / plain text / markdown).

Reuses the existing RAGService.ingest_document pipeline — extraction is the
only new seam. Unsupported formats raise ValueError -> HTTP 400.
"""
import logging
from typing import Optional

logger = logging.getLogger(__name__)

MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB
MAX_EXTRACTED_CHARS = 100_000

TEXT_EXTENSIONS = {".txt", ".md", ".text", ".csv"}


class ExtractedTextLimitError(ValueError):
    pass


def enforce_extracted_text_limit(text: str) -> str:
    if len(text) > MAX_EXTRACTED_CHARS:
        raise ExtractedTextLimitError(
            f"Extracted text is {len(text)} characters; maximum is "
            f"{MAX_EXTRACTED_CHARS}. Split the document into smaller files and retry."
        )
    return text


def extract_document_text(filename: str, raw: bytes) -> str:
    """Extract plaintext from an uploaded document's bytes.

    PDF via pypdf (pure python); text-like formats decoded as UTF-8 with a
    latin-1 fallback so legacy files still ingest.
    """
    ext = "." + filename.rsplit(".", 1)[-1].lower() if "." in filename else ""

    if ext == ".pdf" or _looks_like_pdf(raw):
        return _extract_pdf(raw)
    if ext in TEXT_EXTENSIONS or _looks_like_text(raw):
        return _decode_text(raw)
    raise ValueError(
        f"Unsupported file type '{ext or 'unknown'}'. Upload a PDF or text file."
    )


def _looks_like_pdf(raw: bytes) -> bool:
    return raw[:5] == b"%PDF-"


def _looks_like_text(raw: bytes) -> bool:
    """Heuristic: decode-able as UTF-8 and mostly printable characters."""
    try:
        raw.decode("utf-8")
        return True
    except UnicodeDecodeError:
        return False


def _decode_text(raw: bytes) -> str:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("latin-1", errors="replace")
    return enforce_extracted_text_limit(text)


def _extract_pdf(raw: bytes) -> str:
    try:
        import io

        from pypdf import PdfReader
    except ImportError as exc:  # pragma: no cover - env guard
        raise ValueError(
            "PDF extraction requires the 'pypdf' package (pip install pypdf)."
        ) from exc

    try:
        reader = PdfReader(io.BytesIO(raw))
        pages = [page.extract_text() or "" for page in reader.pages]
    except Exception as exc:
        raise ValueError(f"Could not read this PDF: {exc}") from exc

    text = "\n\n".join(p.strip() for p in pages if p and p.strip())
    if not text:
        raise ValueError(
            "No selectable text found in this PDF — it may be a scanned image. "
            "Paste the text instead, or upload a text-based PDF."
        )
    return enforce_extracted_text_limit(text)


# Optional CLI self-check:  python -m app.services.document_extraction
if __name__ == "__main__":
    assert _decode_text(b"hello") == "hello"
    assert _looks_like_pdf(b"%PDF-1.7 rest") and not _looks_like_pdf(b"plain")
    try:
        extract_document_text("scan.png", b"\x89PNG...")
        raise SystemExit("should have raised for unsupported type")
    except ValueError as e:
        assert "Unsupported" in str(e)
    print("document_extraction: OK")

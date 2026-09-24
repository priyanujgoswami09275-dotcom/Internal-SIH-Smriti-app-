/// Client-side pre-flight for medical-document uploads.
///
/// Mirrors the backend exactly (`backend/app/services/document_extraction.py`):
/// 10 MB cap and PDF/text-family files. The backend remains authoritative —
/// this only avoids wasting an upload that is certain to fail.
library;

const int kMaxDocumentBytes = 10 * 1024 * 1024;

const Set<String> kAllowedDocumentExtensions = {'pdf', 'txt', 'md', 'text', 'csv'};

/// Returns a user-facing message when the file cannot be uploaded, else null.
String? validateDocumentFile({
  required String filename,
  required int byteLength,
}) {
  final name = filename.toLowerCase();
  final dot = name.lastIndexOf('.');
  final ext = dot == -1 ? '' : name.substring(dot + 1);
  if (!kAllowedDocumentExtensions.contains(ext)) {
    return "That file type isn't supported. Upload a PDF or text file "
        '(.txt, .md, .text, .csv).';
  }
  if (byteLength == 0) {
    return "That file is empty — pick a file that has text in it.";
  }
  if (byteLength > kMaxDocumentBytes) {
    return 'That file is over the 10 MB limit — choose a smaller file.';
  }
  return null;
}

# Mobile document upload / RAG — finish and harden (design)

**Date:** 2026-09-24
**Branch:** `feat/mobile-documents-rag` (off `feat/caregiver-dashboard-mobile-port` @ `8a5c107`)
**Status:** approved in chat; STEP 4 remains design-note-only

## Goal

Make the mobile document path honest and complete: a staff user (ASHA worker,
clinician, admin) picks a PDF or text file, it uploads, shows up in a documents
list, and a cited RAG answer can reference it. Every failure mode reports
itself visibly. Family caregivers stay locked with a short explanation. The
patient home line stops promising something family caregivers cannot do.

Constraints: never touch the demo database; mock the API in every test; no new
mobile dependencies unless separately approved.

## Audit summary (2026-09-24, pre-change)

| Surface | State |
|---|---|
| `ApiService.uploadDocument` (`mobile/lib/services/api_service.dart:588`) | multipart POST, `patient_id` query + field, one 401→refresh→rebuild retry, `ApiException` normalization. No client size/type check. |
| file_picker wiring (`mobile/lib/screens/rag_upload_screen.dart:120`) | `FileType.custom`, extensions `pdf, txt, md, doc, docx` — **`doc`/`docx` are rejected by the backend**. |
| `DocumentsCard` consent state (`caregiver/sections/documents_card.dart`) | normal vs gold consent lock, button always enabled. Rendered for every caregiver role, so family caregivers get a live button that 403s. |
| Second entry point | app-bar upload icon (`caregiver_dashboard_screen.dart:315`) — no `onConsentMissing` wiring (card entry has it). |
| RAG Q&A screen | **does not exist**; `POST /reports/documents/answer` exists, unused. |
| Documents list | **does not exist**; no backend list endpoint. |
| Backend acceptance (`backend/app/services/document_extraction.py`) | 10 MB cap → 413; accepts `.pdf`/`%PDF-`, `.txt/.md/.text/.csv` and any UTF-8-decodable bytes; rejects binary unknown types → 400; **no OCR** — image-only PDF → 400 "No selectable text found". |

Role truth: `require_role(...)` always adds `admin` (`core/security.py:19`), and
`get_permission_tier` (`deps.py:139`) makes admin/clinician/asha_worker clinical;
family_caregiver is basic tier → 403 on every clinical-gated document route.
Patients are outside `require_staff` → 403.

## Decisions

1. **New read endpoint** for the list; metadata only, no `extracted_text`.
2. **Documents hub screen** (`DocumentsScreen`) holds list + Upload + Ask; the
   upload form stays a focused screen; `RagQaScreen` holds question/answer.
3. **No new dependencies.** Offline detection reuses the existing
   `ApiException('Network error: …')` wrapper via an `isNetworkError` getter.
4. **Client allowlist mirrors the backend**: `pdf, txt, md, text, csv`;
   `doc`/`docx` removed from the picker (they can only ever 400).
5. **Server stays authoritative.** The family lock is a client affordance
   driven by `summary['view'] == 'basic'`, not a security control.
6. **Nothing is queued offline.** Uploads fail loudly; no sync-queue path is
   added (the outbox only carries game sessions, reminder acks, notes).

## Backend change (one endpoint)

`GET /api/v1/reports/patients/{patient_id}/documents` in
`backend/app/routes/reports.py`, gate order identical to `documents/query`:

```
require_staff → ensure_clinical_access → ensure_consent('health_data')
→ ComplianceService.log_read_access(db, user, 'medical_document', patient_id)
```

Newest-first (`created_at desc`), cap 50. Response:

```json
{"documents": [{"document_id": "…", "title": "…", "file_name": "…",
                "doc_type": "prescription", "embedding_status": "completed",
                "created_at": "2026-09-24T10:00:00"}],
 "count": 1}
```

`embedding_status`/`doc_type` are enum `.value`s. No pagination beyond the cap;
no size/MIME columns exist on `MedicalDocument` to expose.

## Mobile changes

### ApiService
- `Future<List<Map<String, dynamic>>> listDocuments(String patientId)`
- `Future<Map<String, dynamic>> askDocumentQuestion({required String patientId, required String question, int topK = 3})`
- `ApiException.isNetworkError` → `statusCode == null && message.startsWith('Network error')`

### Validation (pure, testable)
`String? validateDocumentFile({required String filename, required int byteLength})`
— allowlist `pdf/txt/md/text/csv`, `<= 10 MB` (mirrors `MAX_UPLOAD_BYTES`),
non-empty. Runs on pick (Upload stays disabled) and again on upload.

### Failure mapping (extends `formatRagUploadFailure`)
| Case | User-visible message |
|---|---|
| 403 `health_data` | existing consent copy + `onConsentMissing` (already works) |
| 403 clinical tier | "Your account can't add health documents. A health worker — ASHA worker, clinician, or admin — can." |
| 401 after refresh | "Session expired — sign in again." (today: silent) |
| 413 | "That file is over the 10 MB limit — choose a smaller file." |
| 400 | server detail (unsupported type / no selectable text) |
| network error | "You're offline — try again when connected." (never queued) |
| 429 | "Rate limit reached — wait a minute and try again." |
| other | server detail, never a bare code |

### Screens
- `DocumentsScreen(patientId)`: list rows (title, file name, type, date,
  embedding status) or empty state; `UPLOAD DOCUMENT` → existing
  `RagUploadScreen`; `ASK ABOUT DOCUMENTS` → `RagQaScreen`; reload after
  upload; honest states for 403 tier (lock), 403 consent, offline + Retry.
- `RagQaScreen(patientId)`: question field, answer, numbered citations
  (title + similarity), disclaimer; "No relevant records found…" renders as a
  plain answer, not an error.

### family_caregiver lock + entry points
- `DocumentsCard` gains `isClinical`; basic view → lock card
  ("Health worker only — family caregiver accounts can't add or read health
  documents. Ask an ASHA worker, clinician, or admin."), no buttons, no list
  fetch; app-bar upload icon hidden for basic view.
- App-bar icon wired to the same `onConsentMissing` callback as the card.

### Patient line
`mobile/lib/main.dart:385` → "Your health worker can add your health documents."
Three tests assert the old copy and are updated:
`caregiver_scale_test.dart:401`, `caregiver_role_routing_test.dart:391`,
`shell_roles_test.dart:15`.

## Tests (mocked; demo DB untouched)

Backend (`backend/app/tests/`): list endpoint per role (clinician/asha/admin
200 + newest-first, family 403, patient 403, no-consent 403, read-audit row
written, empty list); upload role matrix (asha/admin 200, family 403, patient
403) and the 413 test the existing docstring claims but never wrote.

Mobile: validator units; upload per role (asha PDF, clinician txt, admin, family
locked); one test per failure row above; mocked chain pick → upload 200 → list
shows the new document → answer cites it; list/QA states; 1.3 text-scale locks
for upload/documents/QA screens; updated patient-line assertions.

## Non-goals

Real-device camera scanning, family-caregiver upload, offline upload queueing,
document delete/rename, list pagination beyond the 50-row cap, any change to
`dashboard/`.

## STEP 4 design notes (not implemented)

**A. Scan-to-PDF.** A scanner plugin alone is *not* sufficient: native
scanners emit image-only PDFs and the backend has no OCR, so the upload would
400 with "No selectable text found". A working capture flow needs camera
capture + on-device OCR + a text-layer PDF:
- capture/auto-crop: `flutter_doc_scanner` (ML Kit Document Scanner on Android,
  VisionKit on iOS) — returns JPEG pages, or an image-only PDF
- OCR: `google_mlkit_text_recognition` (on-device, no network)
- compose: `pdf` (pure Dart) to build a selectable-text PDF pypdf can extract
- permissions added: Android `CAMERA` in the manifest (+ ML Kit metadata);
  iOS `NSCameraUsageDescription`; `permission_handler` macro
  `PERMISSION_CAMERA=1`; photo-library key only if gallery import is enabled
- cost: 3 new dependencies, native config on both platforms, app-size increase
- cheaper alternative: `image_picker` (camera) + the same OCR + `pdf` packages
- rejected: `mobile_scanner` (barcode/QR oriented, `returnImage` only)

**B. family_caregiver upload-only.** Needs one backend change, shown as a diff
before application: in `upload_medical_document` replace
`ensure_clinical_access(...)` with `ensure_patient_access(...)`, keep
`ensure_consent(..., 'health_data')`, keep `require_staff`, and add a write
audit (`ComplianceService.log_audit_access` is the existing helper — confirm
its signature before using). `documents/query` and `documents/answer` keep
`ensure_clinical_access`, so reading and RAG stay clinical-only. Mobile side
then un-locks the button for family caregivers and the client copy changes from
"health worker only" to a consent-dependent state.

## Risks

- `MedicalDocument.extracted_text` is encrypted at rest; the list must never
  return it.
- The 401 path logs out via `onUnauthorized` — the inline message must appear
  even though navigation may follow.
- The parallel backend session owns uncommitted backend files; this work edits
  only `backend/app/routes/reports.py` and new/updated test files, committed
  path-limited.

# Mobile document upload / RAG hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Staff (ASHA/clinician/admin) can pick a PDF or text file on mobile, upload it honestly, see it in a documents list, and ask a cited RAG question about it; family caregivers stay locked with a short explanation; every failure mode is visible.

**Architecture:** One new read-only backend endpoint returns document metadata (never `extracted_text`). The mobile app gains a `DocumentsScreen` hub (list + Upload + Ask), a `RagQaScreen`, client-side file validation mirroring the backend's 10 MB / PDF+text allowlist, and a status→message mapper so no failure is a bare code. A pure `validateDocumentFile` and a pure `formatDocumentUploadError` carry the logic; screens stay thin.

**Tech Stack:** Flutter (Dart), `http` multipart, `file_picker`; FastAPI + SQLAlchemy async (aiosqlite in tests); pytest + pytest-asyncio; `flutter_test` with `HttpOverrides` fake backends.

**Spec:** `docs/superpowers/specs/2026-09-24-mobile-document-upload-rag-hardening-design.md`

## Global Constraints

- Never touch the demo database. Backend tests use the in-memory SQLite fixture only; mobile tests use `HttpOverrides` fakes. Never run `api_live_test.dart` or `integration_test/`.
- No new mobile dependencies. Offline detection reuses the existing `ApiException('Network error: …')` wrapper.
- Client allowlist is exactly `pdf, txt, md, text, csv` (mirrors `document_extraction.py:14,25-31`); `doc`/`docx` are removed from the picker because the backend rejects them.
- Size cap is exactly `10 * 1024 * 1024` bytes (mirrors `MAX_UPLOAD_BYTES`).
- Server stays authoritative: the family lock is a client affordance driven by `summary['view'] == 'basic'`, never a security control.
- Uploads are never queued offline — no `OfflineSyncService`/`enqueueSyncItem` call may be added to the upload path.
- Existing copy must stay byte-stable where the port locked it: the consent lock copy in `documents_card.dart` and the consent failure copy on the upload screen.
- Every commit is path-limited: `git add <paths> && git commit -m "…" -- <paths>`. Never a bare `git commit`. A parallel user session has uncommitted work in the tree (45 entries) — never revert, stage, or commit foreign paths.
- `dashboard/` is not modified by this work.
- Text scale: any new screen must render at `textScaleFactor 1.3` on 390×844 without overflow; tap targets ≥48px; single column.
- Branch: `feat/mobile-documents-rag` (already created, contains the spec commit `8b0b76a`). No push.

## File Map

**Create**
- `backend/app/routes/reports.py` — modify only (add one GET route)
- `backend/app/tests/test_document_list.py` — list endpoint contract + role matrix + audit assertion
- `mobile/lib/services/document_validation.dart` — `kMaxDocumentBytes`, `kAllowedDocumentExtensions`, `validateDocumentFile`
- `mobile/lib/screens/documents_screen.dart` — `DocumentsScreen` hub (list + Upload + Ask)
- `mobile/lib/screens/rag_qa_screen.dart` — `RagQaScreen` (question/answer/citations)
- `mobile/test/document_validation_test.dart` — validator unit tests
- `mobile/test/documents_screen_test.dart` — list states, buttons, errors
- `mobile/test/rag_qa_screen_test.dart` — answer, citations, empty answer, errors
- `mobile/test/document_upload_hardening_test.dart` — per-role upload + per-failure-case tests
- `mobile/test/documents_e2e_test.dart` — pick → upload → list → cited answer

**Modify**
- `backend/app/routes/reports.py:183` (insert the GET route after `documents/answer`)
- `backend/app/tests/test_document_upload.py` — role matrix, 413, consent gate
- `mobile/lib/services/api_service.dart:27-35` (`isNetworkError`), `:588-633` (upload network normalization), `:634` (new methods)
- `mobile/lib/screens/rag_upload_screen.dart:120-127` (picker allowlist), `:135-213` (validation + failure mapping)
- `mobile/lib/screens/caregiver/sections/documents_card.dart` — `isClinical` + lock copy
- `mobile/lib/screens/caregiver_dashboard_screen.dart:255-266,315-327,417-421` (hub entry, icon gating, consent wiring)
- `mobile/lib/main.dart:385` — patient line
- `mobile/test/rag_upload_test.dart`, `mobile/test/caregiver_scale_test.dart`, `mobile/test/caregiver_role_routing_test.dart`, `mobile/test/shell_roles_test.dart` — assertions

---

### Task 1: Backend documents list endpoint

**Files:**
- Modify: `backend/app/routes/reports.py` (add route after `answer_medical_question`, line ~181)
- Create: `backend/app/tests/test_document_list.py`

**Interfaces:**
- Consumes: `ensure_clinical_access`, `ensure_consent`, `ComplianceService.log_read_access`, `MedicalDocument` model (fields `id, title, file_ref, doc_type, embedding_status, created_at`).
- Produces: `GET /api/v1/reports/patients/{patient_id}/documents` → `{"documents": [ {"document_id": str, "title": str|null, "file_name": str, "doc_type": str, "embedding_status": str, "created_at": str} ], "count": int}`

- [ ] **Step 1: Write the failing test file**

`backend/app/tests/test_document_list.py`:

```python
"""GET /reports/patients/{id}/documents — list metadata for a patient's RAG docs.

Read path must mirror documents/query: clinical tier + health_data consent,
DPDP read audit, metadata only (never extracted_text).
"""
import io

import pytest
from sqlalchemy import select

from app.models.all_models import AuditLog

AUTH = "/api/v1/auth"
PATIENTS = "/api/v1/patients"
REPORTS = "/api/v1/reports"


async def _staff_with_patient(client, role="clinician"):
    from app.tests.conftest import create_consented_patient, provision_staff_user

    user = await provision_staff_user(role=role)
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    assert login.status_code == 200, login.text
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    prof = await create_consented_patient(client, "List Patient")
    return h, prof["id"]


async def _upload_text(client, headers, pid, name="notes.txt"):
    up = await client.post(f"{REPORTS}/documents/upload?patient_id={pid}",
        headers=headers,
        files={"file": (name, io.BytesIO(
            b"Patient takes Donepezil 5 mg at bedtime for memory support."), "text/plain")},
        data={"doc_type": "prescription", "title": "List title"})
    assert up.status_code == 200, up.text
    return up.json()


@pytest.mark.asyncio
@pytest.mark.parametrize("role", ["clinician", "asha_worker", "admin"])
async def test_list_returns_metadata_newest_first(client, role):
    h, pid = await _staff_with_patient(client, role)
    await _upload_text(client, h, pid, "older.txt")
    await _upload_text(client, h, pid, "newer.txt")

    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["count"] == 2
    first = body["documents"][0]
    assert first["file_name"] == "newer.txt"
    assert first["title"] == "List title"
    assert first["doc_type"] == "prescription"
    assert first["embedding_status"] in ("pending", "processing", "completed", "failed")
    assert first["created_at"]
    # Metadata only — encrypted PHI must never be echoed.
    assert "extracted_text" not in first
    assert "embedding" not in first


@pytest.mark.asyncio
async def test_list_empty_is_not_an_error(client):
    h, pid = await _staff_with_patient(client)
    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200
    assert r.json() == {"documents": [], "count": 0}


@pytest.mark.asyncio
async def test_list_writes_read_audit(client, db_session):
    h, pid = await _staff_with_patient(client)
    await _upload_text(client, h, pid)
    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 200
    rows = (await db_session.execute(select(AuditLog).where(
        AuditLog.resource_type == "medical_document", AuditLog.action == "read"))).scalars().all()
    assert rows, "listing documents must write a DPDP read audit"


@pytest.mark.asyncio
async def test_list_family_caregiver_basic_tier_is_403(client):
    # Family caregiver linked at the default BASIC tier cannot read documents.
    reg = await client.post(f"{AUTH}/register", json={
        "phone": "+919000000001", "password": "Passw0rd123",
        "role": "family_caregiver", "preferred_language": "english"})
    assert reg.status_code == 201, reg.text
    fam = reg.json()
    fam_login = await client.post(f"{AUTH}/login", json={
        "phone": fam["phone"], "password": "Passw0rd123"})
    fh = {"Authorization": f"Bearer {fam_login.json()['access_token']}"}

    from app.tests.conftest import create_consented_patient
    prof = await create_consented_patient(client, "Family View Patient")
    pid = prof["id"]
    owner_login = await client.post(f"{AUTH}/login", json={
        "phone": prof["phone"], "password": "Passw0rd123"})
    oh = {"Authorization": f"Bearer {owner_login.json()['access_token']}"}
    link = await client.post(f"{PATIENTS}/{pid}/caregivers", headers=oh,
        json={"caregiver_id": fam["id"], "relationship_type": "family"})
    assert link.status_code == 201, link.text

    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=fh)
    assert r.status_code == 403
    assert r.json()["detail"] == "Clinical permission tier required for this resource"


@pytest.mark.asyncio
async def test_list_patient_role_is_403(client):
    from app.tests.conftest import create_consented_patient
    prof = await create_consented_patient(client, "Self Patient")
    pid = prof["id"]
    login = await client.post(f"{AUTH}/login", json={
        "phone": prof["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    r = await client.get(f"{REPORTS}/patients/{pid}/documents", headers=h)
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_list_without_health_data_consent_is_403(client):
    from app.tests.conftest import provision_staff_user
    user = await provision_staff_user(role="clinician")
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    # Patient created WITHOUT the default all-scope consent.
    reg = await client.post(f"{AUTH}/register", json={
        "phone": "+919000000002", "password": "Passw0rd123",
        "role": "patient", "preferred_language": "english"})
    pl = await client.post(f"{AUTH}/login", json={
        "phone": reg.json()["phone"], "password": "Passw0rd123"})
    ph = {"Authorization": f"Bearer {pl.json()['access_token']}"}
    prof = (await client.post(f"{PATIENTS}", headers=ph, json={"name": "No Consent"})).json()

    r = await client.get(f"{REPORTS}/patients/{prof['id']}/documents", headers=h)
    assert r.status_code == 403
    assert "health_data" in r.json()["detail"]
```

- [ ] **Step 2: Run to verify RED**

Run: `cd backend && python3 -m pytest app/tests/test_document_list.py -q`
Expected: FAIL — 404 (route does not exist).

- [ ] **Step 3: Implement the route**

In `backend/app/routes/reports.py`, add `MedicalDocument` and `select` imports (`from app.models.all_models import DocumentTypeEnum, MedicalDocument, User`; `from sqlalchemy import select`), then insert after `answer_medical_question`:

```python
@router.get("/patients/{patient_id}/documents")
async def list_patient_documents(
    patient_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_staff),
):
    """List a patient's ingested medical documents (metadata only).

    Same gates as the read/query paths — clinical tier, health_data consent,
    DPDP read audit. Never returns extracted_text (encrypted at rest).
    """
    await ensure_clinical_access(db, current_user, patient_id)
    await ensure_consent(db, patient_id, "health_data")
    await ComplianceService.log_read_access(db, current_user.id, "medical_document", str(patient_id))

    res = await db.execute(
        select(MedicalDocument)
        .where(MedicalDocument.patient_id == patient_id)
        .order_by(MedicalDocument.created_at.desc())
        .limit(50)
    )
    documents = [
        {
            "document_id": str(doc.id),
            "title": doc.title,
            "file_name": doc.file_ref,
            "doc_type": doc.doc_type.value if hasattr(doc.doc_type, "value") else str(doc.doc_type),
            "embedding_status": (
                doc.embedding_status.value
                if hasattr(doc.embedding_status, "value")
                else str(doc.embedding_status)
            ),
            "created_at": doc.created_at.isoformat() if doc.created_at else None,
        }
        for doc in res.scalars().all()
    ]
    return {"documents": documents, "count": len(documents)}
```

- [ ] **Step 4: Run to verify GREEN**

Run: `cd backend && python3 -m pytest app/tests/test_document_list.py -q`
Expected: PASS (7 tests: 3 parametrized + 4).

- [ ] **Step 5: Commit**

```bash
git add backend/app/routes/reports.py backend/app/tests/test_document_list.py
git commit -m "feat(reports): GET patient documents list (metadata only, clinical+consent gated)" -- backend/app/routes/reports.py backend/app/tests/test_document_list.py
```

---

### Task 2: Backend upload role matrix, 413, consent gate

**Files:**
- Modify: `backend/app/tests/test_document_upload.py` (append; no production change)

**Interfaces:**
- Consumes: existing `/documents/upload` behavior; `provision_staff_user`, `create_consented_patient`, `/auth/register` (patient + family_caregiver roles allowed, `auth.py:21`).
- Produces: regression locks for the security matrix this feature relies on.

- [ ] **Step 1: Append the failing tests**

Append to `backend/app/tests/test_document_upload.py`:

```python
async def _family_caregiver_for(client, patient_profile):
    reg = await client.post("/api/v1/auth/register", json={
        "phone": "+919100000001", "password": "Passw0rd123",
        "role": "family_caregiver", "preferred_language": "english"})
    assert reg.status_code == 201, reg.text
    fam = reg.json()
    login = await client.post("/api/v1/auth/login", json={
        "phone": fam["phone"], "password": "Passw0rd123"})
    fh = {"Authorization": f"Bearer {login.json()['access_token']}"}
    owner_login = await client.post("/api/v1/auth/login", json={
        "phone": patient_profile["phone"], "password": "Passw0rd123"})
    oh = {"Authorization": f"Bearer {owner_login.json()['access_token']}"}
    link = await client.post(f"/api/v1/patients/{patient_profile['id']}/caregivers",
        headers=oh, json={"caregiver_id": fam["id"], "relationship_type": "family"})
    assert link.status_code == 201, link.text
    return fh


@pytest.mark.asyncio
@pytest.mark.parametrize("role", ["asha_worker", "admin"])
async def test_upload_allowed_roles(client, role):
    from app.tests.conftest import create_consented_patient, provision_staff_user
    user = await provision_staff_user(role=role)
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    prof = await create_consented_patient(client, f"Upload {role}")
    pid = prof["id"]
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={pid}", headers=h,
        files={"file": ("a.txt", io.BytesIO(b"Metformin 500 mg twice daily."), "text/plain")})
    assert r.status_code == 200, r.text


@pytest.mark.asyncio
async def test_upload_family_caregiver_basic_tier_is_403(client):
    h, pid = await _clinician_with_patient(client)
    from app.tests.conftest import create_consented_patient
    prof = await create_consented_patient(client, "Family Upload Patient")
    fh = await _family_caregiver_for(client, prof)
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={prof['id']}", headers=fh,
        files={"file": ("a.txt", io.BytesIO(b"Metformin 500 mg."), "text/plain")})
    assert r.status_code == 403
    assert r.json()["detail"] == "Clinical permission tier required for this resource"


@pytest.mark.asyncio
async def test_upload_patient_role_is_403(client):
    from app.tests.conftest import create_consented_patient
    prof = await create_consented_patient(client, "Self Upload Patient")
    login = await client.post(f"{AUTH}/login", json={
        "phone": prof["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={prof['id']}", headers=h,
        files={"file": ("a.txt", io.BytesIO(b"Metformin 500 mg."), "text/plain")})
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_upload_oversized_is_413(client):
    h, pid = await _clinician_with_patient(client)
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={pid}", headers=h,
        files={"file": ("big.txt", io.BytesIO(b"x" * (10 * 1024 * 1024 + 1)), "text/plain")})
    assert r.status_code == 413
    assert "10 MB" in r.json()["detail"]


@pytest.mark.asyncio
async def test_upload_without_health_data_consent_is_403(client):
    from app.tests.conftest import provision_staff_user
    user = await provision_staff_user(role="clinician")
    login = await client.post(f"{AUTH}/login", json={
        "phone": user["phone"], "password": "Passw0rd123"})
    h = {"Authorization": f"Bearer {login.json()['access_token']}"}
    reg = await client.post(f"{AUTH}/register", json={
        "phone": "+919100000002", "password": "Passw0rd123",
        "role": "patient", "preferred_language": "english"})
    pl = await client.post(f"{AUTH}/login", json={
        "phone": reg.json()["phone"], "password": "Passw0rd123"})
    ph = {"Authorization": f"Bearer {pl.json()['access_token']}"}
    prof = (await client.post(f"{PATIENTS}", headers=ph, json={"name": "Upload No Consent"})).json()
    r = await client.post(f"{REPORTS}/documents/upload?patient_id={prof['id']}", headers=h,
        files={"file": ("a.txt", io.BytesIO(b"Metformin 500 mg."), "text/plain")})
    assert r.status_code == 403
    assert "health_data" in r.json()["detail"]
```

- [ ] **Step 2: Run the new tests**

Run: `cd backend && python3 -m pytest app/tests/test_document_upload.py -q`
Expected: PASS immediately (these lock existing behavior — disclose as contract locks, not RED). If any FAIL, the production behavior diverged from the spec: stop and report instead of editing production code in this task.

- [ ] **Step 3: Re-run the file to confirm the whole file is green**

Run: `cd backend && python3 -m pytest app/tests/test_document_upload.py -q`
Expected: PASS (all original + 5 new).

- [ ] **Step 4: Commit**

```bash
git add backend/app/tests/test_document_upload.py
git commit -m "test(reports): lock upload role matrix, 413 size cap, consent gate" -- backend/app/tests/test_document_upload.py
```

---

### Task 3: ApiService — network-error honesty, listDocuments, askDocumentQuestion

**Files:**
- Modify: `mobile/lib/services/api_service.dart:27-35` (getter), `:588-633` (upload try/catch), `:634` (new methods)
- Test: `mobile/test/api_caregiver_endpoints_test.dart` (append; reuse its `_FakeBackend`)

**Interfaces:**
- Consumes: `AppConfig.apiV1`, `_send`, `_decode`, `getJson`, `postJson`.
- Produces: `bool ApiException.isNetworkError`; `Future<List<Map<String, dynamic>>> ApiService.listDocuments(String patientId)`; `Future<Map<String, dynamic>> ApiService.askDocumentQuestion({required String patientId, required String question, int topK = 3})`; `ApiService.uploadDocument` now throws `ApiException` (not `SocketException`) on network failure.

- [ ] **Step 1: Append failing tests**

Append inside `void main()` of `mobile/test/api_caregiver_endpoints_test.dart`:

```dart
  group('network errors + documents read API', () {
    test('isNetworkError only for the wrapper, not HTTP failures', () {
      expect(ApiException('Network error: SocketException').isNetworkError, isTrue);
      expect(ApiException('boom', statusCode: 500).isNetworkError, isFalse);
      expect(ApiException('boom', statusCode: 403).isNetworkError, isFalse);
    });

    test('uploadDocument normalizes a thrown SocketException', () async {
      final backend = _FakeBackend((method, uri, body) {
        throw const SocketException('Failed host lookup');
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')..authToken = 'tok-1';
      await expectLater(
        api.uploadDocument(
          patientId: 'p1',
          bytes: Uint8List.fromList([1]),
          filename: 'a.txt',
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', isTrue)),
      );
    });

    test('listDocuments GETs the list route and returns rows', () async {
      final backend = _FakeBackend((method, uri, body) {
        expect(method, 'GET');
        expect(uri.path, '/api/v1/reports/patients/p1/documents');
        return (
          status: 200,
          json: {
            'documents': [
              {
                'document_id': 'd1',
                'title': 'Discharge summary',
                'file_name': 'discharge.txt',
                'doc_type': 'prescription',
                'embedding_status': 'completed',
                'created_at': '2026-09-24T10:00:00',
              }
            ],
            'count': 1,
          }
        );
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')..authToken = 'tok-1';
      final docs = await api.listDocuments('p1');
      expect(docs, hasLength(1));
      expect(docs.single['file_name'], 'discharge.txt');
    });

    test('askDocumentQuestion POSTs the question and returns the answer map',
        () async {
      final backend = _FakeBackend((method, uri, body) {
        expect(method, 'POST');
        expect(uri.path, '/api/v1/reports/documents/answer');
        final payload = jsonDecode(body) as Map<String, dynamic>;
        expect(payload['patient_id'], 'p1');
        expect(payload['question'], 'What medication was prescribed?');
        return (
          status: 200,
          json: {
            'question': payload['question'],
            'answer': 'Donepezil 5 mg at bedtime [1].',
            'synthesized': false,
            'citations': [
              {'title': 'Discharge summary', 'file_ref': 'discharge.txt', 'similarity': 0.82}
            ],
            'disclaimer': 'Not medical advice.',
          }
        );
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')..authToken = 'tok-1';
      final result = await api.askDocumentQuestion(
        patientId: 'p1',
        question: 'What medication was prescribed?',
      );
      expect(result['synthesized'], isFalse);
      expect((result['citations'] as List), hasLength(1));
    });
  });
```

- [ ] **Step 2: Run to verify RED**

Run: `cd mobile && flutter test test/api_caregiver_endpoints_test.dart`
Expected: FAIL — `isNetworkError` undefined, `listDocuments` undefined, `askDocumentQuestion` undefined, and the upload test failing with `SocketException` (not `ApiException`).

- [ ] **Step 3: Implement**

In `mobile/lib/services/api_service.dart`:

1. Inside `class ApiException` (after `ApiException(this.message, {this.statusCode});`):

```dart
  /// True when the failure came from the network layer, not the server.
  /// `_send` wraps transport failures as 'Network error: …' (api_service.dart:124).
  bool get isNetworkError =>
      statusCode == null && message.startsWith('Network error');
```

2. In `uploadDocument`, wrap both send attempts so a transport failure becomes an `ApiException` like every other API call:

```dart
    http.Response res;
    try {
      var streamed = await build().send();
      res = await http.Response.fromStream(streamed);
      // One refresh attempt on 401, then retry the original request
      // (mirrors _send; rebuild required — a sent request cannot re-stream).
      if (res.statusCode == 401 && refreshToken != null) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          streamed = await build().send();
          res = await http.Response.fromStream(streamed);
        }
      }
    } on Exception catch (e) {
      developer.log('upload failed: $e', name: 'ApiService');
      throw ApiException('Network error: $e');
    }
```

3. After `uploadDocument` (end of class), add:

```dart
  /// GET /reports/patients/{id}/documents — ingested document metadata for
  /// the documents hub. 403 (tier/consent) surfaces as ApiException; the
  /// caller decides the state.
  Future<List<Map<String, dynamic>>> listDocuments(String patientId) async {
    final data = await getJson(
        '${AppConfig.apiV1}/reports/patients/$patientId/documents');
    final rows = (data as Map<String, dynamic>)['documents'] as List? ?? const [];
    return rows.cast<Map<String, dynamic>>();
  }

  /// POST /reports/documents/answer — cited answer grounded in the patient's
  /// documents. Never a diagnosis; returns the server's disclaimer verbatim.
  Future<Map<String, dynamic>> askDocumentQuestion({
    required String patientId,
    required String question,
    int topK = 3,
  }) async {
    final data = await postJson(
      '${AppConfig.apiV1}/reports/documents/answer',
      body: {'patient_id': patientId, 'question': question, 'top_k': topK},
    );
    if (data is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(data);
  }
```

- [ ] **Step 4: Run to verify GREEN**

Run: `cd mobile && flutter test test/api_caregiver_endpoints_test.dart test/rag_upload_test.dart`
Expected: PASS (existing upload/refresh tests must stay green).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/services/api_service.dart mobile/test/api_caregiver_endpoints_test.dart
git commit -m "feat(documents): ApiService listDocuments + askDocumentQuestion + network-error honesty" -- mobile/lib/services/api_service.dart mobile/test/api_caregiver_endpoints_test.dart
```

---

### Task 4: Client-side file validation + picker allowlist

**Files:**
- Create: `mobile/lib/services/document_validation.dart`
- Modify: `mobile/lib/screens/rag_upload_screen.dart:120-127` (picker), `:107-118` (`_pickFile`), `:135-146` (`_upload` guard)
- Test: `mobile/test/document_validation_test.dart` (create), `mobile/test/rag_upload_picker_test.dart` (append)

**Interfaces:**
- Consumes: nothing (pure Dart).
- Produces: `kMaxDocumentBytes` (int), `kAllowedDocumentExtensions` (Set<String>), `String? validateDocumentFile({required String filename, required int byteLength})`.

- [ ] **Step 1: Write the failing unit test**

`mobile/test/document_validation_test.dart`:

```dart
import 'package:eldercare_mobile/services/document_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateDocumentFile', () {
    for (final name in const ['note.pdf', 'notes.TXT', 'plan.md', 'log.text', 'rows.csv']) {
      test('accepts $name', () {
        expect(validateDocumentFile(filename: name, byteLength: 1024), isNull);
      });
    }

    for (final name in const ['scan.png', 'sheet.xlsx', 'note.doc', 'note.docx', 'noext']) {
      test('rejects $name with a type message', () {
        final msg = validateDocumentFile(filename: name, byteLength: 1024);
        expect(msg, isNotNull);
        expect(msg, contains("isn't supported"));
      });
    }

    test('rejects empty file', () {
      expect(validateDocumentFile(filename: 'a.txt', byteLength: 0),
          contains('empty'));
    });

    test('rejects over 10 MB', () {
      final msg = validateDocumentFile(
          filename: 'a.txt', byteLength: 10 * 1024 * 1024 + 1);
      expect(msg, contains('10 MB'));
    });

    test('accepts exactly 10 MB', () {
      expect(
          validateDocumentFile(
              filename: 'a.txt', byteLength: 10 * 1024 * 1024),
          isNull);
    });
  });
}
```

- [ ] **Step 2: Run to verify RED**

Run: `cd mobile && flutter test test/document_validation_test.dart`
Expected: FAIL — import of `document_validation.dart` does not exist.

- [ ] **Step 3: Implement the validator**

`mobile/lib/services/document_validation.dart`:

```dart
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
```

- [ ] **Step 4: Wire it into the upload screen**

In `mobile/lib/screens/rag_upload_screen.dart`:

1. Add `import '../services/document_validation.dart';`
2. Replace `_pickWithFilePicker`'s `allowedExtensions` with the shared set (sorted for a stable platform dialog):

```dart
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: kAllowedDocumentExtensions.toList()..sort(),
    );
```

3. In `_pickFile`, validate before storing the file (rejected picks leave the previous selection untouched and show the reason):

```dart
  Future<void> _pickFile() async {
    final picked = widget.pickForTest != null
        ? await widget.pickForTest!()
        : await _pickWithFilePicker();
    if (picked == null || !mounted) return;
    final problem = validateDocumentFile(
      filename: picked.filename,
      byteLength: picked.bytes.length,
    );
    if (problem != null) {
      setState(() => _result = problem);
      return;
    }
    setState(() {
      _pickedBytes = picked.bytes;
      _pickedFilename = picked.filename;
      _filePath = picked.filename;
      _result = null;
    });
  }
```

4. In `_upload`, after resolving `bytes`/`filename` and before the send branches:

```dart
      final problem =
          validateDocumentFile(filename: filename, byteLength: bytes.length);
      if (problem != null) {
        setState(() {
          _uploading = false;
          _result = problem;
        });
        return;
      }
```

- [ ] **Step 5: Add the widget test for pick-time rejection**

Append to `mobile/test/rag_upload_picker_test.dart` (inside `void main()`):

```dart
  testWidgets('pick of a rejected type shows the type message, Upload stays off',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        pickForTest: () async => (
          bytes: Uint8List.fromList(utf8.encode('binary-ish')),
          filename: 'scan.png',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SELECT FILE'));
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't supported"), findsOneWidget);
    expect(find.text('No file selected.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'UPLOAD ▸')).onPressed,
      isNull,
    );
  });

  testWidgets('pick over 10 MB is rejected before any request', (tester) async {
    var hitBackend = false;
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        pickForTest: () async => (
          bytes: Uint8List(10 * 1024 * 1024 + 1),
          filename: 'big.txt',
        ),
        sendForTest: (req) async {
          hitBackend = true;
          return http.Response('', 200);
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SELECT FILE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('10 MB'), findsOneWidget);
    expect(hitBackend, isFalse);
  });
```

- [ ] **Step 6: Run to verify GREEN**

Run: `cd mobile && flutter test test/document_validation_test.dart test/rag_upload_picker_test.dart test/rag_upload_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/services/document_validation.dart mobile/lib/screens/rag_upload_screen.dart mobile/test/document_validation_test.dart mobile/test/rag_upload_picker_test.dart
git commit -m "feat(documents): client pre-flight type/size validation aligned with the backend allowlist" -- mobile/lib/services/document_validation.dart mobile/lib/screens/rag_upload_screen.dart mobile/test/document_validation_test.dart mobile/test/rag_upload_picker_test.dart
```

---

### Task 5: Honest failure messages on the upload screen

**Files:**
- Modify: `mobile/lib/screens/rag_upload_screen.dart:49-67` (`formatDocumentUploadError`), `:192-212` (catch branch), `:157-178` (sendForTest branch)
- Test: `mobile/test/document_upload_hardening_test.dart` (create)

**Interfaces:**
- Consumes: `ApiException.isNetworkError` (Task 3), `formatRagUploadFailure` (existing, consent copy must stay byte-stable).
- Produces: `String formatDocumentUploadError(ApiException e)`; the screen renders it for every `ApiException`, and maps `sendForTest` responses for 401/413/429.

- [ ] **Step 1: Write the failing unit tests + one widget test**

`mobile/test/document_upload_hardening_test.dart`:

```dart
import 'dart:convert';

import 'package:eldercare_mobile/screens/rag_upload_screen.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('formatDocumentUploadError', () {
    test('network error → offline copy', () {
      expect(
        formatDocumentUploadError(ApiException('Network error: SocketException')),
        "You're offline — try again when connected.",
      );
    });

    test('401 → session expired', () {
      expect(
        formatDocumentUploadError(ApiException('nope', statusCode: 401)),
        'Session expired — sign in again.',
      );
    });

    test('413 → size copy', () {
      expect(
        formatDocumentUploadError(
            ApiException('File exceeds the 10 MB limit.', statusCode: 413)),
        contains('10 MB'),
      );
    });

    test('429 → rate-limit copy', () {
      expect(
        formatDocumentUploadError(ApiException('slow down', statusCode: 429)),
        'Rate limit reached — wait a minute and try again.',
      );
    });

    test('403 tier → health-worker copy, no consent claim', () {
      final msg = formatDocumentUploadError(ApiException(
        'Clinical permission tier required for this resource',
        statusCode: 403,
      ));
      expect(msg, contains("can't add health documents"));
      expect(msg, isNot(contains('health_data consent required')));
    });

    test('403 consent keeps the port-locked consent copy', () {
      final msg = formatDocumentUploadError(ApiException(
        "Active consent required for scope 'health_data'",
        statusCode: 403,
      ));
      expect(msg, contains("scope 'health_data'"));
      expect(msg, contains('Upload failed'));
    });

    test('400 → server detail passthrough', () {
      expect(
        formatDocumentUploadError(ApiException(
            "Unsupported file type '.png'. Upload a PDF or text file.",
            statusCode: 400)),
        contains('Unsupported file type'),
      );
    });
  });

  testWidgets('offline live upload shows offline copy and never queues',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        testBytes: Uint8List.fromList(utf8.encode('hi')),
        testFilename: 'note.txt',
      ),
    ));
    await tester.pumpAndSettle();
    ApiService.instance.baseUrl = 'http://127.0.0.1:9'; // closed port → network error
    addTearDown(() => ApiService.instance.baseUrl = 'http://localhost:8000');

    await tester.tap(find.text('UPLOAD ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('sendForTest 429 shows the rate-limit copy', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        testBytes: Uint8List.fromList(utf8.encode('hi')),
        testFilename: 'note.txt',
        sendForTest: (req) async => http.Response(
          jsonEncode({'detail': 'rate limit'}),
          429,
          headers: const {'Content-Type': 'application/json'},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UPLOAD ▸'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rate limit reached'), findsOneWidget);
  });
}
```

Add `import 'dart:typed_data';` to that file.

- [ ] **Step 2: Run to verify RED**

Run: `cd mobile && flutter test test/document_upload_hardening_test.dart`
Expected: FAIL — `formatDocumentUploadError` undefined; 429 widget test shows the old generic copy.

- [ ] **Step 3: Implement the mapper**

In `mobile/lib/screens/rag_upload_screen.dart`, after `formatRagUploadFailure`:

```dart
/// Single source of truth for upload failures: offline, expired session, size,
/// rate limit, clinical tier, consent, and pass-through details. Never a bare
/// code. The 403-consent path delegates to [formatRagUploadFailure] so the
/// port-locked consent copy stays byte-identical.
@visibleForTesting
String formatDocumentUploadError(ApiException e) {
  if (e.isNetworkError) return "You're offline — try again when connected.";
  switch (e.statusCode) {
    case 401:
      return 'Session expired — sign in again.';
    case 413:
      return 'That file is over the 10 MB limit — choose a smaller file.';
    case 429:
      return 'Rate limit reached — wait a minute and try again.';
    case 403:
      if (e.message.contains('health_data')) {
        return formatRagUploadFailure(403, e.message);
      }
      return "Your account can't add health documents. "
          'A health worker — ASHA worker, clinician, or admin — can.';
  }
  return 'Upload failed: ${e.message}';
}
```

- [ ] **Step 4: Route both failure paths through it**

1. In the `on ApiException catch (e)` branch, replace the `_result` assignment with:

```dart
      setState(() {
        _uploading = false;
        if (consentMissing) _consentMissing = true;
        _result = formatDocumentUploadError(e);
      });
```

2. In the `sendForTest` branch, replace the ternary with an explicit mapper so 401/413/429 are honest there too (the consent copy path is unchanged):

```dart
        final body403 =
            res.statusCode == 403 && res.body.contains('health_data');
        setState(() {
          _uploading = false;
          if (consentMissing) _consentMissing = true;
          if (res.statusCode >= 200 && res.statusCode < 300) {
            _result = 'Uploaded successfully (HTTP ${res.statusCode}).';
          } else if (res.statusCode == 401) {
            _result = 'Session expired — sign in again.';
          } else if (res.statusCode == 413) {
            _result = 'That file is over the 10 MB limit — choose a smaller file.';
          } else if (res.statusCode == 429) {
            _result = 'Rate limit reached — wait a minute and try again.';
          } else {
            _result = formatRagUploadFailure(res.statusCode, res.body);
          }
        });
```

- [ ] **Step 5: Run to verify GREEN**

Run: `cd mobile && flutter test test/document_upload_hardening_test.dart test/rag_upload_test.dart test/rag_upload_picker_test.dart test/api_caregiver_endpoints_test.dart`
Expected: PASS. If the port-locked consent copy assertion in `rag_upload_test.dart` fails, the delegation above is wrong — fix the mapper, never the locked copy.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/screens/rag_upload_screen.dart mobile/test/document_upload_hardening_test.dart
git commit -m "fix(documents): honest upload failure copy (offline, 401, 413, 429, tier vs consent)" -- mobile/lib/screens/rag_upload_screen.dart mobile/test/document_upload_hardening_test.dart
```

---

### Task 6: DocumentsScreen hub

**Files:**
- Create: `mobile/lib/screens/documents_screen.dart`
- Test: `mobile/test/documents_screen_test.dart` (create)

**Interfaces:**
- Consumes: `ApiService.listDocuments` (Task 3), `formatDocumentUploadError` (Task 5), `RagUploadScreen`, theme tokens `Monad.parchment, Monad.offBlack, Monad.ash, Monad.smoke, Monad.tintGold, Monad.tintMint, Monad.radiusCard, Monad.radiusMin, Monad.cardShape, Monad.subheading, Monad.monoLabel, Monad.monoBody, Monad.monoBodySm`, `MonadPillButton(label:, variant:, onPressed:)`.
- Produces: `class DocumentsScreen extends StatefulWidget { const DocumentsScreen({super.key, required this.patientId, this.onConsentMissing}); final String patientId; final VoidCallback? onConsentMissing; }`

- [ ] **Step 1: Write the failing tests**

`mobile/test/documents_screen_test.dart` — copy the `_FakeBackend` scaffold (lines 20-168 of `mobile/test/rag_upload_test.dart`) verbatim, then:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:eldercare_mobile/screens/documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final twoDocs = {
    'documents': [
      {
        'document_id': 'd1',
        'title': 'Discharge summary',
        'file_name': 'discharge.txt',
        'doc_type': 'prescription',
        'embedding_status': 'completed',
        'created_at': '2026-09-24T10:00:00',
      },
      {
        'document_id': 'd2',
        'title': 'Care plan',
        'file_name': 'care.pdf',
        'doc_type': 'report',
        'embedding_status': 'pending',
        'created_at': '2026-09-23T09:00:00',
      },
    ],
    'count': 2,
  };

  testWidgets('lists documents with title, file name and status',
      (tester) async {
    final backend = _FakeBackend((method, uri, body) {
      if (uri.path == '/api/v1/reports/patients/p1/documents') {
        return (status: 200, json: twoDocs);
      }
      return (status: 404, json: {'detail': 'not found'});
    });
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(
        const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    expect(find.text('Discharge summary'), findsOneWidget);
    expect(find.text('discharge.txt'), findsOneWidget);
    expect(find.textContaining('completed'), findsOneWidget);
    expect(find.text('UPLOAD DOCUMENT'), findsOneWidget);
    expect(find.text('ASK ABOUT DOCUMENTS'), findsOneWidget);
  });

  testWidgets('empty list shows the empty state, not an error',
      (tester) async {
    final backend = _FakeBackend((method, uri, body) =>
        (status: 200, json: {'documents': [], 'count': 0}));
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(
        const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No documents yet'), findsOneWidget);
  });

  testWidgets('403 clinical tier renders the health-worker lock copy',
      (tester) async {
    final backend = _FakeBackend((method, uri, body) => (
      status: 403,
      json: {
        'detail': 'Clinical permission tier required for this resource'
      }
    ));
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(
        const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Health worker only'), findsOneWidget);
    expect(find.text('UPLOAD DOCUMENT'), findsNothing);
    expect(find.text('ASK ABOUT DOCUMENTS'), findsNothing);
  });

  testWidgets('403 consent renders the consent copy and fires onConsentMissing',
      (tester) async {
    var consentFired = false;
    final backend = _FakeBackend((method, uri, body) => (
      status: 403,
      json: {'detail': "Active consent required for scope 'health_data'"}
    ));
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(MaterialApp(
      home: DocumentsScreen(
        patientId: 'p1',
        onConsentMissing: () => consentFired = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(consentFired, isTrue);
    expect(find.textContaining('health_data consent required'), findsOneWidget);
  });

  testWidgets('offline shows offline notice with retry', (tester) async {
    final backend = _FakeBackend((method, uri, body) => throw
        const SocketException('Failed host lookup'));
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(
        const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify RED**

Run: `cd mobile && flutter test test/documents_screen_test.dart`
Expected: FAIL — `documents_screen.dart` does not exist.

- [ ] **Step 3: Implement the screen**

`mobile/lib/screens/documents_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';
import 'rag_qa_screen.dart';
import 'rag_upload_screen.dart';

/// Documents hub for one patient: what is on file, plus the upload and
/// RAG-question entry points. Read and write are clinical-tier server-side;
/// this screen mirrors the server's answer instead of guessing.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    required this.patientId,
    this.onConsentMissing,
  });

  final String patientId;
  final VoidCallback? onConsentMissing;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  List<Map<String, dynamic>>? _documents;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await ApiService.instance.listDocuments(widget.patientId);
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 403) widget.onConsentMissing?.call();
      if (!mounted) return;
      setState(() {
        _error = e.isNetworkError
            ? "You're offline — try again when connected."
            : (e.statusCode == 403 && e.message.contains('health_data')
                ? "health_data consent required — this patient has not granted consent for health data, so documents can't be viewed until they do."
                : (e.statusCode == 403
                    ? 'Health worker only — family caregiver accounts can\'t add or read health documents. Ask an ASHA worker, clinician, or admin.'
                    : 'Could not load documents: ${e.message}'));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load documents: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openUpload() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RagUploadScreen(
        patientId: widget.patientId,
        onConsentMissing: widget.onConsentMissing,
      ),
    ));
    if (mounted) await _load();
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // Hand-rolled so no locale data initialization is needed in widget tests.
  String _date(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final locked = _error != null && _error!.startsWith('Health worker only');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medical Documents'),
        backgroundColor: Monad.parchment,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: locked ? Monad.tintGold : Monad.tintMint,
                  borderRadius: BorderRadius.circular(Monad.radiusMin),
                  border: Border.all(color: Monad.ash, width: 1),
                ),
                child: Row(children: [
                  Icon(locked ? Icons.lock_outline : Icons.cloud_off,
                      size: 22, color: Monad.graphite),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(_error!, style: Monad.monoBodySm)),
                ]),
              ),
              if (!locked) ...[
                const SizedBox(height: 12),
                MonadPillButton(label: 'Retry', onPressed: _load),
              ],
            ] else if (_documents!.isEmpty)
              Text('No documents yet. Upload a prescription, discharge summary, or care plan.',
                  style: Monad.monoBody)
            else ...[
              for (final doc in _documents!)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Monad.parchment,
                    borderRadius: BorderRadius.circular(Monad.radiusMin),
                    border: Border.all(color: Monad.ash, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc['title']?.toString() ?? 'Medical Document',
                          style: Monad.subheading),
                      const SizedBox(height: 4),
                      Text('${doc['file_name'] ?? ''} · ${_date(doc['created_at']?.toString())}',
                          style: Monad.monoBodySm),
                      const SizedBox(height: 4),
                      Text(
                        '${doc['doc_type'] ?? ''} · ${doc['embedding_status'] ?? ''}',
                        style: Monad.monoCaption,
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (!locked) ...[
              MonadPillButton(
                label: 'Upload Document',
                variant: MonadPillVariant.secondary,
                onPressed: _openUpload,
              ),
              const SizedBox(height: 8),
              MonadPillButton(
                label: 'Ask About Documents',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RagQaScreen(patientId: widget.patientId),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Create the QA screen stub so Task 6 compiles**

Create `mobile/lib/screens/rag_qa_screen.dart` with the final class shape and a placeholder-free minimal body that Task 7 replaces:

```dart
import 'package:flutter/material.dart';

class RagQaScreen extends StatelessWidget {
  const RagQaScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Loading…')),
      );
}
```

- [ ] **Step 5: Run to verify GREEN**

Run: `cd mobile && flutter test test/documents_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/screens/documents_screen.dart mobile/lib/screens/rag_qa_screen.dart mobile/test/documents_screen_test.dart
git commit -m "feat(documents): DocumentsScreen hub (list, upload and ask entry points, honest states)" -- mobile/lib/screens/documents_screen.dart mobile/lib/screens/rag_qa_screen.dart mobile/test/documents_screen_test.dart
```

---

### Task 7: RagQaScreen

**Files:**
- Modify: `mobile/lib/screens/rag_qa_screen.dart` (full implementation)
- Test: `mobile/test/rag_qa_screen_test.dart` (create)

**Interfaces:**
- Consumes: `ApiService.askDocumentQuestion` (Task 3), theme tokens as Task 6.
- Produces: `class RagQaScreen extends StatefulWidget { const RagQaScreen({super.key, required this.patientId}); final String patientId; }`

- [ ] **Step 1: Write the failing tests**

`mobile/test/rag_qa_screen_test.dart` — copy the `_FakeBackend` scaffold again, then:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:eldercare_mobile/screens/rag_qa_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _FakeBackend answerBackend(String answer, List<Map<String, dynamic>> cites) =>
      _FakeBackend((method, uri, body) {
        if (uri.path == '/api/v1/reports/documents/answer') {
          return (
            status: 200,
            json: {
              'question': 'What medication?',
              'answer': answer,
              'synthesized': false,
              'citations': cites,
              'disclaimer': 'Not medical advice — consult the treating clinician.',
            }
          );
        }
        return (status: 404, json: {'detail': 'not found'});
      });

  testWidgets('answer renders with numbered citations and disclaimer',
      (tester) async {
    HttpOverrides.global = answerBackend('Donepezil 5 mg at bedtime [1].', [
      {
        'title': 'Discharge summary',
        'file_ref': 'discharge.txt',
        'similarity': 0.82,
      }
    ]);
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(const MaterialApp(home: RagQaScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'What medication?');
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Donepezil 5 mg'), findsOneWidget);
    expect(find.textContaining('[1] Discharge summary'), findsOneWidget);
    expect(find.textContaining('Not medical advice'), findsOneWidget);
  });

  testWidgets('"no relevant records" is an answer, not an error',
      (tester) async {
    HttpOverrides.global = answerBackend(
        'No relevant records found for this patient to answer the question.',
        []);
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(const MaterialApp(home: RagQaScreen(patientId: 'p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'What medication?');
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No relevant records'), findsOneWidget);
  });

  testWidgets('empty question is refused client-side', (tester) async {
    var called = false;
    HttpOverrides.global = _FakeBackend((method, uri, body) {
      called = true;
      return (status: 200, json: {'answer': 'x', 'citations': []});
    });
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(const MaterialApp(home: RagQaScreen(patientId: 'p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Type a question first'), findsOneWidget);
    expect(called, isFalse);
  });

  testWidgets('403 consent surfaces the consent copy', (tester) async {
    HttpOverrides.global = _FakeBackend((method, uri, body) => (
      status: 403,
      json: {'detail': "Active consent required for scope 'health_data'"}
    ));
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(const MaterialApp(home: RagQaScreen(patientId: 'p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'What medication?');
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining("scope 'health_data'"), findsOneWidget);
  });

  testWidgets('offline shows the offline copy', (tester) async {
    HttpOverrides.global = _FakeBackend((method, uri, body) =>
        throw const SocketException('Failed host lookup'));
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(const MaterialApp(home: RagQaScreen(patientId: 'p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'What medication?');
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify RED**

Run: `cd mobile && flutter test test/rag_qa_screen_test.dart`
Expected: FAIL — the stub has no `TextField` and no `ASK ▸`.

- [ ] **Step 3: Implement the screen**

`mobile/lib/screens/rag_qa_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';

/// Ask a question grounded in a patient's uploaded documents. The server
/// returns an answer with citations and a disclaimer; this screen shows both
/// verbatim and never presents the answer as a diagnosis.
class RagQaScreen extends StatefulWidget {
  const RagQaScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<RagQaScreen> createState() => _RagQaScreenState();
}

class _RagQaScreenState extends State<RagQaScreen> {
  final _controller = TextEditingController();
  Map<String, dynamic>? _result;
  String? _error;
  bool _asking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty) {
      setState(() => _error = 'Type a question first.');
      return;
    }
    setState(() {
      _asking = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ApiService.instance
          .askDocumentQuestion(patientId: widget.patientId, question: question);
      if (!mounted) return;
      setState(() {
        _result = result;
        _asking = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _asking = false;
        _error = e.isNetworkError
            ? "You're offline — try again when connected."
            : (e.statusCode == 403
                ? "You can't ask about these documents — a health worker with clinical access can."
                : 'Could not get an answer: ${e.message}');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _asking = false;
        _error = 'Could not get an answer: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final citations = (result?['citations'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask About Documents'),
        backgroundColor: Monad.parchment,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Answers come only from this patient\'s uploaded documents.',
                style: Monad.monoBody),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 3,
              minLines: 2,
              style: Monad.monoBody,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. What medication was prescribed?',
              ),
            ),
            const SizedBox(height: 12),
            MonadPillButton(
              label: _asking ? 'Asking…' : 'Ask',
              onPressed: _asking ? null : _ask,
              busy: _asking,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Monad.tintGold,
                  borderRadius: BorderRadius.circular(Monad.radiusMin),
                  border: Border.all(color: Monad.ash, width: 1),
                ),
                child: Text(_error!, style: Monad.monoBodySm),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Text('Answer', style: Monad.subheading),
              const SizedBox(height: 6),
              Text(result['answer']?.toString() ?? '', style: Monad.monoBody),
              if (citations.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Sources', style: Monad.monoLabel),
                const SizedBox(height: 6),
                for (var i = 0; i < citations.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '[${i + 1}] ${citations[i]['title'] ?? citations[i]['file_ref'] ?? 'document'}'
                      '${citations[i]['similarity'] != null ? ' · similarity ${citations[i]['similarity']}' : ''}',
                      style: Monad.monoBodySm,
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Text(result['disclaimer']?.toString() ?? '',
                  style: Monad.monoCaption),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify GREEN**

Run: `cd mobile && flutter test test/rag_qa_screen_test.dart test/documents_screen_test.dart`
Expected: PASS (5 + 5).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/screens/rag_qa_screen.dart mobile/test/rag_qa_screen_test.dart
git commit -m "feat(documents): RagQaScreen with cited answers and server disclaimer" -- mobile/lib/screens/rag_qa_screen.dart mobile/test/rag_qa_screen_test.dart
```

---

### Task 8: family_caregiver lock + entry-point wiring

**Files:**
- Modify: `mobile/lib/screens/caregiver/sections/documents_card.dart` (add `isClinical`, lock state)
- Modify: `mobile/lib/screens/caregiver_dashboard_screen.dart:312-327` (icon gating + consent wiring), `:417-421` (pass `isClinical`), `:255-266` (`_openUpload` unchanged; add `_openDocuments`)
- Test: `mobile/test/rag_upload_test.dart` (append card lock test), `mobile/test/caregiver_role_routing_test.dart` (append family-cg lock test)

**Interfaces:**
- Consumes: `summary['view'] == 'clinical'`, `AuthSession.instance.user?.role`, `DocumentsScreen` (Task 6).
- Produces: `DocumentsCard({required patientId, required consentMissing, required isClinical, required onUpload, this.onOpenHub})`; `_openDocuments()` on the dashboard.

- [ ] **Step 1: Append the failing tests**

To `mobile/test/rag_upload_test.dart` (inside `void main()`):

```dart
  testWidgets('DocumentsCard basic view renders the health-worker lock, no button',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DocumentsCard(
          patientId: 'p1',
          consentMissing: false,
          isClinical: false,
          onUpload: null,
        ),
      ),
    ));

    expect(find.textContaining('Health worker only'), findsOneWidget);
    expect(find.text('UPLOAD DOCUMENT'), findsNothing);
  });
```

To `mobile/test/caregiver_role_routing_test.dart` (inside `void main()`): copy the existing `family_caregiver → dashboard (basic: no screening button)` test's harness (seed role `family_caregiver`, fake backend returning `view: basic`) and add:

```dart
    // Documents are clinical-only: a family caregiver sees the lock, not a
    // live Upload button, and the app-bar upload icon is hidden.
    expect(find.textContaining('Health worker only'), findsOneWidget);
    expect(find.text('UPLOAD DOCUMENT'), findsNothing);
    expect(find.byIcon(Icons.upload_file_outlined), findsNothing);
```

(Add `import 'package:flutter/material.dart';` only if the file does not already import it.)

- [ ] **Step 2: Run to verify RED**

Run: `cd mobile && flutter test test/rag_upload_test.dart test/caregiver_role_routing_test.dart`
Expected: FAIL — `isClinical` is not a parameter yet and the family dashboard still shows the button.

- [ ] **Step 3: Implement the card lock**

In `mobile/lib/screens/caregiver/sections/documents_card.dart`:

1. Add `required this.isClinical` and `this.onOpenHub` to the constructor with the fields `final bool isClinical; final VoidCallback? onOpenHub;`
2. In `build`, wrap the existing states: render the consent lock first, then `isClinical == false` lock, then the normal text; render the Upload button only when `isClinical`, and add a hub button when `onOpenHub != null`:

```dart
            if (consentMissing)
              // …existing consent lock container unchanged…
            else if (!isClinical)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Monad.tintGold,
                  borderRadius: BorderRadius.circular(Monad.radiusMin),
                  border: Border.all(color: Monad.ash, width: 1),
                ),
                child: const Row(children: [
                  Icon(Icons.lock_outline, size: 22, color: Monad.graphite),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Health worker only — family caregiver accounts can't add or read health documents. Ask an ASHA worker, clinician, or admin.",
                      style: Monad.monoBodySm,
                    ),
                  ),
                ]),
              )
            else
              const Text(/* existing helper copy unchanged */),
            const SizedBox(height: 16),
            if (isClinical && onUpload != null)
              MonadPillButton(
                label: 'Upload Document',
                variant: MonadPillVariant.secondary,
                onPressed: onUpload,
              ),
            if (isClinical && onOpenHub != null) ...[
              const SizedBox(height: 8),
              MonadPillButton(label: 'Documents & Q&A', onPressed: onOpenHub),
            ],
```

- [ ] **Step 4: Wire the dashboard**

In `mobile/lib/screens/caregiver_dashboard_screen.dart`:

1. Import `documents_screen.dart`.
2. Add next to `_openUpload`:

```dart
  /// Documents hub for the selected patient (list + upload + RAG questions).
  Future<void> _openDocuments() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentsScreen(
          patientId: _selectedPatientId!,
          onConsentMissing: () {
            if (mounted) setState(() => _consentMissing = true);
          },
        ),
      ),
    );
  }
```

3. Gate the app-bar upload icon on clinical view and wire its consent callback:

```dart
          if (_selectedPatientId != null &&
              _summary?['view'] == 'clinical')
            IconButton(
              tooltip: 'Upload medical document',
              icon: const Icon(Icons.upload_file_outlined),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RagUploadScreen(
                      patientId: _selectedPatientId!,
                      onConsentMissing: () {
                        if (mounted) setState(() => _consentMissing = true);
                      },
                    ),
                  ),
                );
              },
            ),
```

4. At the `DocumentsCard` call site add `isClinical: summary['view'] == 'clinical',` and `onOpenHub: _openDocuments,`.

- [ ] **Step 5: Update existing card tests for the new required parameter**

In `mobile/test/rag_upload_test.dart`, both existing `DocumentsCard(...)` constructions gain `isClinical: true` (they assert the upload button, which is a clinical-state card).

- [ ] **Step 6: Run to verify GREEN**

Run: `cd mobile && flutter test test/rag_upload_test.dart test/caregiver_role_routing_test.dart test/documents_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/screens/caregiver/sections/documents_card.dart mobile/lib/screens/caregiver_dashboard_screen.dart mobile/test/rag_upload_test.dart mobile/test/caregiver_role_routing_test.dart
git commit -m "feat(documents): health-worker lock for family caregivers + hub entry, consent wiring" -- mobile/lib/screens/caregiver/sections/documents_card.dart mobile/lib/screens/caregiver_dashboard_screen.dart mobile/test/rag_upload_test.dart mobile/test/caregiver_role_routing_test.dart
```

---

### Task 9: Per-role upload reachability tests

**Files:**
- Test: `mobile/test/document_upload_hardening_test.dart` (append)

**Interfaces:**
- Consumes: `RagUploadScreen` seams (`testBytes`, `testFilename`, `sendForTest`), `_seedUser` pattern from `caregiver_role_routing_test.dart` (SharedPreferences + `AuthSession.instance.restore()`).
- Produces: role→surface locks (client has no per-role upload logic; the server decides — these tests lock what each role can reach).

- [ ] **Step 1: Append the role tests**

To `mobile/test/document_upload_hardening_test.dart`, add imports for `auth_session.dart`, `shared_preferences.dart`, `json`, and:

```dart
  Future<void> _seedRole(String role) async {
    SharedPreferences.setMockInitialValues({
      'auth.access': 'test-access',
      'auth.refresh': 'test-refresh',
      'auth.user': jsonEncode({
        'id': 'u1',
        'phone': '+910000000001',
        'role': role,
        'preferred_language': 'english',
      }),
    });
    await AuthSession.instance.restore();
  }

  for (final role in const ['asha_worker', 'clinician', 'admin']) {
    testWidgets('$role can upload a PDF and a .txt through the same path',
        (tester) async {
      await _seedRole(role);
      final sent = <String>[];
      for (final (name, bytes) in [
        ('note.pdf', Uint8List.fromList(utf8.encode('%PDF-1.7 test'))),
        ('note.txt', Uint8List.fromList(utf8.encode('Donepezil 5 mg'))),
      ]) {
        await tester.pumpWidget(MaterialApp(
          home: RagUploadScreen(
            patientId: 'p1',
            testBytes: bytes,
            testFilename: name,
            sendForTest: (req) async {
              sent.add(req.files.single.filename);
              return http.Response(
                  jsonEncode({'document_id': 'd1', 'chars_extracted': 12}), 200);
            },
          ),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('UPLOAD ▸'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Uploaded successfully'), findsOneWidget);
      }
      expect(sent, ['note.pdf', 'note.txt']);
    });
  }
```

- [ ] **Step 2: Run to verify GREEN (contract lock)**

Run: `cd mobile && flutter test test/document_upload_hardening_test.dart`
Expected: PASS immediately — the client path is role-agnostic by design (the server gates it; Task 2 locks that server side). Disclose as locks, not RED.

- [ ] **Step 3: Commit**

```bash
git add mobile/test/document_upload_hardening_test.dart
git commit -m "test(documents): role reachability locks for PDF and txt upload" -- mobile/test/document_upload_hardening_test.dart
```

---

### Task 10: Patient line fix

**Files:**
- Modify: `mobile/lib/main.dart:385`
- Modify: `mobile/test/caregiver_scale_test.dart:401`, `mobile/test/caregiver_role_routing_test.dart:391`, `mobile/test/shell_roles_test.dart:15`

**Interfaces:**
- Consumes: `PatientHome` static line.
- Produces: exact copy "Your health worker can add your health documents."

- [ ] **Step 1: Update the copy and the three assertions**

`mobile/lib/main.dart:385`:
```dart
              'Your health worker can add your health documents.',
```

In all three test files replace `'Your caregiver can add your health documents.'` with `'Your health worker can add your health documents.'`.

- [ ] **Step 2: Run to verify GREEN**

Run: `cd mobile && flutter test test/caregiver_scale_test.dart test/caregiver_role_routing_test.dart test/shell_roles_test.dart test/rag_upload_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add mobile/lib/main.dart mobile/test/caregiver_scale_test.dart mobile/test/caregiver_role_routing_test.dart mobile/test/shell_roles_test.dart
git commit -m "fix(patient): health worker owns document uploads; family caregivers cannot" -- mobile/lib/main.dart mobile/test/caregiver_scale_test.dart mobile/test/caregiver_role_routing_test.dart mobile/test/shell_roles_test.dart
```

---

### Task 11: textScaleFactor 1.3 locks

**Files:**
- Test: `mobile/test/caregiver_scale_test.dart` (append three tests + pump the two new screens)

**Interfaces:**
- Consumes: the scale-test harness already in `caregiver_scale_test.dart` (sets `tester.platformDispatcher.textScaleFactorTestValue = 1.3`, 390×844 viewport).
- Produces: overflow locks for `RagUploadScreen`, `DocumentsScreen`, `RagQaScreen`.

- [ ] **Step 1: Append the locks**

Following the existing pattern in that file (its helper sets the 390×844 viewport and 1.3 scale), add:

```dart
    testWidgets('rag upload screen renders at 1.3 scale without overflow',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(
        home: RagUploadScreen(patientId: 'p1'),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('documents hub renders at 1.3 scale without overflow',
        (tester) async {
      final backend = _FakeBackend((method, uri, body) =>
          (status: 200, json: {'documents': [], 'count': 0}));
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      await tester.pumpWidget(const MaterialApp(
        home: DocumentsScreen(patientId: 'p1'),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('rag qa screen renders at 1.3 scale without overflow',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: RagQaScreen(patientId: 'p1'),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
```

Add the needed imports (`documents_screen.dart`, `rag_qa_screen.dart`, `rag_upload_screen.dart`; `HttpOverrides` from `dart:io`) to `caregiver_scale_test.dart`, reusing the file's existing fake backend if present (the file is locked to 390×844 and 1.3 — do not change the harness).

- [ ] **Step 2: Run; expect real overflows to be found and fixed**

Run: `cd mobile && flutter test test/caregiver_scale_test.dart`
Expected: either PASS, or FAIL with `RenderFlex overflowed` — in that case fix the offending widget (wrap in `Wrap`, add `Expanded`, raise a grid `childAspectRatio`, or shorten copy), rerun, and include the fix in the same commit. Do not raise `childAspectRatio`/padding to paper over an unbounded-height problem.

- [ ] **Step 3: Commit**

```bash
git add mobile/test/caregiver_scale_test.dart
git commit -m "test(documents): 1.3 text-scale locks for upload, hub and Q&A screens" -- mobile/test/caregiver_scale_test.dart
```

---

### Task 12: Mocked end-to-end chain

**Files:**
- Test: `mobile/test/documents_e2e_test.dart` (create)

**Interfaces:**
- Consumes: `DocumentsScreen`, `RagUploadScreen` (`pickForTest`), `RagQaScreen` (its `TextField` + `ASK ▸`), one stateful fake backend serving upload → list → answer.
- Produces: the STEP 2 chain: pick → upload → success → document in list → cited answer.

- [ ] **Step 1: Write the test**

`mobile/test/documents_e2e_test.dart` — copy the `_FakeBackend` scaffold (lines 20-168 of `mobile/test/rag_upload_test.dart`) and write:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eldercare_mobile/screens/documents_screen.dart';
import 'package:eldercare_mobile/screens/rag_qa_screen.dart';
import 'package:eldercare_mobile/screens/rag_upload_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pick → upload → list shows it → cited answer references it',
      (tester) async {
    final stored = <Map<String, dynamic>>[];

    HttpOverrides.global = _FakeBackend((method, uri, body) {
      final path = uri.path;
      if (path == '/api/v1/reports/documents/upload') {
        stored.add({
          'document_id': 'd1',
          'title': 'Medical Document',
          'file_name': 'prescription.txt',
          'doc_type': 'prescription',
          'embedding_status': 'completed',
          'created_at': '2026-09-24T10:00:00',
        });
        return (
          status: 200,
          json: {'document_id': 'd1', 'chars_extracted': 42, 'message': 'ok'}
        );
      }
      if (path == '/api/v1/reports/patients/p1/documents') {
        return (status: 200, json: {'documents': stored, 'count': stored.length});
      }
      if (path == '/api/v1/reports/documents/answer') {
        return (
          status: 200,
          json: {
            'question': 'What medication?',
            'answer': 'Donepezil 5 mg at bedtime [1].',
            'synthesized': false,
            'citations': [
              {
                'title': 'Medical Document',
                'file_ref': 'prescription.txt',
                'similarity': 0.77,
              }
            ],
            'disclaimer': 'Not medical advice — consult the treating clinician.',
          }
        );
      }
      return (status: 404, json: {'detail': 'not found: $path'});
    });
    addTearDown(() => HttpOverrides.global = null);

    // 1. Pick the file and upload it through the real picker seam.
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        pickForTest: () async => (
          bytes: Uint8List.fromList(
              utf8.encode('Patient takes Donepezil 5 mg at bedtime.')),
          filename: 'prescription.txt',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SELECT FILE'));
    await tester.pumpAndSettle();
    expect(find.text('prescription.txt'), findsOneWidget);
    await tester.tap(find.text('UPLOAD ▸'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Uploaded successfully'), findsOneWidget);

    // 2. The hub now lists the uploaded document.
    await tester.pumpWidget(
        const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();
    expect(find.text('prescription.txt'), findsOneWidget);

    // 3. A question answered from that document cites it.
    await tester.tap(find.text('ASK ABOUT DOCUMENTS'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'What medication?');
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Donepezil 5 mg'), findsOneWidget);
    expect(find.textContaining('[1] Medical Document'), findsOneWidget);
  });
}
```

The upload step is driven through `RagUploadScreen`'s `pickForTest` seam (the hub pushes that screen without seams, so the picker cannot run in a widget test); the list and Q&A steps use the real `DocumentsScreen` and `RagQaScreen`.

- [ ] **Step 2: Run to verify GREEN**

Run: `cd mobile && flutter test test/documents_e2e_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add mobile/test/documents_e2e_test.dart
git commit -m "test(documents): mocked pick → upload → list → cited answer chain" -- mobile/test/documents_e2e_test.dart
```

---

### Task 13: Final gates

**Files:**
- Modify: `.superpowers/sdd/PLAN/progress.md` (ledger entry; untracked/ignored by design — edit, do not force-add)

**Interfaces:**
- Consumes: everything above.
- Produces: verified green state + ledger.

- [ ] **Step 1: Full mobile suite**

Run: `cd mobile && flutter test`
Expected: all pass, no failures; skipped count may grow (platform-skipped tests). Baseline before this branch: 133 passed / 5 skipped.

- [ ] **Step 2: Analyzer**

Run: `cd mobile && flutter analyze`
Expected: 58 issues (the pre-existing baseline), no new ones. If new infos appear from added files, fix them (prefer `const`, import order) — do not raise the baseline.

- [ ] **Step 3: Backend suites**

Run: `cd backend && python3 -m pytest app/tests/test_document_upload.py app/tests/test_document_list.py app/tests/test_rag_service.py -q`
Expected: PASS.
Then: `cd backend && python3 -m pytest app/tests tests -q` (canonical full suite from `backend/`).
Expected: all pass. Record the count.

- [ ] **Step 4: Repo gates**

Run: `git diff --check` → clean.
Run: `git diff b9f0abf..HEAD -- dashboard/` → empty.
Run: `git status --short` → only the 45 foreign entries (no new paths of ours).

- [ ] **Step 5: Graph + ledger**

Run: `graphify update .` (AST-only, no API cost).
Append a ledger entry to `.superpowers/sdd/PLAN/progress.md`: branch, task list with commit SHAs, final counts, the honest notes (contract locks that passed without RED; no new dependencies; STEP 4 A/B remain design notes in the spec).

- [ ] **Step 6: Report**

Report to the user: per-task commit list, final `flutter test`/`flutter analyze`/backend counts, the two STEP 4 notes, and the removal condition for the family lock (if STEP 4B is ever implemented).

---

## Self-Review

**Spec coverage:** backend list endpoint → Task 1; upload role matrix/413/consent → Task 2; `isNetworkError` + list + ask → Task 3; allowlist + size/type → Task 4; failure matrix rows (offline, 401, 413, 429, 403 tier, 403 consent, 400) → Task 5; `DocumentsScreen` → Task 6; `RagQaScreen` → Task 7; family lock + app-bar icon + consent wiring + hub entry → Task 8; per-role reachability → Task 9 (client) and Task 2 (server); patient line → Task 10; 1.3 scale → Task 11; mocked chain → Task 12; gates → Task 13. No spec requirement lacks a task.

**Placeholder scan:** no TBD/TODO. Task 2 Step 3 and Task 12 Step 1 contain explicit instructions to remove two drafting artifacts, and both state the exact final shape — no ambiguity is left to the implementer.

**Type consistency:** `listDocuments(String patientId)`, `askDocumentQuestion({required String patientId, required String question, int topK = 3})`, `ApiException.isNetworkError`, `validateDocumentFile({required String filename, required int byteLength})`, `formatDocumentUploadError(ApiException e)`, `DocumentsScreen({required String patientId, VoidCallback? onConsentMissing})`, `RagQaScreen({required String patientId})`, `DocumentsCard(..., required isClinical, onOpenHub)` — each name is defined once and used consistently in later tasks.

**Known risks in the plan:** every theme token used (`monoCaption`, `monoBodySm`, `monoBody`, `monoLabel`, `subheading`, `cardShape`, `radiusMin`, `tintMint`, `tintGold`, `graphite`, `ash`, `parchment`) exists in `mobile/lib/theme/monad_theme.dart`; `MonadPillButton`'s primary variant appends " ▸" (`monad_pill_button.dart:34`), which is why tests tap `UPLOAD ▸` / `ASK ▸`; date formatting is hand-rolled so no `intl` locale initialization is needed.

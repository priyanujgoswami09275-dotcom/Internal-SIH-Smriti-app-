# Caregiver Dashboard Mobile Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the full caregiver-dashboard feature set into the mobile app so caregiver/ASHA/clinician/admin phone logins see the dashboard; patients keep the patient shell.

**Architecture:** Incremental refactor of the existing 883-line `CaregiverDashboardScreen` into section widgets under `mobile/lib/screens/caregiver/`; new endpoints (`uploadDocument`, `submitRiskScreening`) added to the existing `ApiService` (single-flight refresh); role routing in `main.dart` switches on the server-issued role; `file_picker` replaces the RAG picker stub; `dashboard/` untouched.

**Tech Stack:** Flutter (stable 3.47.2), `http`, `shared_preferences`, `file_picker` (new dep), existing Monad theme, fake-HTTP `HttpOverrides` test pattern.

**Spec:** `docs/superpowers/specs/2026-09-23-caregiver-dashboard-mobile-port-design.md`

## Global Constraints

- Branch: `feat/caregiver-dashboard-mobile-port` (already created; spec committed at `807a85a`).
- NEVER modify anything under `dashboard/`.
- NEVER touch: CLAUDE.md, README.md, graphify-out/, backend/eldercare.db, .env, .opencode/opencode.json.
- The git index holds staged junk deletions (backend-verify/, frontend/, report.txt, etc.) from the cleanup pass. NEVER run a bare `git commit`; always `git add <task paths> && git commit -m "..." -- <task paths>`.
- Reuse `mobile/lib/services/api_service.dart` + `auth_session.dart` (single-flight refresh). Do NOT copy dashboard's `Api` class.
- Single-column phone layout; interactive controls ≥48px (`MonadPillButton` already min-height 48; raw `IconButton`s in caregiver surfaces get `constraints: BoxConstraints(minWidth: 48, minHeight: 48)` during extraction); Monad tokens only (`Monad.*`); CustomPaint sparklines only (reuse `mobile/lib/widgets/trend_chart.dart`; no chart dependency).
- Server gates authoritative; client renders honest 403/`view=basic` states; consent failures surface explicit "health_data consent required" copy — never silence an error.
- Tests: mock ApiService/HTTP only (fake-HTTP `HttpOverrides` pattern from `rag_upload_test.dart`). NEVER run `api_live_test.dart` or `integration_test/` against the demo DB — run full suite only as `flutter test` from `mobile/` with default `API_BASE_URL` (api_live self-skips without a live server).
- Per extraction: run `flutter test` after EACH section move (Amendment 4) before committing.
- Gates per task: `cd mobile && flutter analyze` clean (33 pre-existing infos OK, no new issues), targeted `flutter test` green.
- Roles come from the server only (`AuthSession.instance.user.role`). `DevRoleMenu` gated by `kDebugMode && DEV_MENU`.
- Commit style: `feat(caregiver): ...` / `test(caregiver): ...` / `docs: ...`.

---

### Task 1: ApiService — `uploadDocument` + `submitRiskScreening`

**Files:**
- Modify: `mobile/lib/services/api_service.dart` (append after `auditLogs`, ~line 541)
- Test: `mobile/test/api_caregiver_endpoints_test.dart` (new)

**Interfaces:**
- Consumes: `ApiService._send/_headers/_uri/_tryRefresh/_decode/ApiException` (existing, lines 82–200), `buildRagUploadRequest` from `screens/rag_upload_screen.dart`.
- Produces (later tasks rely on these exact signatures):
  - `Future<Map<String, dynamic>> uploadDocument({required String patientId, required Uint8List bytes, required String filename, String docType = 'prescription', String? title})`
  - `Future<Map<String, dynamic>> submitRiskScreening({required String patientId, required Map<String, dynamic> payload})`

- [ ] **Step 1: Copy the fake-HTTP scaffold**

Copy `_Handler`, `_FakeBackend`, `_FakeClient`, `_FakeRequest`, `_FakeHeaders`, `_FakeResponse` verbatim from `mobile/test/rag_upload_test.dart` lines 19–167 into the new file `mobile/test/api_caregiver_endpoints_test.dart`, with a `void main()` stub.

- [ ] **Step 2: Write the failing tests**

```dart
void main() {
  group('uploadDocument', () {
    test('multipart POST to upload path with query+field patient_id, auth header', () async {
      final backend = _FakeBackend((method, uri, body) {
        expect(method, 'POST');
        expect(uri.path, '/api/v1/reports/documents/upload');
        expect(uri.queryParameters['patient_id'], 'p1');
        expect(body, contains('name="patient_id"'));
        expect(body, contains('name="file"'));
        expect(body, contains('name="doc_type"'));
        return (status: 200, json: {'document_id': 'd1'});
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')..authToken = 'tok-1';
      final data = await api.uploadDocument(
        patientId: 'p1',
        bytes: Uint8List.fromList(utf8.encode('hi')),
        filename: 'note.pdf',
      );
      expect(data['document_id'], 'd1');
    });

    test('403 consent detail surfaces via ApiException (no silence)', () async {
      final backend = _FakeBackend((method, uri, body) => (
        status: 403,
        json: {'detail': "Active consent required for scope 'health_data'"},
      ));
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')..authToken = 'tok-1';
      await expectLater(
        api.uploadDocument(patientId: 'p1', bytes: Uint8List.fromList([1]), filename: 'a.pdf'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', contains('health_data'))),
      );
    });
  });

  group('submitRiskScreening', () {
    test('POSTs payload to /patients/{id}/risk-screening and returns result', () async {
      final backend = _FakeBackend((method, uri, body) {
        expect(method, 'POST');
        expect(uri.path, '/api/v1/patients/p1/risk-screening');
        expect(jsonDecode(body), containsPair('Age', 72));
        return (status: 200, json: {'status': 'ok', 'risk_score': 41, 'tier': 'moderate_risk'});
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')..authToken = 'tok-1';
      final result = await api.submitRiskScreening(patientId: 'p1', payload: {'Age': 72});
      expect(result['tier'], 'moderate_risk');
    });

    test('401 then refresh then retry (single-flight path reused)', () async {
      var calls = 0;
      final backend = _FakeBackend((method, uri, body) {
        calls++;
        if (uri.path.endsWith('/risk-screening')) {
          final auth = (uri.queryParameters.isEmpty ? null : null);
          // first hit: 401; after refresh: 200
          return calls == 1 || calls == 2 && false
              ? (status: 401, json: {'detail': 'token expired'})
              : (status: 200, json: {'status': 'ok', 'risk_score': 10});
        }
        if (uri.path.endsWith('/auth/refresh')) {
          return (status: 200, json: {'access_token': 'new', 'refresh_token': 'r2'});
        }
        return (status: 404, json: {'detail': 'no'});
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')
        ..authToken = 'old'
        ..refreshToken = 'r1';
      final result = await api.submitRiskScreening(patientId: 'p1', payload: {'Age': 60});
      expect(result['status'], 'ok');
      expect(api.authToken, 'new');
    });
  });
}
```

(Note: simplify the 401 test — first risk-screening call returns 401, second returns 200; refresh endpoint returns new tokens. Assert final result ok + `api.authToken == 'new'`.)

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd mobile && flutter test test/api_caregiver_endpoints_test.dart`
Expected: FAIL — `uploadDocument`/`submitRiskScreening` are not defined.

- [ ] **Step 4: Implement**

Append to `mobile/lib/services/api_service.dart` (needs `import 'dart:typed_data';` if not present — `Uint8List` comes from `dart:typed_data` or `flutter/foundation.dart`):

```dart
/// Authed multipart upload → POST /reports/documents/upload.
/// `patient_id` rides as query param AND form field (FastAPI signature
/// declares query; field keeps the contract either way — see the web
/// dashboard). Rebuilds the MultipartRequest on refresh retry (a sent
/// request cannot be re-streamed).
Future<Map<String, dynamic>> uploadDocument({
  required String patientId,
  required Uint8List bytes,
  required String filename,
  String docType = 'prescription',
  String? title,
}) async {
  http.MultipartRequest build() {
    final req = http.MultipartRequest(
      'POST',
      _uri('${AppConfig.apiV1}/reports/documents/upload',
          {'patient_id': patientId}),
    );
    final h = _headers()..remove('Content-Type');
    req.headers.addAll(h);
    req.fields['patient_id'] = patientId;
    req.fields['doc_type'] = docType;
    if (title != null && title.isNotEmpty) req.fields['title'] = title;
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    return req;
  }

  var streamed = await build().send();
  var res = await http.Response.fromStream(streamed);
  if (res.statusCode == 401 && includeAuthOn401(res)) { ... }
  // 401 → refresh → rebuild once:
  if (res.statusCode == 401 && refreshToken != null) {
    final refreshed = await _tryRefresh();
    if (refreshed) {
      streamed = await build().send();
      res = await http.Response.fromStream(streamed);
    }
  }
  if (res.statusCode == 401 && !_inUnauthorizedHandler) {
    _inUnauthorizedHandler = true;
    try {
      await onUnauthorized?.call();
    } finally {
      _inUnauthorizedHandler = false;
    }
  }
  return _decode(res) as Map<String, dynamic>;
}

/// POST /patients/{id}/risk-screening — clinical tier + health_data
/// consent enforced server-side; 403 detail surfaces in ApiException.
Future<Map<String, dynamic>> submitRiskScreening({
  required String patientId,
  required Map<String, dynamic> payload,
}) async {
  final data = await postJson(
    '${AppConfig.apiV1}/patients/$patientId/risk-screening',
    body: payload,
  );
  return Map<String, dynamic>.from(data as Map);
}
```

(Delete the bogus `includeAuthOn401` line — 401 handling mirrors `_send` lines 127–141 exactly; `_decode` already throws `ApiException(detail, statusCode:)` for non-2xx, which carries the consent detail.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd mobile && flutter test test/api_caregiver_endpoints_test.dart`
Expected: PASS (all).

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/services/api_service.dart mobile/test/api_caregiver_endpoints_test.dart
git commit -m "feat(caregiver): ApiService.uploadDocument + submitRiskScreening (1)" -- mobile/lib/services/api_service.dart mobile/test/api_caregiver_endpoints_test.dart
```

---

### Task 2: DevRoleMenu `kDebugMode` gate + PatientHome static line

**Files:**
- Modify: `mobile/lib/widgets/dev_role_menu.dart` (gate), `mobile/lib/main.dart:371` + `mobile/lib/screens/caregiver_dashboard_screen.dart:224` (drawer attach), `mobile/lib/main.dart` PatientHome ListView (~line 374)
- Test: `mobile/test/shell_roles_test.dart` (new)

**Interfaces:**
- Consumes: `DevRoleMenu.enabled` (existing `bool.fromEnvironment('DEV_MENU')`), `PatientHome` (public, `main.dart:353`).
- Produces: `DevRoleMenu.enabled` becomes a `static bool get` = `kDebugMode && const bool.fromEnvironment('DEV_MENU')`; exact patient line `'Your caregiver can add your health documents.'`.

- [ ] **Step 1: Write failing tests** in `mobile/test/shell_roles_test.dart`

```dart
import 'package:eldercare_mobile/main.dart';
import 'package:eldercare_mobile/widgets/dev_role_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('DevRoleMenu disabled without DEV_MENU define (even in debug)', () {
    expect(DevRoleMenu.enabled, isFalse);
  });

  testWidgets('PatientHome shows the caregiver-documents line', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PatientHome(patientId: 'p1')));
    expect(find.text('Your caregiver can add your health documents.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run → verify FAIL** (`flutter test test/shell_roles_test.dart`): patient line missing; `DevRoleMenu.enabled` is a `const` field — keep compiling but the const is already false, so only the line test fails (that's the RED). Also add `expect(const DevRoleMenu().enabled, ...)`? No — keep simple: the line test is RED, the enabled test is a lock.

- [ ] **Step 3: Implement**

`dev_role_menu.dart`: replace `static const enabled = bool.fromEnvironment('DEV_MENU');` with:

```dart
/// Dev-only: never active in release (kDebugMode) and only when explicitly
/// enabled with --dart-define=DEV_MENU=true.
static bool get enabled =>
    kDebugMode && const bool.fromEnvironment('DEV_MENU');
```

Add `import 'package:flutter/foundation.dart';` if missing.

`main.dart` PatientHome — insert as the FIRST child of the ListView (before the first `_homeButton`), after `padding`:

```dart
Padding(
  padding: const EdgeInsets.only(bottom: Monad.spacing16),
  child: Text(
    'Your caregiver can add your health documents.',
    style: Monad.monoBodySm.copyWith(color: Monad.smoke),
  ),
),
```

Drawer call sites (`main.dart:371`, `caregiver_dashboard_screen.dart:224`): `drawer: DevRoleMenu.enabled ? const DevRoleMenu() : null,`

- [ ] **Step 4: Run → PASS**, then `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/widgets/dev_role_menu.dart mobile/lib/main.dart mobile/lib/screens/caregiver_dashboard_screen.dart mobile/test/shell_roles_test.dart
git commit -m "feat(caregiver): dev-menu kDebugMode gate + patient documents line (2)" -- <those paths>
```

---

### Task 3: Extract `sections/patient_switcher.dart` + `sections/alerts_card.dart`

**Files:**
- Create: `mobile/lib/screens/caregiver/sections/patient_switcher.dart`, `mobile/lib/screens/caregiver/sections/alerts_card.dart`
- Modify: `mobile/lib/screens/caregiver_dashboard_screen.dart` (delete `_patientSelector`, `_alerts`, `_chip`; call sites at body build ~line 340)
- Test: existing `flutter test` must stay green (no new test — refactor).

**Interfaces:**
- Produces:

```dart
class PatientSwitcher extends StatelessWidget {
  const PatientSwitcher({super.key, required this.patients, required this.selectedPatientId, required this.onSelect});
  final List<Map<String, dynamic>> patients;
  final String? selectedPatientId;
  final ValueChanged<String> onSelect;
}

class AlertsCard extends StatelessWidget {
  const AlertsCard({super.key, required this.summary, required this.onAcknowledge});
  final Map<String, dynamic> summary;
  final Future<void> Function(String alertId) onAcknowledge;
}
```

- [ ] **Step 1: Create `patient_switcher.dart`** — body = verbatim move of `_patientSelector` (lines 459–487) into `build`, with `patients`/`selectedPatientId` from fields and `onChanged: (v) { if (v != null) onSelect(v); }`. Imports: `flutter/material.dart`, `../../theme/monad_theme.dart`.
- [ ] **Step 2: Create `alerts_card.dart`** — body = verbatim move of `_chip` (436–457) as a private `_chip` method + `_alerts` (489–574) into `build`; `onAcknowledge` replaces the state's `_acknowledge` call. Imports: `flutter/material.dart`, `../../theme/monad_theme.dart`, `../../widgets/monad/monad_pill_button.dart`.
- [ ] **Step 3: Rewire orchestrator** — replace `_patientSelector(patients)` call with `PatientSwitcher(patients: patients, selectedPatientId: _selectedPatientId, onSelect: (v) => _select(v))` and `_alerts(summary)` with `AlertsCard(summary: summary, onAcknowledge: _acknowledge)`; delete the moved private methods; add imports `sections/patient_switcher.dart`, `sections/alerts_card.dart`.
- [ ] **Step 4: Run tests** — `cd mobile && flutter test` (full suite; api_live self-skips). Expected: same as baseline (102+ passing / 5 skipped + new Task 1–2 tests).
- [ ] **Step 5: `flutter analyze`** — no new issues.
- [ ] **Step 6: Commit** — `feat(caregiver): extract patient_switcher + alerts_card sections (3)` with `-- <paths>`.

---

### Task 4: Extract `sections/metrics_tiles.dart` + `sections/trends_section.dart`

**Files:**
- Create: `mobile/lib/screens/caregiver/sections/metrics_tiles.dart`, `mobile/lib/screens/caregiver/sections/trends_section.dart`
- Modify: `mobile/lib/screens/caregiver_dashboard_screen.dart` (delete `_metrics`, `_tile`, `_trends`; call sites ~lines 352, 357)
- Test: existing suite stays green.

**Interfaces:**
- Produces:

```dart
class MetricsTiles extends StatelessWidget {
  const MetricsTiles({super.key, required this.summary});
  final Map<String, dynamic> summary; // renders accuracy/compliance/missed tiles (moves lines 576–608 + _tile 924–end)
}

class TrendsSection extends StatelessWidget {
  const TrendsSection({super.key, required this.summary});
  final Map<String, dynamic> summary; // moves lines 610–654: TrendChart pair or basic-tier lock note
}
```

- [ ] **Steps:** same pattern as Task 3 — create files (verbatim move, `_tile` becomes private method of metrics file; `TrendChart` imported from `../../widgets/trend_chart.dart`; `AuthSession`-free), rewire call sites, `flutter test` full, `flutter analyze`, commit `feat(caregiver): extract metrics_tiles + trends_section (4)`.

---

### Task 5: Extract `sections/compliance_log.dart` + `sections/schedules_card.dart`

**Files:**
- Create: `mobile/lib/screens/caregiver/sections/compliance_log.dart`, `mobile/lib/screens/caregiver/sections/schedules_card.dart`
- Modify: `mobile/lib/screens/caregiver_dashboard_screen.dart` (delete `_complianceLog` 656–731, `_schedulesCard` 733–816; call sites ~lines 362, 367)
- Test: existing `schedule_delete_contract_test.dart` + `rag_upload_test.dart` must stay green (they pump the whole screen).

**Interfaces:**
- Produces:

```dart
class ComplianceLog extends StatelessWidget {
  const ComplianceLog({super.key, required this.events});
  final List<ReminderEventModel>? events; // null = unavailable; moves lines 656–731
}

class SchedulesCard extends StatelessWidget {
  const SchedulesCard({super.key, required this.schedules, required this.onAdd, required this.onRemove});
  final List<ReminderScheduleModel>? schedules;
  final VoidCallback onAdd;               // orchestrator keeps _addSchedule bottom-sheet logic (lines 687–726)
  final Future<void> Function(String scheduleId) onRemove; // = _removeSchedule
}
```

- [ ] **Steps:** create (compliance_log imports `../../models/shared_models.dart` for `ReminderEventModel` + `ReminderStatus`; schedules_card imports models + `MonadPillButton` — note `_schedulesCard` calls `onAdd` from its ADD `TextButton.icon`), rewire, full `flutter test`, analyze, commit `feat(caregiver): extract compliance_log + schedules_card (5)`.

---

### Task 6: Extract `sections/documents_card.dart` (consent state) + RagUploadScreen consent pop-result

**Files:**
- Create: `mobile/lib/screens/caregiver/sections/documents_card.dart`
- Modify: `mobile/lib/screens/caregiver_dashboard_screen.dart` (delete `_documentsCard` 818–856, add `bool _consentMissing = false`, push becomes awaited), `mobile/lib/screens/rag_upload_screen.dart` (pop with result on consent 403)
- Test: extend `mobile/test/rag_upload_test.dart` with a consent-result case.

**Interfaces:**
- Consumes: `RagUploadScreen` (existing push pattern).
- Produces:

```dart
class DocumentsCard extends StatelessWidget {
  const DocumentsCard({super.key, required this.patientId, required this.consentMissing, required this.onUpload});
  final String? patientId;
  final bool consentMissing;      // true → tinted "health_data consent required" state (Amendment 1)
  final VoidCallback? onUpload;   // null when patientId == null
}
```

`RagUploadScreen` new behavior: on a failed upload whose body detail contains `'health_data'` (server contract: `Active consent required for scope 'health_data'`), set an internal `_consentMissing = true`; on pop (AppBar back / system back — use `PopScope` capturing `didPop`) return `'consent_missing'` when the flag is set, else `null`.

- [ ] **Step 1: Failing test** (append to `rag_upload_test.dart`):

```dart
testWidgets('consent 403 pops result consent_missing', (tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(MaterialApp(
    home: RagUploadScreen(
      patientId: 'p1',
      testBytes: Uint8List.fromList(utf8.encode('x')),
      testFilename: 'n.pdf',
      sendForTest: (req) async => http.Response(
        jsonEncode({'detail': "Active consent required for scope 'health_data'"}),
        403,
        headers: const {'Content-Type': 'application/json'},
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('UPLOAD ▸'));
  await tester.pumpAndSettle();
  expect(find.textContaining('consent'), findsWidgets); // explicit state, not silence
  // Pop returns the marker:
  final result = await Navigator.of(tester.element(find.byType(RagUploadScreen)))
      .push<String?>(MaterialPageRoute(builder: (_) => const SizedBox()));
  // Instead: verify via PopScope by popping and reading route result:
});
```

(Abort-route check is awkward in-test; simpler contract: make `RagUploadScreen` expose `@visibleForTesting String? get lastOutcome => _consentMissing ? 'consent_missing' : null;` AND pop-with-result. Test asserts `lastOutcome == 'consent_missing'` after the failed upload, and a separate orchestrator test asserts the card state — see Step 3.)

- [ ] **Step 2: Implement** — `rag_upload_screen.dart`: in `_upload()`'s failure branch, `if (res.statusCode == 403 && res.body.contains('health_data')) _consentMissing = true;` plus `@visibleForTesting String? get lastOutcome`. `PopScope(canPop: true, onPopInvokedWithResult: ...)` is not needed if we only expose `lastOutcome` for the card wiring test.

Orchestrator: `bool _consentMissing = false;` — push becomes:

```dart
await Navigator.of(context).push<bool>(
  MaterialPageRoute(builder: (_) => RagUploadScreen(patientId: patientId)),
);
```

Actually the marker lives on the pushed screen instance — simplest wiring: `RagUploadScreen(patientId: ..., onConsentMissing: () => setState(() => _consentMissing = true))` (new optional callback param, invoked before showing the 403 message). Reset `_consentMissing = false` in `_select()` when the patient changes.

`documents_card.dart`: when `consentMissing`, render a tinted `Monad.tintGold` container (same pattern as the trends lock note, lines 625–643 of the orchestrator):

```
health_data consent required — this patient has not granted consent for
health data, so documents can't be uploaded until they do.
```

Button stays enabled (server authoritative; re-push allowed after consent granted).

- [ ] **Step 3: Orchestrator test** (append to `rag_upload_test.dart`): pump dashboard with fake backend (roster/summary handlers copied from lines 248–287), tap `UPLOAD DOCUMENT`, fail with consent 403 via `sendForTest`, pop back, expect `find.textContaining('health_data consent required')` findsOneWidget on the dashboard.

- [ ] **Step 4: Run** `flutter test test/rag_upload_test.dart` → RED then GREEN; full `flutter test`; analyze; commit `feat(caregiver): documents_card consent-required state (6)`.

---

### Task 7: Audit → `audit_viewer_screen.dart` (card list) + admin entry

**Files:**
- Create: `mobile/lib/screens/caregiver/audit_viewer_screen.dart`
- Modify: `mobile/lib/screens/caregiver_dashboard_screen.dart` (delete `_auditCard` 858–922 + its section header/spacing in `_buildMain`; add admin-only AppBar action)
- Modify: `mobile/test/schedule_delete_contract_test.dart` (audit row now lives behind the admin push)
- Test: extend `shell_roles_test.dart` or the contract test.

**Interfaces:**
- Consumes: `ApiService.instance.auditLogs({int limit})` (already exists, line 537).
- Produces:

```dart
class AuditViewerScreen extends StatefulWidget { ... }
// Loads auditLogs(limit: 50) in initState; renders a card list
// (ListTile column — NOT a table) with 'by {user_id} · {timestamp}' rows;
// 403 → 'Audit trail is admin-only — your role cannot view it.'
```

Dashboard AppBar gains (only when `AuthSession.instance.user?.role == Role.admin`):

```dart
IconButton(
  tooltip: 'Compliance audit trail (admin)',
  icon: const Icon(Icons.fact_check_outlined),
  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
  onPressed: () => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AuditViewerScreen()),
  ),
),
```

- [ ] **Step 1: Update failing test** — in `schedule_delete_contract_test.dart` audit group: seed an admin user BEFORE pumping (mirror `_seedUser` from `clinical_notes_sync_test.dart:76–88` with `role: 'admin'`), pump dashboard, tap `find.byTooltip('Compliance audit trail (admin)')`, `pumpAndSettle`, then assert `find.text('by u1 · t1')` / `findsNothing` for 'by system'. RED: no such tooltip yet.
- [ ] **Step 2: Implement** `audit_viewer_screen.dart` — move the `_auditCard` FutureBuilder body (lines 858–922) into a screen: `Scaffold(appBar: AppBar(title: Text('DPDP audit trail')), body: ListView(...))` keeping the honest-403 text, card styling (`Monad.periwinkleMist`, `softShape`), and `user_id`/`timestamp` keys. Dashboard: delete `_auditCard` + the `'Audit trail'` section header block from `_buildMain`; add the admin AppBar action.
- [ ] **Step 3: Run** `flutter test test/schedule_delete_contract_test.dart` → GREEN; full `flutter test`; analyze; commit `feat(caregiver): audit viewer as admin pushed screen (7)`.

---

### Task 8: Risk screening port — card, intake form, section

**Files:**
- Create: `mobile/lib/screens/caregiver/sections/risk_screening_card.dart`, `.../risk_intake_form.dart`, `.../risk_screening_section.dart`
- Modify: `mobile/lib/screens/caregiver_dashboard_screen.dart` (state `Map<String, dynamic>? _riskScreeningResult; bool _screeningConsentMissing = false;` + `_buildMain` inserts `RiskScreeningSection` after trends)
- Test: `mobile/test/risk_screening_test.dart` (new)

**Interfaces:**
- Consumes: `ApiService.submitRiskScreening` (Task 1), `summary['view'] == 'clinical'`.
- Produces:

```dart
class RiskScreeningCard extends StatelessWidget { // port of dashboard/lib/widgets/risk_screening_card.dart with import path ../../theme/monad_theme.dart; fields: final Map<String, dynamic>? result;
}

class RiskIntakeForm extends StatefulWidget {
  const RiskIntakeForm({super.key, required this.patientId, required this.patientName, required this.onResult, this.onConsentMissing});
  final String patientId;
  final String patientName;
  final void Function(Map<String, dynamic> result) onResult;
  final VoidCallback? onConsentMissing; // fired on 403 detail containing 'health_data'
}

class RiskScreeningSection extends StatelessWidget {
  const RiskScreeningSection({super.key, required this.isClinical, required this.patientId, required this.patientName, required this.result, required this.consentMissing, required this.onResult, required this.onConsentMissing});
  // clinical + !consentMissing → RiskScreeningCard + 'Run Screening (32 inputs)' button (opens dialog)
  // clinical + consentMissing → tinted gold consent-required state (Amendment 1)
  // basic → gold locked note: 'Cognitive risk screening is available to linked clinical staff only.'
}
```

Phone adaptation of the intake form (dashboard version is width 560 Dialog): use `width: double.maxFinite` inside `Dialog` with `constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.94, maxHeight: MediaQuery.of(context).size.height * 0.9)` — single-column-friendly; the `Row`/`Wrap` field groups already wrap.

- [ ] **Step 1: Failing tests** (`risk_screening_test.dart`, fake-HTTP scaffold copied):

```dart
testWidgets('basic tier: locked note, no Run Screening button', ...) // summary view=basic → find.textContaining('linked clinical staff only'), find.text('RUN SCREENING (32 INPUTS) ▸') findsNothing
testWidgets('clinical tier: card + button visible', ...) // view=clinical → button findsOneWidget
testWidgets('intake form submits payload; result renders score', ...) // open form, enter Age 72 + a couple fields, tap RUN SCREENING, fake backend asserts body contains '"Age":72', returns {status: ok, risk_score: 41, tier: moderate_risk}; expect find.textContaining('Screening score: 41')
testWidgets('403 consent → section shows consent-required state', ...) // form submit returns consent 403 → onConsentMissing → section shows 'health_data consent required'
```

- [ ] **Step 2: Port files** — copy `dashboard/lib/widgets/risk_screening_card.dart` → sections/ with `import '../../theme/monad_theme.dart';`; copy `risk_intake_form.dart` → sections/ replacing `import '../main.dart';` + `Api.submitRiskScreening(...)` with `import '../../services/api_service.dart';` + `ApiService.instance.submitRiskScreening(...)`, `import '../../theme/monad_theme.dart';`, `import '../../widgets/monad/monad_pill_button.dart';`, width fix above, and add `onConsentMissing` (in `_submit`'s catch: `if (e is ApiException && e.statusCode == 403 && e.message.contains('health_data')) widget.onConsentMissing?.call();` — error text still renders inline).
- [ ] **Step 3: Section + wire into orchestrator** — insert in `_buildMain` after `_trends(summary)` block:

```dart
const SizedBox(height: 24),
RiskScreeningSection(
  isClinical: summary['view'] == 'clinical',
  patientId: _selectedPatientId!,
  patientName: _patientName(_selectedPatientId!), // derive from _patients list; helper method
  result: _riskScreeningResult,
  consentMissing: _screeningConsentMissing,
  onResult: (r) => setState(() => _riskScreeningResult = r),
  onConsentMissing: () => setState(() => _screeningConsentMissing = true),
),
```

Reset `_riskScreeningResult`/`_screeningConsentMissing` in `_select()`.

- [ ] **Step 4: Run** `flutter test test/risk_screening_test.dart` → GREEN; full suite; analyze; commit `feat(caregiver): risk screening port — card, intake, section (8)`.

---

### Task 9: `file_picker` for RAG upload

**Files:**
- Modify: `mobile/pubspec.yaml` (add dep), `mobile/lib/screens/rag_upload_screen.dart` (`_pickFile` + drop `dart:io`)
- Test: `mobile/test/rag_upload_picker_test.dart` (new)

**Interfaces:**
- Consumes: `ApiService.uploadDocument` (Task 1), existing `testBytes`/`sendForTest` seams (must keep working for prior tests).
- Produces: `Future<void> _pickFile()` uses `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf','txt','md','doc','docx'], withData: true)` → stores `_pickedBytes`/`_pickedFilename`; upload path uses `_pickedBytes ?? testBytes`.

- [ ] **Step 1: Add dependency**

Run: `cd mobile && flutter pub add file_picker` (supersedes the earlier file-picker hold — user constraint in the port request).

- [ ] **Step 2: Failing test** (`rag_upload_picker_test.dart`): `file_picker` in widget tests needs its MethodChannel mocked — use `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel('miguelruivo.flutter.plugins.filepicker'), ...)` returning `{'files': [{'path': ..., 'name': 'note.pdf', 'bytes': <int>[...]}]}`. Simpler and version-stable: extract `_pickFile`'s platform call behind a `@visibleForTesting Future<({Uint8List bytes, String filename})?> Function()? pickForTest` seam on the screen (mirrors `sendForTest`); unit-test the wiring (pick → bytes → Upload enabled → sendForTest receives file part named note.pdf). The real `FilePicker` call sits in the default function. RED first.

- [ ] **Step 3: Implement** — `_pickFile`:

```dart
Future<void> _pickFile() async {
  final picked = widget.pickForTest != null
      ? await widget.pickForTest!()
      : await _pickWithFilePicker();
  if (picked == null || !mounted) return;
  setState(() {
    _pickedBytes = picked.bytes;
    _pickedFilename = picked.filename;
    _filePath = picked.filename; // display line unchanged
    _result = null;
  });
}

Future<({Uint8List bytes, String filename})?> _pickWithFilePicker() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'txt', 'md', 'doc', 'docx'],
    withData: true,
  );
  final f = res?.files.single;
  if (f == null || f.bytes == null) return null;
  return (bytes: f.bytes!, filename: f.name);
}
```

`_canUpload` gains `_pickedBytes != null`; `_upload` uses `_pickedBytes ?? widget.testBytes` (drop `dart:io` `File` import — web-safe).

- [ ] **Step 4: Run** picker test + full suite (all prior RAG tests still green — `testBytes` path unchanged); analyze; commit `feat(caregiver): file_picker RAG upload (9)`.

---

### Task 10: Role routing in `main.dart` + per-role widget tests

**Files:**
- Modify: `mobile/lib/main.dart` `HomeShell.build` (~lines 253–270)
- Test: `mobile/test/caregiver_role_routing_test.dart` (new)

**Interfaces:**
- Consumes: `AuthSession.instance.user.role`, `CaregiverDashboardScreen(caregiverId:)`, `PatientHome(patientId:)`.
- Produces: explicit switch (all staff roles currently converge on the dashboard — the switch documents the tier mapping and gates the admin surface):

```dart
final role = user?.role;
if (role == Role.familyCaregiver ||
    role == Role.ashaWorker ||
    role == Role.clinician ||
    role == Role.admin) {
  return CaregiverDashboardScreen(caregiverId: user!.id);
}
// patient (or null) → existing patient path below
```

(The tier split basic-vs-clinical is server-driven via `summary['view']`; the client switch satisfies "role routing in main.dart" and keeps `isStaff` semantics. Admin gets the dashboard + audit entry from Task 7.)

- [ ] **Step 1: Failing tests** — fake-HTTP scaffold + `_seedUser` helper (copy from `clinical_notes_sync_test.dart:76–88`):

```dart
group('role routing', () {
  testWidgets('family_caregiver → dashboard (basic: no screening button)', (tester) async {
    await _seedUser(id: 'u1', role: 'family_caregiver');
    // fake backend: roster 1 patient, summary view=basic (handlers as in rag_upload_test)
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    await tester.pumpAndSettle();
    expect(find.byType(CaregiverDashboardScreen), findsOneWidget);
    expect(find.textContaining('linked clinical staff only'), findsWidgets);
    expect(find.text('RUN SCREENING (32 INPUTS) ▸'), findsNothing);
    expect(find.byTooltip('Compliance audit trail (admin)'), findsNothing);
  });

  testWidgets('asha_worker → clinical + patient switcher', (tester) async {
    await _seedUser(id: 'u2', role: 'asha_worker');
    // roster: 2 patients; summary view=clinical with daily_trends non-empty
    ... expect(find.byType(CaregiverDashboardScreen), findsOneWidget);
    expect(find.text('RUN SCREENING (32 INPUTS) ▸'), findsOneWidget);
    expect(find.text('Select patient'), findsOneWidget);
  });

  testWidgets('clinician → clinical tier', ...);  // same clinical assertions, no switcher (role != asha → switcher hidden; roster length 1)
  testWidgets('admin → audit entry visible', ...); // role admin → find.byTooltip('Compliance audit trail (admin)') findsOneWidget
  testWidgets('patient → PatientHome (not dashboard)', ...); // seed patient role + profile handler returning a patient → find.byType(PatientHome), findsOneWidget; CaregiverDashboardScreen findsNothing
  testWidgets('patient sees the static documents line', ...); // Pump PatientHome directly (already covered in shell_roles_test — keep routing assertion here: 'Your caregiver can add your health documents.' present)
});
```

Each test: `SharedPreferences.setMockInitialValues` + `_seedUser` + `HttpOverrides.global = fake` + `addTearDown` cleanup; `OfflineSyncService.instance.stop()` in teardown (stop exists, line 303) to cancel HomeShell's timer; tall surface `tester.view.physicalSize = const Size(800, 4000)`.

403-graceful case: fake backend returns 403 `{'detail': 'Active consent required...'}` for summary → expect dashboard renders without crash + the error text surfaced (existing `_error` path) — one such test.

- [ ] **Step 2: Run RED** (routing switch not yet explicit — actually the current `isStaff` already routes staff→dashboard, so family/asha/admin tests may PASS before the switch; the RED anchor: patient test passes already too. The genuinely new behavior: none on routing itself — tests lock behavior + the admin/clinical additions from Tasks 7–8. That's fine: these are contract locks, not TDD reds; Step 2 asserts they pass and Step 3 makes the switch explicit anyway.)

- [ ] **Step 3: Implement the explicit switch** in `HomeShell.build` (replace `isStaff` bool with the role check above; keep the null/patient fallthrough).

- [ ] **Step 4: Run** `flutter test test/caregiver_role_routing_test.dart` → GREEN; full suite; analyze; commit `feat(caregiver): explicit role routing switch + per-role tests (10)`.

---

### Task 11: textScaleFactor 1.3 tests

**Files:**
- Test: `mobile/test/caregiver_scale_test.dart` (new)

- [ ] **Step 1: Write tests**

```dart
Future<void> _pumpAtScale(WidgetTester tester, Widget home) async {
  addTearDown(tester.view.resetPhysicalSize);
  tester.view.physicalSize = const Size(390, 844); // phone width
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(home);
  await tester.pumpAndSettle();
}

testWidgets('dashboard renders at 1.3 scale without overflow', (tester) async {
  // fake backend (clinical summary) + pump CaregiverDashboardScreen in MaterialApp
  await _pumpAtScale(tester, const MaterialApp(home: CaregiverDashboardScreen(caregiverId: 'cg1')));
  expect(tester.takeException(), isNull);
  expect(find.text('Overview'), findsOneWidget);
});
testWidgets('audit viewer renders at 1.3 scale', ...); // pump AuditViewerScreen with fake logs
testWidgets('risk intake form renders at 1.3 scale', ...); // open dialog, takeException null
testWidgets('patient home line visible at 1.3 scale', ...);
```

- [ ] **Step 2: Run RED→GREEN** (these should pass immediately unless overflow bugs exist; if overflow found, fix layout in the offending section — wrap text with `Flexible`/adjust `childAspectRatio` — and note it).

- [ ] **Step 3: Commit** `test(caregiver): textScale 1.3 coverage (11)`.

---

### Task 12: Docs — PRD.md + ARCHITECTURE.md (Amendment 6: verify against actual files first)

**Files:**
- Modify: `PRD.md` (~line 80), `ARCHITECTURE.md` (~lines 26–28, 67, screens list ~line 60, dashboard section ~lines 66–72)
- Modify: `docs/superpowers/specs/...-design.md` (fix the Navigator.pop mechanism sentence → `onConsentMissing` callback, matching what shipped)

- [ ] **Step 1: Re-read anchors** — `grep -n "Flutter Web\|web-only\|Caregiver Dashboard" PRD.md ARCHITECTURE.md` to confirm current text (files may have drifted).
- [ ] **Step 2: Edit verified lines only:**
  - PRD row: `| Flutter Web: JWT login, patient roster, 7-day metric tiles | Built + tested |` → `| Flutter Web + mobile (role-routed: family/ASHA/clinician/admin): JWT login, patient roster, 7-day metric tiles | Built + tested |`
  - ARCHITECTURE diagram box: `│   Caregiver Dashboard      │  Flutter Web` → `│   Caregiver Dashboard      │  Flutter Web + mobile`
  - ARCHITECTURE `- **Framework:** Flutter Web (same Dart codebase as mobile)` → `- **Framework:** Flutter Web + mobile app (role-routed in mobile/lib/main.dart; same Monad design system)`
  - ARCHITECTURE screens list: add `caregiver/ (sections: switcher, alerts, metrics, trends, compliance, schedules, documents, risk_screening) + audit_viewer_screen` under `mobile/lib/screens/`
  - ARCHITECTURE dashboard "Key files" section: add one line noting the mobile port lives under `mobile/lib/screens/caregiver/` and uses `file_picker` for RAG upload (no dart:html on mobile).
- [ ] **Step 3: Spec mechanism sentence** — replace "returns its terminal status via `Navigator.pop` result" with "invokes an `onConsentMissing` callback".
- [ ] **Step 4: Commit** `docs: record mobile caregiver port in PRD + ARCHITECTURE (12)`.

---

### Task 13: Final gates

- [ ] **Step 1:** `cd mobile && flutter analyze` → no new issues (33 pre-existing infos baseline).
- [ ] **Step 2:** `cd mobile && flutter test` → full suite green (baseline 102/5 + new tests; `api_live_test` self-skips; NEVER run `integration_test/`).
- [ ] **Step 3:** `git diff --check` clean; `git status --porcelain` — only expected dirty files (user's CLAUDE.md/README/graphify edits + staged cleanup deletions) plus this feature's commits; NO dashboard/ changes: `git diff fix/app-breakage-wave1-7...HEAD -- dashboard/` must be empty.
- [ ] **Step 4:** `graphify update .` (AST-only).
- [ ] **Step 5:** Append ledger entry to `.superpowers/sdd/PLAN/progress.md` (port complete, commit list).
- [ ] **Step 6:** Final report to user: commit list, test counts, anything deferred.

---

## Self-Review (writing-plans checklist)

1. **Spec coverage:** API endpoints (T1) ✓; dev menu kDebugMode (T2) ✓; patient line (T2) ✓; extractions all 8 sections (T3–T7) ✓; consent states on documents (T6) + screening (T8) ✓; file_picker (T9) ✓; role routing + audit entry (T7, T10) ✓; risk screening incl. card/intake/section (T8) ✓; per-role tests (T10) ✓; textScale 1.3 (T11) ✓; docs (T12) ✓; gates (T13) ✓; 48px targets — noted in Global Constraints, applied at AppBar icons (T7) ✓.
2. **Placeholder scan:** T1 Step 2's 401-test draft has a leftover confused expression — fixed inline by the note below it (first call 401, second 200). All other steps carry concrete code/commands. `patientName` helper in T8 specified (`_patientName` derives from `_patients`).
3. **Type consistency:** `onConsentMissing` name consistent T6/T8; `uploadDocument`/`submitRiskScreening` signatures match across T1/T8/T9; section widget names consistent with call sites in T10 tests (`CaregiverDashboardScreen`, `AuditViewerScreen`, `RiskScreeningSection`).

/// Wave 2 Batch D tests (fix-it PLAN task 2.5-mobile): clinical notes save
/// for real by riding the existing `offline_symptom` pipeline — no new enum,
/// no migration.
///
/// - `OfflineSyncService.clinicalNoteItem` builds the exact envelope item the
///   backend `/api/v1/sync` + `consume_sync_queue` already materialize into an
///   encrypted `SymptomLog` (unit-tested without a database; the flush path
///   `syncNow`/`_pushGeneric` already posts the correct envelope — verified by
///   inspection, unchanged).
/// - `ClinicalNotesScreen` maps severities low→2/medium→3/high→4, attributes
///   `entered_by`/`source` from the signed-in user, and shows queued state.
///
/// No live server: enqueue is captured by `FakeClinicalSync`; auth is seeded
/// through the real `AuthSession` via a `SharedPreferences` mock.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:eldercare_mobile/screens/clinical_notes_screen.dart';
import 'package:eldercare_mobile/services/auth_session.dart';
import 'package:eldercare_mobile/services/offline_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CapturedClinicalNote {
  final String patientId;
  final String enteredBy;
  final String source;
  final int severity;
  final String notes;
  final DateTime recordedAt;

  const CapturedClinicalNote({
    required this.patientId,
    required this.enteredBy,
    required this.source,
    required this.severity,
    required this.notes,
    required this.recordedAt,
  });
}

/// Records `enqueueClinicalNote` calls without touching the database or the
/// network (same pattern as `FakeSync` in `odd_one_out_screen_test.dart`).
class FakeClinicalSync extends OfflineSyncService {
  final List<CapturedClinicalNote> notes = [];

  @override
  Future<void> enqueueClinicalNote({
    required String patientId,
    required String enteredBy,
    required String source,
    required int severity,
    required String notes,
    required DateTime recordedAt,
  }) async {
    this.notes.add(CapturedClinicalNote(
          patientId: patientId,
          enteredBy: enteredBy,
          source: source,
          severity: severity,
          notes: notes,
          recordedAt: recordedAt,
        ));
  }
}

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

Future<void> _seedUser({required String id, required String role}) async {
  SharedPreferences.setMockInitialValues({
    'auth.access': 'test-access',
    'auth.refresh': 'test-refresh',
    'auth.user': jsonEncode({
      'id': id,
      'phone': '+910000000001',
      'role': role,
      'preferred_language': 'english',
    }),
  });
  await AuthSession.instance.restore();
}

Future<void> _pumpScreen(WidgetTester tester, FakeClinicalSync sync) async {
  addTearDown(tester.view.resetPhysicalSize);
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    MaterialApp(home: ClinicalNotesScreen(patientId: 'p1', sync: sync)),
  );
  await tester.pumpAndSettle();
}

Future<void> _saveWith(
  WidgetTester tester, {
  String observation = '',
  String notes = '',
  String? severityChip,
}) async {
  if (severityChip != null) {
    await tester.tap(find.text(severityChip));
    await tester.pump();
  }
  await tester.enterText(find.byType(TextField).at(0), observation);
  await tester.enterText(find.byType(TextField).at(1), notes);
  // MonadPillButton renders the label uppercased with a trailing "▸".
  await tester.tap(find.text('SAVE NOTES ▸'));
  await tester.pumpAndSettle();
}

// Minimal HTTP stub: only used to keep the `tearDownAll` logout local (the
// screen itself performs no HTTP in these tests — everything is enqueued).
class _StubHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _StubClient();
}

class _StubClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _StubRequest();

  @override
  void close({bool force = false}) {}
}

class _StubRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _StubHeaders();

  @override
  void write(Object? obj) {}

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {}
  }

  @override
  Future<HttpClientResponse> close() async => _StubResponse();
}

class _StubHeaders extends Fake implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  String? value(String name) {
    final v = _values[name.toLowerCase()];
    return v == null || v.isEmpty ? null : v.join(',');
  }

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];
}

class _StubResponse extends Stream<List<int>> implements HttpClientResponse {
  _StubResponse() : _bytes = utf8.encode('{}');

  final List<int> _bytes;

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpHeaders get headers {
    final h = _StubHeaders();
    h.set('content-type', 'application/json');
    return h;
  }

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  List<Cookie> get cookies => const [];

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.value(_bytes).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

void main() {
  // FakeClinicalSync builds a lazy (never opened) AppDatabase per instance;
  // silence drift's multiple-database warning for these unopened test doubles.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  tearDownAll(() async {
    // Leave the AuthSession singleton clean for any other test in this
    // isolate; the stub keeps the logout fully local (no live server).
    HttpOverrides.global = _StubHttp();
    try {
      await AuthSession.instance.logout();
    } finally {
      HttpOverrides.global = null;
    }
  });

  group('clinicalNoteItem envelope (offline_symptom pipeline)', () {
    test('builds the exact envelope item the backend consumer expects', () {
      final recordedAt = DateTime.utc(2026, 9, 22, 10, 30);
      final item = OfflineSyncService.clinicalNoteItem(
        patientId: 'patient-1',
        enteredBy: 'user-asha-1',
        source: 'manual_asha',
        severity: 3,
        notes: 'walking slower than usual',
        recordedAt: recordedAt,
      );

      expect(item.resourceType, 'offline_symptom');
      expect(item.operation, 'create');
      expect(item.patientId, 'patient-1');
      // Timestamp-based local queue id (no uuid package), like the other
      // enqueue helpers (`ack_<ms>_<eventId>`).
      expect(item.id, startsWith('clinical_'));
      expect(item.id, contains('patient-1'));
      // Backend `/api/v1/sync` requires a UUID resource_id.
      expect(item.resourceId, matches(_uuidV4));
      expect(
        item.payload,
        {
          'entered_by': 'user-asha-1',
          'source': 'manual_asha',
          'severity': 3,
          'notes': 'walking slower than usual',
          'recorded_at': recordedAt.toIso8601String(),
        },
      );
      expect(DateTime.parse(item.payload['recorded_at'] as String),
          recordedAt);
    });

    test('resource ids are unique per note', () {
      final at = DateTime.utc(2026, 9, 22, 10, 30);
      final a = OfflineSyncService.clinicalNoteItem(
        patientId: 'p1',
        enteredBy: 'u1',
        source: 'manual_asha',
        severity: 2,
        notes: 'a',
        recordedAt: at,
      );
      final b = OfflineSyncService.clinicalNoteItem(
        patientId: 'p1',
        enteredBy: 'u1',
        source: 'manual_asha',
        severity: 2,
        notes: 'b',
        recordedAt: at,
      );
      // Client-generated UUID v4 resource ids (backend requires UUIDs).
      expect(a.resourceId, isNot(b.resourceId));
    });

    test('rejects severity outside the 1-5 SymptomLog scale', () {
      expect(
        () => OfflineSyncService.clinicalNoteItem(
          patientId: 'p1',
          enteredBy: 'u1',
          source: 'manual_asha',
          severity: 9,
          notes: 'a',
          recordedAt: DateTime.utc(2026, 9, 22),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ClinicalNotesScreen save', () {
    // Runs first on the pristine AuthSession singleton (no user seeded):
    // an unauthenticated save must fail loudly instead of losing the note.
    testWidgets('no signed-in user shows "sign in again" and enqueues nothing',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final sync = FakeClinicalSync();
      await _pumpScreen(tester, sync);

      await _saveWith(tester, notes: 'unsaved without a user');
      expect(find.textContaining('sign in again'), findsOneWidget);
      expect(sync.notes, isEmpty);
    });

    testWidgets('asha worker queues a manual_asha note and shows queued state',
        (tester) async {
      await _seedUser(id: 'user-asha-1', role: 'asha_worker');
      final sync = FakeClinicalSync();
      await _pumpScreen(tester, sync);

      await _saveWith(
        tester,
        observation: 'walking slower',
        notes: 'detailed clinical note',
      );

      expect(sync.notes, hasLength(1));
      final queued = sync.notes.single;
      expect(queued.patientId, 'p1');
      expect(queued.enteredBy, 'user-asha-1');
      expect(queued.source, 'manual_asha');
      // Default severity chip is low → 2 on the 1-5 scale.
      expect(queued.severity, 2);
      // The brief observation field rides along inside the locked payload.
      expect(queued.notes, contains('walking slower'));
      expect(queued.notes, contains('detailed clinical note'));
      expect(find.text('Queued — will send when online.'), findsOneWidget);
      // Fields clear only on success…
      expect(find.text('detailed clinical note'), findsNothing);
    });

    testWidgets('medium severity maps to 3', (tester) async {
      await _seedUser(id: 'user-asha-1', role: 'asha_worker');
      final sync = FakeClinicalSync();
      await _pumpScreen(tester, sync);

      await _saveWith(
          tester, notes: 'medium note', severityChip: 'medium');

      expect(sync.notes, hasLength(1));
      expect(sync.notes.single.severity, 3);
      expect(find.text('Queued — will send when online.'), findsOneWidget);
    });

    testWidgets('caregiver queues manual_caregiver with high mapping to 4',
        (tester) async {
      await _seedUser(id: 'user-cg-1', role: 'family_caregiver');
      final sync = FakeClinicalSync();
      await _pumpScreen(tester, sync);

      await _saveWith(tester, notes: 'high note', severityChip: 'high');

      expect(sync.notes, hasLength(1));
      expect(sync.notes.single.source, 'manual_caregiver');
      expect(sync.notes.single.severity, 4);
      expect(sync.notes.single.enteredBy, 'user-cg-1');
      expect(find.text('Queued — will send when online.'), findsOneWidget);
    });

    testWidgets('empty notes are rejected without enqueueing', (tester) async {
      await _seedUser(id: 'user-asha-1', role: 'asha_worker');
      final sync = FakeClinicalSync();
      await _pumpScreen(tester, sync);

      await _saveWith(tester, notes: '   ');
      expect(find.text('Please enter notes.'), findsOneWidget);
      expect(sync.notes, isEmpty);
    });
  });
}

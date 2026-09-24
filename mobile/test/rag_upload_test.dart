/// Wave 2C task 2.4-mobile: RAG upload auth + staff-only entry + 403 detail.
/// TDD red: helpers + seams do not exist yet.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eldercare_mobile/main.dart';
import 'package:eldercare_mobile/screens/caregiver/sections/documents_card.dart';
import 'package:eldercare_mobile/screens/caregiver_dashboard_screen.dart';
import 'package:eldercare_mobile/screens/rag_upload_screen.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef _Handler = ({int status, Object? json}) Function(
    String method, Uri uri, String body);

class _FakeBackend extends HttpOverrides {
  _FakeBackend(this.handler);

  final _Handler handler;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeClient(this);
}

class _FakeClient extends Fake implements HttpClient {
  _FakeClient(this.backend);

  final _FakeBackend backend;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(backend, method, url);

  @override
  void close({bool force = false}) {}
}

class _FakeRequest extends Fake implements HttpClientRequest {
  _FakeRequest(this.backend, this.method, this.uri);

  final _FakeBackend backend;

  @override
  final String method;

  @override
  final Uri uri;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  final StringBuffer _body = StringBuffer();

  @override
  void write(Object? obj) => _body.write(obj);

  @override
  void add(List<int> data) => _body.write(utf8.decode(data));

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _body.write(utf8.decode(chunk));
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final res = backend.handler(method, uri, _body.toString());
    return _FakeResponse(res.status, res.json);
  }
}

class _FakeHeaders extends Fake implements HttpHeaders {
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

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, Object? jsonBody)
      : _bytes = utf8.encode(jsonBody == null ? '' : jsonEncode(jsonBody));

  @override
  final int statusCode;

  final List<int> _bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.value(_bytes).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  int get contentLength => _bytes.length;

  @override
  HttpHeaders get headers {
    final h = _FakeHeaders();
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
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';

  @override
  List<Cookie> get cookies => const [];

  @override
  List<RedirectInfo> get redirects => const [];
}

void main() {
  group('2.4-mobile (a) auth header', () {
    test('upload request carries Authorization header + fields + file',
        () async {
      ApiService.instance.authToken = 'tok-mobile-123';
      addTearDown(() => ApiService.instance.authToken = null);

      final req = buildRagUploadRequest(
        patientId: 'p1',
        bytes: Uint8List.fromList(utf8.encode('hello')),
        filename: 'note.pdf',
        authToken: ApiService.instance.authToken,
        baseUrl: 'http://fake.invalid',
      );

      expect(req.url.path, '/api/v1/reports/documents/upload');
      expect(req.headers['Authorization'], 'Bearer tok-mobile-123');
      expect(req.fields['patient_id'], 'p1');
      expect(req.fields['doc_type'], 'prescription');
      expect(req.fields['title'], isNotEmpty);
      expect(req.files, hasLength(1));
      expect(req.files.single.field, 'file');
      expect(req.files.single.filename, 'note.pdf');
    });
  });

  group('2.4-mobile (c) 403 detail', () {
    test('formats server detail with clinical-tier/consent hint', () {
      final msg = formatRagUploadFailure(
          403, jsonEncode({'detail': 'clinical tier required'}));
      expect(msg, contains('clinical tier required'));
      expect(msg.toLowerCase(), contains('consent'));
      expect(msg, isNot('HTTP 403'));
      expect(msg, isNot(contains('Failed: HTTP 403 — {}')));
    });
  });

  group('2.4-mobile (b) staff-only entry', () {
    testWidgets('patient home has no Medical Documents entry',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(home: PatientHome(patientId: 'p1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Medical Documents'), findsNothing);
    });

    testWidgets('403 surfaces server detail, never a bare code',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(
        home: RagUploadScreen(
          patientId: 'p1',
          testBytes: Uint8List.fromList(utf8.encode('hello')),
          testFilename: 'note.pdf',
          sendForTest: (req) async => http.Response(
            jsonEncode({'detail': 'clinical tier required'}),
            403,
            headers: const {'Content-Type': 'application/json'},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Select File is a no-op seam when testBytes are provided; Upload
      // must be enabled (primary variant appends the ▸ glyph).
      await tester.tap(find.text('UPLOAD ▸'));
      await tester.pumpAndSettle();

      expect(find.textContaining('clinical tier required'), findsOneWidget);
      expect(find.text('Failed: HTTP 403'), findsNothing);
    });
  });

  group('2.4-mobile staff surface', () {
    testWidgets('caregiver dashboard exposes Medical Documents upload',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final backend = _FakeBackend((method, uri, body) {
        final p = uri.path;
        if (p == '/api/v1/dashboard/caregivers/cg1/patients') {
          return (
            status: 200,
            json: [
              {
                'patient_id': 'p1',
                'name': 'Test Patient',
                'district': 'Kamrup',
                'relationship_type': 'family',
              }
            ]
          );
        }
        if (p == '/api/v1/dashboard/patients/p1/summary') {
          return (
            status: 200,
            json: {
              'active_alerts': [],
              'clinical_flags': {},
              'view': 'clinical',
              'compliance_pct': 80,
              'games_played': 2,
              'reminders_acknowledged': 8,
              'reminders_total': 10,
              'reminders_missed': 0,
              'daily_trends': [],
            }
          );
        }
        if (p == '/api/v1/reminders/patients/p1/events' ||
            p == '/api/v1/reminders/schedules/p1') {
          return (status: 200, json: []);
        }
        if (p == '/api/v1/compliance/audit-logs') {
          return (status: 200, json: []);
        }
        return (status: 404, json: {'detail': 'not found: $p'});
      });

      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        const MaterialApp(home: CaregiverDashboardScreen(caregiverId: 'cg1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Medical Documents'), findsWidgets);
      expect(find.text('UPLOAD DOCUMENT'), findsOneWidget);
    });
  });

  group('task 6 consent state', () {
    testWidgets('consent 403 fires onConsentMissing + lastOutcome',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var consentFired = false;
      late RagUploadScreen screen;
      screen = RagUploadScreen(
        patientId: 'p1',
        testBytes: Uint8List.fromList(utf8.encode('x')),
        testFilename: 'n.pdf',
        onConsentMissing: () => consentFired = true,
        sendForTest: (req) async => http.Response(
          jsonEncode(
              {'detail': "Active consent required for scope 'health_data'"}),
          403,
          headers: const {'Content-Type': 'application/json'},
        ),
      );
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      await tester.tap(find.text('UPLOAD ▸'));
      await tester.pumpAndSettle();

      // Structural consent state fires...
      expect(consentFired, isTrue);
      final state =
          tester.state<State<RagUploadScreen>>(find.byType(RagUploadScreen));
      expect((state as dynamic).lastOutcome, 'consent_missing');
      // ...AND the formatted failure still renders inline (no silence).
      expect(find.textContaining("scope 'health_data'"), findsOneWidget);
      expect(find.textContaining('Upload failed'), findsOneWidget);
      expect(screen, isNotNull);
    });

    testWidgets(
        'DocumentsCard consentMissing=true renders exact consent copy + button',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DocumentsCard(
            patientId: 'p1',
            consentMissing: true,
            isClinical: true,
            onUpload: () => tapped = true,
          ),
        ),
      ));

      expect(
        find.text(
            "health_data consent required — this patient has not granted consent for health data, so documents can't be uploaded until they do."),
        findsOneWidget,
      );
      expect(find.text('Medical Documents'), findsOneWidget);
      expect(find.text('UPLOAD DOCUMENT'), findsOneWidget);
      expect(find.textContaining('They are embedded and searchable'),
          findsNothing);

      await tester.tap(find.text('UPLOAD DOCUMENT'));
      expect(tapped, isTrue);
    });

    testWidgets('DocumentsCard consentMissing=false renders normal helper text',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DocumentsCard(
            patientId: 'p1',
            consentMissing: false,
            isClinical: true,
            onUpload: () {},
          ),
        ),
      ));

      expect(find.textContaining('health_data consent required'), findsNothing);
      expect(
        find.text(
          'Upload prescriptions, discharge summaries, care plans. '
          'They are embedded and searchable in the clinical Q&A flow.',
        ),
        findsOneWidget,
      );
      expect(find.text('Medical Documents'), findsOneWidget);
      expect(find.text('UPLOAD DOCUMENT'), findsOneWidget);
    });
  });

  testWidgets(
      'DocumentsCard basic view renders the health-worker lock, no button',
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
}

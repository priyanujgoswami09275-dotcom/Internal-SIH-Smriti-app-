/// Task 11 — textScaleFactor 1.3 coverage locks for caregiver-port surfaces.
///
/// These are coverage locks, not TDD: they must pass immediately unless a
/// genuine RenderFlex overflow (or similar) exists at 1.3 on a 390×844
/// phone. Fake HTTP (HttpOverrides) where the surface fetches — no live
/// server. Do NOT pump HomeShell here (it starts OfflineSyncService's
/// periodic timer).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eldercare_mobile/main.dart';
import 'package:eldercare_mobile/screens/caregiver/audit_viewer_screen.dart';
import 'package:eldercare_mobile/screens/caregiver_dashboard_screen.dart';
import 'package:eldercare_mobile/screens/documents_screen.dart';
import 'package:eldercare_mobile/screens/rag_qa_screen.dart';
import 'package:eldercare_mobile/screens/rag_upload_screen.dart';
import 'package:eldercare_mobile/screens/risk_intake_screen.dart';
import 'package:eldercare_mobile/services/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

typedef _Handler = ({int status, Object? json}) Function(
    String method, Uri uri, String body);

class _FakeBackend extends HttpOverrides {
  _FakeBackend(this.handler);

  final _Handler handler;
  final List<({String method, Uri uri, String body})> requests = [];

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
    final body = _body.toString();
    backend.requests.add((method: method, uri: uri, body: body));
    final res = backend.handler(method, uri, body);
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

/// 390×844 phone viewport + textScaleFactor 1.3 — exact per task ruling.
Future<void> _pumpAtScale(WidgetTester tester, Widget home) async {
  addTearDown(tester.view.resetPhysicalSize);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(home);
  await tester.pumpAndSettle();
}

/// Clinical dashboard backend: roster + clinical summary (daily_trends
/// non-empty) + events + schedules + risk rehydration + audit-logs.
_FakeBackend _dashboardBackend() {
  return _FakeBackend((method, uri, body) {
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
          'active_alerts': <dynamic>[],
          'clinical_flags': <String, dynamic>{},
          'view': 'clinical',
          'patient_name': 'Test Patient',
          'compliance_pct': 80,
          'accuracy_pct': 72.0,
          'games_played': 2,
          'reminders_acknowledged': 8,
          'reminders_total': 10,
          'reminders_missed': 0,
          'daily_trends': [
            {
              'day': '2026-09-21',
              'accuracy_pct': 80,
              'avg_response_time_ms': 1200,
            },
            {
              'day': '2026-09-22',
              'accuracy_pct': 75,
              'avg_response_time_ms': 1400,
            },
          ],
        }
      );
    }
    if (p == '/api/v1/reminders/patients/p1/events') {
      return (
        status: 200,
        json: [
          {
            'id': 'e1',
            'schedule_id': 's1',
            'patient_id': 'p1',
            'scheduled_at': '2026-09-21T08:00:00Z',
            'status': 'pending',
          },
          {
            'id': 'e2',
            'schedule_id': 's1',
            'patient_id': 'p1',
            'scheduled_at': '2026-09-21T20:00:00Z',
            'status': 'acknowledged',
            'acknowledged_at': '2026-09-21T20:05:00Z',
            'acknowledgment_method': 'tap',
          },
        ]
      );
    }
    if (p == '/api/v1/reminders/schedules/p1') {
      return (
        status: 200,
        json: [
          {
            'id': 's1',
            'patient_id': 'p1',
            'reminder_type': 'medicine',
            'cadence': 'daily',
            'is_active': true,
            'created_at': '2026-09-01T00:00:00Z',
          }
        ]
      );
    }
    if (p == '/api/v1/patients/p1/risk-screening') {
      return (status: 200, json: {'status': 'not_assessed'});
    }
    if (p == '/api/v1/compliance/audit-logs') {
      return (
        status: 200,
        json: [
          {
            'action': 'read',
            'resource_type': 'patient',
            'user_id': 'u1',
            'timestamp': '2026-09-21T10:00:00Z',
          },
          {
            'action': 'update',
            'resource_type': 'consent',
            'user_id': 'u2',
            'timestamp': '2026-09-21T11:00:00Z',
          },
        ]
      );
    }
    return (status: 404, json: {'detail': 'not found: $p'});
  });
}

/// Audit-logs-only backend for the standalone AuditViewerScreen.
_FakeBackend _auditBackend() {
  return _FakeBackend((method, uri, body) {
    if (uri.path == '/api/v1/compliance/audit-logs') {
      return (
        status: 200,
        json: [
          {
            'action': 'read',
            'resource_type': 'patient',
            'user_id': 'u1',
            'timestamp': '2026-09-21T10:00:00Z',
          },
          {
            'action': 'update',
            'resource_type': 'consent',
            'user_id': 'u2',
            'timestamp': '2026-09-21T11:00:00Z',
          },
        ]
      );
    }
    return (status: 404, json: {'detail': 'not found: ${uri.path}'});
  });
}

void _installBackend(_FakeBackend backend) {
  HttpOverrides.global = backend;
  addTearDown(() => HttpOverrides.global = null);
}

void main() {
  group('textScaleFactor 1.3 coverage locks (390×844)', () {
    testWidgets('dashboard renders at 1.3 scale without overflow',
        (tester) async {
      await _seedUser(id: 'u1', role: 'clinician');
      _installBackend(_dashboardBackend());
      await _pumpAtScale(
        tester,
        const MaterialApp(home: CaregiverDashboardScreen(caregiverId: 'cg1')),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Overview'), findsOneWidget);
    });

    testWidgets('audit viewer renders at 1.3 scale without overflow',
        (tester) async {
      await _seedUser(id: 'admin-1', role: 'admin');
      _installBackend(_auditBackend());
      await _pumpAtScale(tester, const MaterialApp(home: AuditViewerScreen()));

      expect(tester.takeException(), isNull);
      // AppBar title + card heading both say "DPDP audit trail" once loaded.
      expect(find.text('DPDP audit trail'), findsWidgets);
    });

    testWidgets('risk intake form renders at 1.3 scale without overflow',
        (tester) async {
      await _seedUser(id: 'u1', role: 'clinician');
      await _pumpAtScale(
        tester,
        MaterialApp(
          home: RiskIntakeScreen(
            patientId: 'p1',
            patientName: 'Test Patient',
            onResult: (_) {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Risk screening'), findsOneWidget);
      expect(
        find.text('32 clinical inputs · Test Patient'),
        findsOneWidget,
      );
    });

    testWidgets('patient home line visible at 1.3 scale without overflow',
        (tester) async {
      await _seedUser(id: 'u5', role: 'patient');
      await _pumpAtScale(
        tester,
        const MaterialApp(home: PatientHome(patientId: 'p1')),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('Your health worker can add your health documents.'),
        findsOneWidget,
      );
    });

    testWidgets('rag upload screen renders at 1.3 scale without overflow',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpAtScale(
        tester,
        const MaterialApp(home: RagUploadScreen(patientId: 'p1')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('documents hub renders at 1.3 scale without overflow',
        (tester) async {
      final backend = _FakeBackend((method, uri, body) =>
          (status: 200, json: {'documents': [], 'count': 0}));
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      await _pumpAtScale(
        tester,
        const MaterialApp(home: DocumentsScreen(patientId: 'p1')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('rag qa screen renders at 1.3 scale without overflow',
        (tester) async {
      await _pumpAtScale(
        tester,
        const MaterialApp(home: RagQaScreen(patientId: 'p1')),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

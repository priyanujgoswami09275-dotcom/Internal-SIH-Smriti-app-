/// Task 8 (reconcile): risk-screening section gating + consent state.
///
/// Mock-HTTP only (HttpOverrides fake — no live server). Scaffold copied
/// from schedule_delete_contract_test.dart. RED: RiskScreeningSection /
/// consent state do not exist yet.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eldercare_mobile/screens/caregiver_dashboard_screen.dart';
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

_Json _roster() => (
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

_Json _summary(String view) => (
      status: 200,
      json: {
        'active_alerts': [],
        'clinical_flags': {},
        'view': view,
        'patient_name': 'Test Patient',
        'compliance_pct': 80,
        'accuracy_pct': 72.0, // clinical MetricsTiles casts num→double
        'games_played': 2,
        'reminders_acknowledged': 8,
        'reminders_total': 10,
        'reminders_missed': 0,
        'daily_trends': [],
      }
    );

typedef _Json = ({int status, Object? json});

_FakeBackend _dashboardBackend(
  String view, {
  _Json? Function(String method, Uri uri, String body)? onRiskPost,
}) {
  return _FakeBackend((method, uri, body) {
    final p = uri.path;
    if (p == '/api/v1/dashboard/caregivers/cg1/patients') return _roster();
    if (p == '/api/v1/dashboard/patients/p1/summary') return _summary(view);
    if (p == '/api/v1/reminders/patients/p1/events' ||
        p == '/api/v1/reminders/schedules/p1') {
      return (status: 200, json: <dynamic>[]);
    }
    if (p == '/api/v1/patients/p1/risk-screening') {
      if (method == 'POST' && onRiskPost != null) {
        final forced = onRiskPost(method, uri, body);
        if (forced != null) return forced;
      }
      // GET rehydration (clinical): not assessed yet.
      return (status: 200, json: {'status': 'not_assessed'});
    }
    if (p == '/api/v1/compliance/audit-logs') {
      return (status: 200, json: <dynamic>[]);
    }
    return (status: 404, json: {'detail': 'not found: $p'});
  });
}

Future<void> _pumpDashboard(WidgetTester tester, _FakeBackend backend) async {
  HttpOverrides.global = backend;
  addTearDown(() => HttpOverrides.global = null);
  addTearDown(tester.view.resetPhysicalSize);
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    const MaterialApp(home: CaregiverDashboardScreen(caregiverId: 'cg1')),
  );
  await tester.pumpAndSettle();
}

/// The intake screen's first TextField is Age.
Future<void> _enterAge(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField).first, value);
}

/// Buttons uppercase their label; this Flutter's textContaining is
/// case-sensitive (no matchCase param), so match case-insensitively.
Finder _runScreeningOnDashboard() =>
    find.textContaining(RegExp('Run Screening', caseSensitive: false));

void main() {
  group('task 8 risk screening section', () {
    testWidgets('basic tier: locked note, no Run Screening', (tester) async {
      await _seedUser(id: 'u1', role: 'clinician');
      final backend = _dashboardBackend('basic');
      await _pumpDashboard(tester, backend);

      // Risk-lock note specifically (the Trends basic lock shares the
      // 'linked clinical staff only' tail, so pin the screening wording).
      expect(
        find.textContaining('Screening needs clinical tier / health-data consent'),
        findsOneWidget,
      );
      expect(find.textContaining('linked clinical staff only'), findsWidgets);
      expect(_runScreeningOnDashboard(), findsNothing);
      expect(find.text('COGNITIVE RISK SCREENING'), findsNothing);
    });

    testWidgets('clinical tier: card + button visible', (tester) async {
      await _seedUser(id: 'u1', role: 'clinician');
      final backend = _dashboardBackend('clinical');
      await _pumpDashboard(tester, backend);

      expect(_runScreeningOnDashboard(), findsOneWidget);
      expect(find.text('COGNITIVE RISK SCREENING'), findsOneWidget);
      expect(
        find.textContaining('Screening needs clinical tier'),
        findsNothing,
      );
    });

    testWidgets('intake submits payload; result renders score',
        (tester) async {
      await _seedUser(id: 'u1', role: 'clinician');
      final backend = _dashboardBackend('clinical', onRiskPost: (m, u, b) {
        if (m != 'POST') return null;
        return (
          status: 200,
          json: {
            'status': 'ok',
            'risk_score': 41,
            'tier': 'moderate_risk',
            'probability': 0.41,
            'feature_count': 32,
          }
        );
      });
      await _pumpDashboard(tester, backend);

      await tester.tap(_runScreeningOnDashboard());
      await tester.pumpAndSettle();
      expect(find.text('Risk screening'), findsOneWidget);

      await _enterAge(tester, '72');
      await tester.tap(find.text('RUN SCREENING ▸'));
      await tester.pumpAndSettle();

      final posts = backend.requests
          .where((r) =>
              r.method == 'POST' &&
              r.uri.path == '/api/v1/patients/p1/risk-screening')
          .toList();
      expect(posts, hasLength(1));
      expect(posts.single.body, contains('"Age":72'));

      // Intake popped itself; dashboard card shows the real score format.
      expect(find.textContaining('Score: 41 / 100'), findsOneWidget);
      expect(find.text('Risk screening'), findsOneWidget);
    });

    testWidgets('consent 403 → section shows consent-required state',
        (tester) async {
      await _seedUser(id: 'u1', role: 'clinician');
      final backend = _dashboardBackend('clinical', onRiskPost: (m, u, b) {
        if (m != 'POST') return null;
        return (
          status: 403,
          json: {'detail': "Active consent required for scope 'health_data'"}
        );
      });
      await _pumpDashboard(tester, backend);

      await tester.tap(_runScreeningOnDashboard());
      await tester.pumpAndSettle();
      await _enterAge(tester, '72');
      await tester.tap(find.text('RUN SCREENING ▸'));
      await tester.pumpAndSettle();

      // Intake keeps rendering its inline error (no silence)...
      expect(find.textContaining("scope 'health_data'"), findsOneWidget);

      // ...navigate back → dashboard section shows the consent state.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('health_data consent required'),
        findsOneWidget,
      );
      expect(_runScreeningOnDashboard(), findsOneWidget);
    });
  });
}

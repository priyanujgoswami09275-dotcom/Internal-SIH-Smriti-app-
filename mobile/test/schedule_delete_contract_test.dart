/// Wave 2 Batch A contract tests (fix-it PLAN tasks 2.1 + 2.6-mobile).
///
/// 2.1 (deleteSchedule prefix) is ALREADY APPLIED in
/// `lib/services/api_service.dart` — this file only verifies + locks it:
/// the DELETE must go to `/api/v1/reminders/schedules/{id}`.
///
/// 2.6-mobile (audit-trail keys): the backend `GET /compliance/audit-logs`
/// returns `user_id` + `timestamp`; the caregiver dashboard must render those
/// (not `actor_id` / `created_at`, which render every row as "by system").
///
/// Both tests run the REAL ApiService + REAL widgets against a fake HTTP
/// transport (HttpOverrides). No live server, no new dependencies.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eldercare_mobile/screens/caregiver_dashboard_screen.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handler result: HTTP status + JSON-encodable body (null = empty body).
typedef _Handler = ({int status, Object? json}) Function(
    String method, Uri uri, String body);

/// Fake HTTP backend. Intercepts package:http at the dart:io layer so the
/// real ApiService code (real paths, real methods) is exercised for any host
/// — including the Android-emulator base URL flutter tests resolve to.
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

void main() {
  group('2.1 deleteSchedule prefix (applied — verify + lock)', () {
    test('sends DELETE to /api/v1/reminders/schedules/{id}', () async {
      final backend = _FakeBackend((method, uri, body) {
        return (status: 200, json: null);
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      await ApiService(baseUrl: 'http://fake.invalid')
          .deleteSchedule('sched-123');

      expect(backend.requests, hasLength(1));
      expect(backend.requests.single.method, 'DELETE');
      expect(backend.requests.single.uri.path,
          startsWith('/api/v1/reminders/schedules/'));
      expect(backend.requests.single.uri.path,
          '/api/v1/reminders/schedules/sched-123');
    });
  });

  group('2.6-mobile audit-trail keys', () {
    testWidgets('audit row shows user_id + timestamp, never bare "system"',
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
              'view': 'basic',
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
          return (
            status: 200,
            json: [
              {
                'action': 'read',
                'resource_type': 'x',
                'user_id': 'u1',
                'timestamp': 't1',
              }
            ]
          );
        }
        return (status: 404, json: {'detail': 'not found: $p'});
      });

      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      // Tall test surface so the lazily-built ListView lays out all the
      // way down to the audit card — no scrolling needed.
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        const MaterialApp(home: CaregiverDashboardScreen(caregiverId: 'cg1')),
      );
      await tester.pumpAndSettle();

      // Row built from user_id/timestamp renders the real actor + time…
      expect(find.text('by u1 · t1'), findsOneWidget);
      // …and never the "system" fallback when user_id is present.
      expect(find.textContaining('by system'), findsNothing);
    });
  });
}

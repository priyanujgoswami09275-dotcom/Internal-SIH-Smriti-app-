/// Task 10 — explicit role-routing contract locks for `HomeShell.build`.
///
/// Each test seeds a server-issued role through SharedPreferences (the real
/// AuthSession restore path), pumps `HomeShell` against a fake HTTP backend
/// (HttpOverrides — no live server), and asserts the surface that role must
/// see. These lock the existing `isStaff` behaviour before/after the explicit
/// role switch lands in `main.dart`.
///
/// Teardown always stops `OfflineSyncService.instance` (HomeShell.initState
/// starts its periodic timer — leaving it running hangs the test).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eldercare_mobile/main.dart';
import 'package:eldercare_mobile/screens/caregiver/sections/patient_switcher.dart';
import 'package:eldercare_mobile/screens/caregiver_dashboard_screen.dart';
import 'package:eldercare_mobile/services/auth_session.dart';
import 'package:eldercare_mobile/services/offline_sync_service.dart';
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
typedef _Json = ({int status, Object? json});

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

/// Roster + summary + secondary-view backend for HomeShell role tests.
///
/// Unknown paths (including OfflineSyncService's `/language/status` probe)
/// fall through to 404 — probeOnline treats that as offline and skips the
/// local DB flush, keeping widget tests free of drift/SQLite I/O.
_FakeBackend _shellBackend({
  List<Map<String, dynamic>>? roster,
  _Json? summaryOverride,
  String summaryView = 'basic',
  double? accuracyPct,
  List<Map<String, dynamic>> dailyTrends = const [],
  _Json? myPatient,
}) {
  roster ??= [
    {
      'patient_id': 'p1',
      'name': 'Test Patient',
      'district': 'Kamrup',
      'relationship_type': 'family',
    }
  ];
  return _FakeBackend((method, uri, body) {
    final p = uri.path;
    if (p.startsWith('/api/v1/dashboard/caregivers/')) {
      return (status: 200, json: roster);
    }
    if (p.endsWith('/summary')) {
      final override = summaryOverride;
      if (override != null) return override;
      return (
        status: 200,
        json: {
          'active_alerts': <dynamic>[],
          'clinical_flags': <String, dynamic>{},
          'view': summaryView,
          'patient_name': 'Test Patient',
          'compliance_pct': 80,
          if (accuracyPct != null) 'accuracy_pct': accuracyPct,
          'games_played': 2,
          'reminders_acknowledged': 8,
          'reminders_total': 10,
          'reminders_missed': 0,
          'daily_trends': dailyTrends,
        }
      );
    }
    if (p == '/api/v1/patients/me') {
      return myPatient ?? (status: 404, json: {'detail': 'no profile'});
    }
    if (p.startsWith('/api/v1/reminders/patients/') ||
        p.startsWith('/api/v1/reminders/schedules/')) {
      return (status: 200, json: <dynamic>[]);
    }
    if (p.endsWith('/risk-screening')) {
      return (status: 200, json: {'status': 'not_assessed'});
    }
    if (p == '/api/v1/compliance/audit-logs') {
      return (status: 200, json: <dynamic>[]);
    }
    return (status: 404, json: {'detail': 'not found: $p'});
  });
}

Future<void> _pumpShell(WidgetTester tester, _FakeBackend backend) async {
  HttpOverrides.global = backend;
  addTearDown(() => HttpOverrides.global = null);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(OfflineSyncService.instance.stop);
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(const MaterialApp(home: HomeShell()));
  await tester.pumpAndSettle();
  // HomeShell.initState starts OfflineSyncService's periodic timer. The
  // binding verifies "no pending timers" before addTearDown runs, so cancel
  // here (in the test body) — not only in teardown.
  OfflineSyncService.instance.stop();
}

/// Secondary pill uppercases its label with NO trailing " ▸" (only the
/// primary variant appends the caret).
const _runScreening = 'RUN SCREENING (32 INPUTS)';

void main() {
  group('role routing (HomeShell)', () {
    testWidgets(
        'family_caregiver → dashboard (basic: no screening button)',
        (tester) async {
      await _seedUser(id: 'u1', role: 'family_caregiver');
      await _pumpShell(tester, _shellBackend(summaryView: 'basic'));

      expect(find.byType(CaregiverDashboardScreen), findsOneWidget);
      expect(find.textContaining('linked clinical staff only'), findsWidgets);
      expect(find.text(_runScreening), findsNothing);
      expect(find.byTooltip('Compliance audit trail (admin)'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('asha_worker → clinical + patient switcher', (tester) async {
      await _seedUser(id: 'u2', role: 'asha_worker');
      await _pumpShell(
        tester,
        _shellBackend(
          roster: [
            {
              'patient_id': 'p1',
              'name': 'Test Patient',
              'district': 'Kamrup',
              'relationship_type': 'family',
            },
            {
              'patient_id': 'p2',
              'name': 'Second Patient',
              'district': 'Nagaon',
              'relationship_type': 'neighbor',
            },
          ],
          summaryView: 'clinical',
          accuracyPct: 72.0,
          dailyTrends: [
            {
              'day': '2026-09-20',
              'accuracy_pct': 70,
              'avg_response_time_ms': 1500,
            },
            {
              'day': '2026-09-21',
              'accuracy_pct': 75,
              'avg_response_time_ms': 1400,
            },
          ],
        ),
      );

      expect(find.byType(CaregiverDashboardScreen), findsOneWidget);
      expect(find.text(_runScreening), findsOneWidget);
      // Switcher is ASHA-only; closed dropdown shows the selected item label
      // (PatientSwitcher builds `'name (district) — RELATIONSHIP'`).
      expect(find.byType(PatientSwitcher), findsOneWidget);
      expect(find.text('Test Patient (Kamrup) — FAMILY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clinician → clinical tier, no switcher', (tester) async {
      await _seedUser(id: 'u3', role: 'clinician');
      await _pumpShell(
        tester,
        _shellBackend(
          summaryView: 'clinical',
          accuracyPct: 72.0,
          dailyTrends: [
            {
              'day': '2026-09-21',
              'accuracy_pct': 80,
              'avg_response_time_ms': 1200,
            },
          ],
        ),
      );

      expect(find.byType(CaregiverDashboardScreen), findsOneWidget);
      expect(find.text(_runScreening), findsOneWidget);
      expect(find.byType(PatientSwitcher), findsNothing);
      expect(find.text('Select patient'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('admin → audit entry visible', (tester) async {
      await _seedUser(id: 'u4', role: 'admin');
      await _pumpShell(tester, _shellBackend(summaryView: 'basic'));

      expect(find.byType(CaregiverDashboardScreen), findsOneWidget);
      expect(find.byTooltip('Compliance audit trail (admin)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('patient → PatientHome (not dashboard)', (tester) async {
      await _seedUser(id: 'u5', role: 'patient');
      await _pumpShell(
        tester,
        _shellBackend(
          myPatient: (
            status: 200,
            json: {
              'id': 'p1',
              'user_id': 'u5',
              'name': 'Elder One',
              'cognitive_baseline': 'healthy',
              'region': 'Assam',
              'district': 'Kamrup',
            }
          ),
        ),
      );

      expect(find.byType(PatientHome), findsOneWidget);
      expect(find.byType(CaregiverDashboardScreen), findsNothing);
      expect(
        find.text('Your health worker can add your health documents.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('summary 403 consent → dashboard renders error, no crash',
        (tester) async {
      await _seedUser(id: 'u6', role: 'family_caregiver');
      await _pumpShell(
        tester,
        _shellBackend(
          summaryOverride: (
            status: 403,
            json: {'detail': "Active consent required for scope 'health_data'"},
          ),
        ),
      );

      expect(find.byType(CaregiverDashboardScreen), findsOneWidget);
      // Load-failure path (`_error`) surfaces the ApiException detail —
      // not a blank body and not a stuck spinner.
      expect(
        find.textContaining('Could not load the summary'),
        findsOneWidget,
      );
      expect(
        find.textContaining("scope 'health_data'"),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('RETRY ▸'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

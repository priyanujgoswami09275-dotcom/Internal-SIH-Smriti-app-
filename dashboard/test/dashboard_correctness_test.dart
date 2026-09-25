import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eldercare_dashboard/config.dart';
import 'package:eldercare_dashboard/main.dart';
import 'package:eldercare_dashboard/widgets/risk_screening_card.dart';

import 'test_helpers.dart';

const _patients = [
  {
    'patient_id': 'p1',
    'name': 'Patient One',
    'district': 'Kamrup',
    'cognitive_baseline': 'healthy',
    'relationship_type': 'family',
  },
  {
    'patient_id': 'p2',
    'name': 'Patient Two',
    'district': 'Darrang',
    'cognitive_baseline': 'MCI',
    'relationship_type': 'family',
  },
];

Map<String, dynamic> _summary(
  String patientId, {
  String view = 'clinical',
  bool includeAlert = false,
}) {
  final clinical = view == 'clinical';
  return {
    'patient_id': patientId,
    'patient_name': patientId == 'p1' ? 'Patient One' : 'Patient Two',
    'period': 'last_7_days',
    'view': view,
    'permission_tier': view,
    'games_played': clinical ? 5 : 2,
    'reminders_total': clinical ? 3 : 1,
    'reminders_acknowledged': clinical ? 2 : 1,
    'reminders_missed': 0,
    'compliance_pct': clinical ? 80.0 : 100.0,
    if (clinical) 'accuracy_pct': 72.0,
    if (clinical) 'avg_response_time_ms': 1200.0,
    if (clinical)
      'active_alerts': includeAlert
          ? [
              {
                'id': 'alert-1',
                'summary': 'Missed reminders',
                'trigger_type': 'missed_reminders',
                'severity': 'warning',
              },
            ]
          : [],
    if (clinical) 'clinical_flags': {},
    if (clinical)
      'daily_trends': [
        {'accuracy_pct': 70.0, 'avg_response_time_ms': 1300.0},
        {'accuracy_pct': 74.0, 'avg_response_time_ms': 1100.0},
      ],
  };
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  Future<http.Response> Function(http.BaseRequest request, String body) handler, {
  String role = 'clinician',
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  Api.resetForTest();
  Api.setTestSession(
    token: 'token',
    refreshToken: 'refresh',
    userId: 'cg1',
    role: role,
  );
  Api.testClient = FakeClient((request, body) async {
    if (request.url.path.endsWith('/auth/me')) {
      return jsonRes({'id': 'cg1', 'role': role}, 200);
    }
    return handler(request, body);
  });
  await tester.pumpWidget(const CaregiverDashboardApp());
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

Future<http.Response> _defaultHandler(
  http.BaseRequest request,
  String body, {
  FutureOr<Map<String, dynamic>> Function(String patientId)? summaryFor,
  int auditStatus = 200,
}) async {
  final path = request.url.path;
  if (path.contains('/dashboard/caregivers/')) {
    return jsonRes(_patients, 200);
  }
  if (path.contains('/dashboard/patients/')) {
    final patientId = path.split('/').last;
    if (path.endsWith('/risk-screening/consent')) {
      return jsonRes(
        {
          'patient_id': patientId,
          'permission_tier': 'clinical',
          'required_scope': 'health_data',
          'health_data_consent': true,
          'consent_state': 'granted',
        },
        200,
      );
    }
    if (path.endsWith('/risk-screening')) {
      return jsonRes({'status': 'not_assessed'}, 200);
    }
    final summary = summaryFor == null
        ? _summary(patientId)
        : await summaryFor(patientId);
    return jsonRes(summary, 200);
  }
  if (path.contains('/reminders/schedules/')) return jsonRes([], 200);
  if (path.contains('/compliance/audit-logs')) {
    if (auditStatus != 200) return jsonRes({'detail': 'Admin only'}, auditStatus);
    return jsonRes([], 200);
  }
  return jsonRes({'detail': 'not found'}, 404);
}

void main() {
  tearDown(() => Api.resetForTest());

  testWidgets('a stale patient response cannot overwrite the current selection',
      (tester) async {
    var delayNextPatientOne = false;
    await _pumpDashboard(
      tester,
      (request, body) => _defaultHandler(
        request,
        body,
        summaryFor: (patientId) async {
          if (patientId == 'p1' && delayNextPatientOne) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          return _summary(patientId);
        },
      ),
    );
    delayNextPatientOne = true;

    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    dropdown.onChanged!('p1');
    dropdown.onChanged!('p2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    final current = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    expect(current.value, 'p2');
    expect(find.textContaining('Patient Two'), findsOneWidget);
    expect(find.textContaining('Patient One'), findsNothing);
  });

  testWidgets('switching patients clears the previous screening result',
      (tester) async {
    await _pumpDashboard(
      tester,
      (request, body) async {
        if (request.url.path.endsWith('/risk-screening')) {
          final patientId = request.url.path.split('/').elementAt(4);
          return jsonRes(
            patientId == 'p1'
                ? {
                    'status': 'ok',
                    'risk_score': 10,
                    'probability': 0.1,
                    'tier': 'low_risk',
                    'feature_count': 32,
                  }
                : {'status': 'not_assessed'},
            200,
          );
        }
        return _defaultHandler(request, body);
      },
    );

    expect(find.textContaining('Screening score: 10 / 100'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    dropdown.onChanged!('p2');
    await tester.pumpAndSettle();

    expect(find.text('No screening result yet'), findsOneWidget);
    expect(find.textContaining('Screening score: 10 / 100'), findsNothing);
  });

  testWidgets('basic server view hides clinical controls even for a clinician',
      (tester) async {
    await _pumpDashboard(
      tester,
      (request, body) => _defaultHandler(
        request,
        body,
        summaryFor: (patientId) => _summary(patientId, view: 'basic'),
      ),
    );

    expect(find.text('Upload'), findsNothing);
    expect(find.text('Run Screening (32 inputs)'), findsNothing);
    expect(find.text('DAILY ACCURACY TREND (14D), ALL GAMES'), findsNothing);
    expect(find.textContaining('clinical detail'), findsOneWidget);
  });

  testWidgets('empty roster explains the server scope honestly', (tester) async {
    Future<void> pumpWithRole(String role) => _pumpDashboard(
          tester,
          (request, body) async {
            if (request.url.path.contains('/dashboard/caregivers/')) {
              return jsonRes([], 200);
            }
            return _defaultHandler(request, body);
          },
          role: role,
        );

    await pumpWithRole('clinician');
    expect(
      find.text('No patients are available in the clinical roster yet.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await pumpWithRole('family_caregiver');
    expect(
      find.text('No patients are linked to this account yet.'),
      findsOneWidget,
    );
  });

  testWidgets('missing health-data consent disables screening before intake',
      (tester) async {
    await _pumpDashboard(
      tester,
      (request, body) async {
        if (request.url.path.endsWith('/risk-screening/consent')) {
          return jsonRes(
            {
              'patient_id': 'p1',
              'permission_tier': 'clinical',
              'required_scope': 'health_data',
              'health_data_consent': false,
              'consent_state': 'required',
            },
            200,
          );
        }
        return _defaultHandler(request, body);
      },
    );

    expect(find.textContaining('health_data consent required'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Run Screening (32 inputs)'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('rate limits and network failures render their own retry states',
      (tester) async {
    await _pumpDashboard(
      tester,
      (request, body) async {
        if (request.url.path.contains('/dashboard/caregivers/')) {
          return http.Response(
            jsonEncode({'detail': 'slow down'}),
            429,
            headers: {
              'content-type': 'application/json',
              'retry-after': '3',
            },
          );
        }
        return _defaultHandler(request, body);
      },
      settle: false,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Rate limit reached'), findsOneWidget);
    expect(find.text('RETRY ▸'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _pumpDashboard(
      tester,
      (request, body) async {
        if (request.url.path.contains('/dashboard/caregivers/')) {
          throw http.ClientException('offline');
        }
        return _defaultHandler(request, body);
      },
      settle: false,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Network unavailable'), findsOneWidget);
  });

  testWidgets('5xx renders the server status and a retry action', (tester) async {
    await _pumpDashboard(
      tester,
      (request, body) async {
        if (request.url.path.contains('/dashboard/caregivers/')) {
          return jsonRes({'detail': 'service unavailable'}, 503);
        }
        return _defaultHandler(request, body);
      },
      settle: false,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Server error (503): service unavailable'), findsOneWidget);
    expect(find.text('RETRY ▸'), findsOneWidget);
  });

  test('HTTP 429 exposes status and Retry-After through a typed error', () async {
    Api.setTestSession(
      token: 'token',
      refreshToken: 'refresh',
      userId: 'cg1',
    );
    Api.testClient = FakeClient((request, body) async {
      return http.Response(
        jsonEncode({'detail': 'rate limited'}),
        429,
        headers: {
          'content-type': 'application/json',
          'retry-after': '3',
        },
      );
    });

    try {
      await Api.summary('p1');
      fail('expected a typed error');
    } catch (error) {
      expect(error.runtimeType.toString(), 'ApiException');
      expect((error as dynamic).statusCode, 429);
      expect((error as dynamic).retryAfter, const Duration(seconds: 3));
      expect((error as dynamic).isRateLimited, isTrue);
    }
  });

  test('network failures expose a typed transport error', () async {
    Api.setTestSession(
      token: 'token',
      refreshToken: 'refresh',
      userId: 'cg1',
    );
    Api.testClient = FakeClient((request, body) async {
      throw http.ClientException('offline');
    });

    try {
      await Api.summary('p1');
      fail('expected a typed error');
    } catch (error) {
      expect((error as dynamic).isNetworkError, isTrue);
      expect(error.toString(), contains('Network'));
    }
  });

  test('audit 403 keeps the server detail instead of claiming admin-only', () {
    const error = ApiException(
      kind: ApiErrorKind.forbidden,
      statusCode: 403,
      message: 'audit policy denied this request',
    );

    final message = describeApiError(error, context: 'audit');

    expect(message, contains('403'));
    expect(message, contains('audit policy denied this request'));
    expect(message, isNot(contains('admin-only')));
  });

  test('5xx exposes a typed server error with its status', () async {
    Api.setTestSession(
      token: 'token',
      refreshToken: 'refresh',
      userId: 'cg1',
    );
    Api.testClient = FakeClient((request, body) async {
      return jsonRes({'detail': 'service unavailable'}, 503);
    });

    try {
      await Api.summary('p1');
      fail('expected a typed error');
    } catch (error) {
      expect((error as dynamic).isServerError, isTrue);
      expect((error as dynamic).statusCode, 503);
      expect(describeApiError(error as ApiException), contains('503'));
    }
  });

  testWidgets('a successful alert mutation is not reported as failed when refresh fails',
      (tester) async {
    var summaryCalls = 0;
    await _pumpDashboard(
      tester,
      (request, body) async {
        if (request.url.path.contains('/dashboard/patients/') &&
            request.url.path.endsWith('/summary')) {
          summaryCalls++;
          if (summaryCalls > 1) {
            return jsonRes({'detail': 'refresh failed'}, 500);
          }
          return jsonRes(_summary('p1', includeAlert: true), 200);
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/alerts/alert-1/acknowledge')) {
          return jsonRes({'message': 'acknowledged'}, 200);
        }
        return _defaultHandler(request, body);
      },
    );

    final button = find.text('Acknowledge');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.textContaining('Alert acknowledged'), findsOneWidget);
    expect(find.textContaining('refresh failed'), findsOneWidget);
    expect(find.textContaining('Failed:'), findsNothing);
  });

  testWidgets('audit viewer pages through offset results and shows identifying fields',
      (tester) async {
    final requests = <Uri>[];
    await _pumpDashboard(
      tester,
      (request, body) async {
        if (request.url.path.contains('/compliance/audit-logs')) {
          requests.add(request.url);
          final offset = int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
          final count = offset == 0 ? 50 : 1;
          return jsonRes(
            List.generate(
              count,
              (index) => {
                'id': 'audit-${offset + index}',
                'user_id': 'user-1',
                'action': 'read',
                'resource_type': 'patient_profile',
                'resource_id': 'resource-${offset + index}',
                'timestamp': '2026-09-25T00:00:00Z',
                'details': {'patient_id': 'p${offset + index}'},
              },
            ),
            200,
          );
        }
        return _defaultHandler(
          request,
          body,
          summaryFor: (patientId) => _summary(patientId, view: 'basic'),
        );
      },
      role: 'admin',
    );

    await tester.tap(find.byTooltip('Compliance audit trail (admin)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('audit-0'), findsOneWidget);
    expect(find.textContaining('resource-0'), findsOneWidget);
    expect(find.textContaining('NEXT'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('NEXT'),
      find.byType(Scrollable).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('NEXT'));
    await tester.pumpAndSettle();

    expect(requests.any((uri) => uri.queryParameters['offset'] == '50'), isTrue);
    expect(find.textContaining('resource-50'), findsOneWidget);
  });

  testWidgets('risk screening states are rendered honestly', (tester) async {
    Future<void> pump(Map<String, dynamic> result) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RiskScreeningCard(result: result))),
      );
      await tester.pumpAndSettle();
    }

    await pump({'status': 'not_assessed'});
    expect(find.text('No screening result yet'), findsOneWidget);
    expect(find.textContaining('temporarily unavailable'), findsNothing);

    await pump({'status': 'validation_failed', 'errors': ['missing_feature: Age']});
    expect(find.textContaining('validation'), findsOneWidget);
    expect(find.textContaining('missing_feature: Age'), findsOneWidget);

    await pump({'status': 'inference_failed'});
    expect(find.textContaining('inference failed'), findsOneWidget);

    await pump({'status': 'model_unavailable'});
    expect(find.textContaining('model artifacts'), findsOneWidget);

    await pump({'status': 'transport_failure'});
    expect(find.textContaining('Could not reach'), findsOneWidget);

    await pump({
      'status': 'ok',
      'risk_score': 20,
      'probability': 0.2,
      'tier': 'low_risk',
      'feature_count': 32,
    });
    expect(find.textContaining('not clinically validated'), findsOneWidget);
  });

  test('release configuration refuses an implicit API URL', () {
    expect(
      () => resolveApiBaseUrl(release: true, configured: ''),
      throwsA(isA<StateError>()),
    );
    expect(
      resolveApiBaseUrl(release: false, configured: ''),
      'http://localhost:8000',
    );
    expect(
      resolveApiBaseUrl(release: true, configured: 'https://api.example.test'),
      'https://api.example.test',
    );
  });
}

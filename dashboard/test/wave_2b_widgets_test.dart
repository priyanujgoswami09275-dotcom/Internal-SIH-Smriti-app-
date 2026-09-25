// Wave 2B tasks 2.3 + 2.6-dashboard widget tests:
// risk-form auth header, basic-tier gating, audit caption, compliance
// no-data tile, honest trend titles.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eldercare_dashboard/main.dart';
import 'package:eldercare_dashboard/widgets/risk_intake_form.dart';

import 'test_helpers.dart';

const _patient = {
  'patient_id': 'p1',
  'name': 'Asha',
  'district': 'Kamrup',
  'cognitive_baseline': 'mild',
  'relationship_type': 'daughter',
};

Map<String, dynamic> _basicSummary() => {
      'view': 'basic',
      'patient_id': 'p1',
    };

Map<String, dynamic> _clinicalSummary() => {
      'view': 'clinical',
      'patient_id': 'p1',
      'accuracy_pct': 72.0,
      'compliance_pct': 100.0,
      'reminders_total': 0,
      'reminders_acknowledged': 0,
      'games_played': 5,
      'avg_response_time_ms': 1200.0,
      'active_alerts': [],
      'clinical_flags': {},
      'daily_trends': [
        {'accuracy_pct': 70.0, 'avg_response_time_ms': 1300.0},
        {'accuracy_pct': 74.0, 'avg_response_time_ms': 1100.0},
      ],
    };

Future<void> _pumpApp(
  WidgetTester tester,
  Map<String, dynamic> summary, {
  int auditStatus = 200,
}) async {
  SharedPreferences.setMockInitialValues({});
  Api.resetForTest();
  Api.setTestSession(token: 't', refreshToken: 'r', userId: 'cg1');
  Api.testClient = FakeClient((req, body) async {
    final path = req.url.path;
    if (path.endsWith('/auth/me')) return jsonRes({'id': 'cg1'}, 200);
    if (path.contains('/dashboard/caregivers/')) return jsonRes([_patient], 200);
    if (path.contains('/dashboard/patients/')) return jsonRes(summary, 200);
    if (path.contains('/reminders/schedules/')) return jsonRes([], 200);
    if (path.endsWith('/risk-screening') && req.method == 'GET') {
      return jsonRes({'status': 'not_assessed'}, 200);
    }
    if (path.contains('/compliance/audit-logs')) {
      return auditStatus == 200
          ? jsonRes([], 200)
          : jsonRes({'detail': 'Admin only'}, auditStatus);
    }
    return jsonRes({'detail': 'not found'}, 404);
  });
  await tester.pumpWidget(const CaregiverDashboardApp());
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => Api.resetForTest());

  testWidgets('risk form submits Authorization header via the Api seam',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Api.resetForTest();
    Api.setTestSession(
        token: 'tok-123', refreshToken: 'ref-1', userId: 'cg1');
    Uri? seenUrl;
    Map<String, String>? seenHeaders;
    var gotResult = false;
    Api.testClient = FakeClient((req, body) async {
      seenUrl = req.url;
      seenHeaders = Map.of(req.headers);
      return jsonRes(
          {'status': 'ok', 'tier': 'low_risk', 'risk_score': 12.0}, 200);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => RiskIntakeForm(
                patientId: 'p1',
                patientName: 'Test',
                onResult: (_) => gotResult = true,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RUN SCREENING ▸'));
    await tester.pumpAndSettle();

    expect(seenUrl?.path, '/api/v1/patients/p1/risk-screening');
    final auth = seenHeaders?.entries
        .where((e) => e.key.toLowerCase() == 'authorization')
        .map((e) => e.value)
        .singleOrNull;
    expect(auth, 'Bearer tok-123');
    expect(gotResult, isTrue);
  });

  testWidgets('basic view hides screening button, shows locked note',
      (tester) async {
    await _pumpApp(tester, _basicSummary());

    expect(
        find.textContaining(
            'Clinical screening, trends, and document controls are hidden'),
        findsOneWidget);
    expect(find.text('Run Screening (32 inputs)'), findsNothing);
  });

  testWidgets('zero reminders show honest no-data compliance tile',
      (tester) async {
    await _pumpApp(tester, _clinicalSummary());

    expect(find.text('no reminders yet'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('trend titles disclose pooled games', (tester) async {
    await _pumpApp(tester, _clinicalSummary());

    expect(find.text('DAILY ACCURACY TREND (14D), ALL GAMES'), findsOneWidget);
    expect(find.text('RESPONSE TIME TREND (14D), ALL GAMES'), findsOneWidget);
  });

  testWidgets('audit error shows caption, never a fake row', (tester) async {
    await _pumpApp(tester, _clinicalSummary(), auditStatus: 403);

    await tester.tap(find.byTooltip('Compliance audit trail (admin)'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.textContaining('Audit trail request denied by the server'),
      find.byType(Scrollable).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Audit trail request denied by the server'), findsOneWidget);
    expect(find.text('null · null'), findsNothing);
  });
}

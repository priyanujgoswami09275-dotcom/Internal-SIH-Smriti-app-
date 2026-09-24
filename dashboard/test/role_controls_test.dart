import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eldercare_dashboard/main.dart';

import 'test_helpers.dart';

const _patient = {
  'patient_id': 'p1',
  'name': 'Asha',
  'district': 'Kamrup',
  'relationship_type': 'family',
};

Map<String, dynamic> _basicSummary() => {
      'view': 'basic',
      'patient_id': 'p1',
      'patient_name': 'Asha',
      'games_played': 0,
      'reminders_total': 0,
      'reminders_acknowledged': 0,
      'reminders_missed': 0,
      'compliance_pct': 100.0,
    };

Map<String, dynamic> _clinicalSummary() => {
      'view': 'clinical',
      'patient_id': 'p1',
      'games_played': 5,
      'accuracy_pct': 72.0,
      'reminders_total': 0,
      'reminders_acknowledged': 0,
      'reminders_missed': 0,
      'compliance_pct': 100.0,
      'avg_response_time_ms': 1200.0,
      'active_alerts': [],
      'clinical_flags': {},
      'daily_trends': [
        {'accuracy_pct': 70.0, 'avg_response_time_ms': 1300.0},
        {'accuracy_pct': 74.0, 'avg_response_time_ms': 1100.0},
      ],
    };

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required String role,
  required Map<String, dynamic> summary,
}) async {
  SharedPreferences.setMockInitialValues({});
  Api.resetForTest();
  Api.setTestSession(token: 'token', refreshToken: 'refresh', userId: 'cg1');
  Api.testClient = FakeClient((req, body) async {
    final path = req.url.path;
    if (path.endsWith('/auth/me')) {
      return jsonRes({'id': 'cg1', 'role': role}, 200);
    }
    if (path.contains('/dashboard/caregivers/')) {
      return jsonRes([_patient], 200);
    }
    if (path.contains('/dashboard/patients/')) {
      return jsonRes(summary, 200);
    }
    if (path.contains('/reminders/schedules/')) {
      return jsonRes([], 200);
    }
    return jsonRes({'detail': 'not found'}, 404);
  });

  await tester.pumpWidget(const CaregiverDashboardApp());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Api.resetForTest();
  });

  tearDown(() {
    Api.resetForTest();
  });

  testWidgets('non-admin role hides the audit-trail control', (tester) async {
    await _pumpDashboard(
      tester,
      role: 'clinician',
      summary: _clinicalSummary(),
    );

    expect(find.byTooltip('Compliance audit trail (admin)'), findsNothing);
  });

  testWidgets('admin role shows the audit-trail control', (tester) async {
    await _pumpDashboard(
      tester,
      role: 'admin',
      summary: _clinicalSummary(),
    );

    expect(find.byTooltip('Compliance audit trail (admin)'), findsOneWidget);
  });

  testWidgets('family caregiver role hides the document-upload control',
      (tester) async {
    await _pumpDashboard(
      tester,
      role: 'family_caregiver',
      summary: _basicSummary(),
    );

    expect(find.text('Upload'), findsNothing);
  });
}

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
    expect(find.text('Your health worker can add your health documents.'), findsOneWidget);
  });
}

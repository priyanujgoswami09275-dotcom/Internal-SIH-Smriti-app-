import 'package:eldercare_mobile/screens/caregiver/sections/metrics_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('integer accuracy_pct from JSON renders (num→double safe)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MetricsTiles(summary: <String, dynamic>{
            'view': 'clinical',
            'accuracy_pct': 72, // raw JSON int — previously threw `as double`
            'compliance_pct': 88,
            'games_played': 4,
            'reminders_acknowledged': 5,
            'reminders_total': 6,
            'reminders_missed': 1,
          }),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('72%'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
  });
}

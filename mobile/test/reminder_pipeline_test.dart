import 'package:eldercare_mobile/services/reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

String _formatTime(ReminderTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

void main() {
  group('reminder cadence grammar parity', () {
    test('accepts every backend-valid form and collapses duplicate times', () {
      final examples = <String, List<String>>{
        'daily@08:00': ['08:00'],
        'everyday 08:00': ['08:00'],
        '08:00,20:00': ['08:00', '20:00'],
        '08:00; 20:00': ['08:00', '20:00'],
        '08:00 AM Daily': ['08:00'],
        '  DAILY at 20:00, 08:00;08:00  ': ['08:00', '20:00'],
      };

      for (final entry in examples.entries) {
        expect(
          ReminderScheduler.parseCadence(entry.key).map(_formatTime),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('rejects every form outside the backend grammar', () {
      const invalid = [
        '',
        '   ',
        'after lunch',
        '24:00',
        '08:60',
        '08:00 AM',
        '08:00 Daily',
        '08:00 PM extra',
        '08:00,',
        '08:00/20:00',
      ];

      for (final cadence in invalid) {
        expect(
          () => ReminderScheduler.parseCadence(cadence),
          throwsA(isA<FormatException>()),
          reason: cadence,
        );
      }
    });
  });
}

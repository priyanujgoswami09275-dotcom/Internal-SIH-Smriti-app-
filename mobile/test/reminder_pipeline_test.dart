import 'package:eldercare_mobile/services/reminder_scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

String _formatTime(ReminderTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('reminder local timezone', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');

    setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') return true;
        return null;
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('initialization establishes IST and maps 08:00 to the right instant',
        () async {
      final scheduler = ReminderScheduler(
        deviceTimeZone: () => const DeviceTimeZone(
          'IST',
          Duration(hours: 5, minutes: 30),
        ),
        now: () => DateTime.utc(2026, 9, 24, 18),
      );

      await scheduler.initialize();
      final eight = ReminderScheduler.parseCadence('daily@08:00').single;
      final next = scheduler.nextInstanceOf(eight);

      expect(tz.local.name, ReminderScheduler.fallbackTimeZoneName);
      expect(tz.local.name, 'Asia/Kolkata');
      expect(next.toUtc().toIso8601String(), '2026-09-25T02:30:00.000Z');
    });
  });
}

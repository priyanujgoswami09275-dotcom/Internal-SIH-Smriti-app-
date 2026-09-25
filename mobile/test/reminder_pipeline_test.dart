import 'package:eldercare_mobile/models/shared_models.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:eldercare_mobile/services/reminder_scheduler.dart';
import 'package:eldercare_mobile/services/reminder_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

String _formatTime(ReminderTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

ReminderScheduleModel _schedule({
  required String id,
  required String cadence,
  ReminderType type = ReminderType.medicine,
}) =>
    ReminderScheduleModel(
      id: id,
      patientId: 'patient-1',
      reminderType: type,
      cadence: cadence,
      isActive: true,
      createdAt: DateTime.utc(2026, 9, 1),
    );

class _FakeNotificationGateway implements ReminderNotificationGateway {
  final Map<int, ScheduledReminderNotification> pending = {};
  final List<int> scheduledIds = [];
  final List<int> canceledIds = [];
  int cancelAllCalls = 0;

  @override
  Future<void> initialize(TargetPlatform platform) async {}

  @override
  Future<List<ScheduledReminderNotification>> pendingNotifications() async =>
      pending.values.toList(growable: false);

  @override
  Future<void> schedule(ScheduledReminderNotification notification) async {
    pending[notification.id] = notification;
    scheduledIds.add(notification.id);
  }

  @override
  Future<void> cancel(int id) async {
    pending.remove(id);
    canceledIds.add(id);
  }

  @override
  Future<void> cancelAll() async {
    pending.clear();
    cancelAllCalls++;
  }
}

class _FakeReminderApi extends ApiService {
  _FakeReminderApi(this.schedules) : super(baseUrl: 'http://reminder.test');

  List<ReminderScheduleModel> schedules;

  @override
  Future<List<ReminderScheduleModel>> reminderSchedules(
          String patientId) async =>
      schedules;
}

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

  group('reminder schedule reconciliation', () {
    test('cancels removed and changed schedules, adds new, and is idempotent',
        () async {
      final gateway = _FakeNotificationGateway();
      final scheduler = ReminderScheduler(
        gateway: gateway,
        platform: TargetPlatform.android,
        deviceTimeZone: () =>
            const DeviceTimeZone('IST', Duration(hours: 5, minutes: 30)),
        now: () => DateTime.utc(2026, 9, 24, 18),
      );
      final removed = _schedule(id: 'removed', cadence: 'daily@08:00');
      final changed = _schedule(id: 'changed', cadence: 'daily@08:00');
      final stable = _schedule(id: 'stable', cadence: 'daily@08:00');
      await scheduler.scheduleForSchedule(removed);
      await scheduler.scheduleForSchedule(changed);
      await scheduler.scheduleForSchedule(stable);
      gateway.scheduledIds.clear();
      gateway.canceledIds.clear();

      final first = await scheduler.reconcile([
        _schedule(id: 'changed', cadence: 'daily@09:00'),
        stable,
        _schedule(id: 'new', cadence: '08:00,20:00'),
      ]);

      expect(first.canceledCount, 2);
      expect(first.scheduledCount, 3);
      expect(first.unchangedCount, 1);
      expect(gateway.canceledIds, hasLength(2));
      expect(gateway.scheduledIds, hasLength(3));
      expect(
        gateway.pending.values.map((notification) => notification.scheduleId),
        containsAll(<String>['changed', 'stable', 'new']),
      );

      gateway.scheduledIds.clear();
      gateway.canceledIds.clear();
      final second = await scheduler.reconcile([
        _schedule(id: 'changed', cadence: 'daily@09:00'),
        stable,
        _schedule(id: 'new', cadence: '08:00,20:00'),
      ]);

      expect(second.canceledCount, 0);
      expect(second.scheduledCount, 0);
      expect(second.unchangedCount, 4);
      expect(gateway.canceledIds, isEmpty);
      expect(gateway.scheduledIds, isEmpty);
    });

    test('every successful fetch reconciles and auth stop clears notifications',
        () async {
      final gateway = _FakeNotificationGateway();
      final scheduler = ReminderScheduler(
        gateway: gateway,
        platform: TargetPlatform.android,
        deviceTimeZone: () =>
            const DeviceTimeZone('IST', Duration(hours: 5, minutes: 30)),
        now: () => DateTime.utc(2026, 9, 24, 18),
      );
      final api = _FakeReminderApi([
        _schedule(id: 'server-owned', cadence: 'daily@08:00'),
      ]);
      final service = MobileReminderService(
        apiService: api,
        scheduler: scheduler,
      );

      await service.getSchedules('patient-1');
      await service.getSchedules('patient-1');

      expect(gateway.scheduledIds, hasLength(1));
      expect(gateway.pending, hasLength(1));

      await service.stop();
      expect(gateway.cancelAllCalls, 1);
      expect(gateway.pending, isEmpty);
    });
  });
}

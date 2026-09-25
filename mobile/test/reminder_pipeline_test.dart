import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:eldercare_mobile/database/app_database.dart';
import 'package:eldercare_mobile/models/shared_models.dart';
import 'package:eldercare_mobile/patient_localizations.dart';
import 'package:eldercare_mobile/screens/reminders_screen.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:eldercare_mobile/services/offline_sync_service.dart';
import 'package:eldercare_mobile/services/reminder_scheduler.dart';
import 'package:eldercare_mobile/services/reminder_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

ReminderEventModel _event({ReminderStatus status = ReminderStatus.pending}) =>
    ReminderEventModel(
      id: 'event-1',
      scheduleId: 'schedule-1',
      patientId: 'patient-1',
      scheduledAt: DateTime.utc(2026, 9, 25, 8),
      deliveredAt: DateTime.utc(2026, 9, 25, 8),
      status: status,
    );

class _FakeNotificationGateway implements ReminderNotificationGateway {
  final Map<int, ScheduledReminderNotification> pending = {};
  final List<int> scheduledIds = [];
  final List<int> canceledIds = [];
  int cancelAllCalls = 0;
  bool permissionGranted = true;

  @override
  Future<void> initialize(TargetPlatform platform) async {}

  @override
  Future<bool?> requestPermission(TargetPlatform platform) async =>
      permissionGranted;

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
  bool acknowledgeResult = true;
  Object? acknowledgeError;
  int acknowledgeCalls = 0;

  @override
  Future<List<ReminderScheduleModel>> reminderSchedules(
          String patientId) async =>
      schedules;

  @override
  Future<bool> acknowledgeReminder(
    String eventId, {
    String method = 'button',
    String? idempotencyKey,
  }) async {
    acknowledgeCalls++;
    final error = acknowledgeError;
    if (error != null) throw error;
    return acknowledgeResult;
  }
}

class _ToggleFailingDatabase extends AppDatabase {
  _ToggleFailingDatabase() : super.forTesting(NativeDatabase.memory());

  bool failReminderWrites = false;

  @override
  Future<void> upsertReminderEvent(ReminderEventModel event) async {
    if (failReminderWrites) throw StateError('local database unavailable');
    await super.upsertReminderEvent(event);
  }
}

class _NoTtsApi extends ApiService {
  _NoTtsApi() : super(baseUrl: 'http://reminder.test');

  @override
  Future<dynamic> getJson(
    String path, {
    Map<String, String>? query,
    bool includeAuth = true,
  }) async =>
      <String, dynamic>{'capabilities': <String, dynamic>{}};
}

class _ScreenReminderService extends MobileReminderService {
  _ScreenReminderService(this.outcome)
      : super(
          apiService: _FakeReminderApi(const []),
          scheduler: ReminderScheduler(),
        );

  final ReminderAcknowledgmentOutcome outcome;

  @override
  Future<List<ReminderScheduleModel>> getSchedules(String patientId) async =>
      [_schedule(id: 'schedule-1', cadence: 'daily@08:00')];

  @override
  Future<List<ReminderEventModel>> getTodaysEvents(String patientId) async =>
      [_event()];

  @override
  Future<Set<String>> getLocalAcknowledgedScheduleIds(
    String patientId, {
    DateTime? now,
  }) async =>
      {};

  @override
  Future<ReminderAcknowledgmentResult> acknowledgeReminder({
    required String patientId,
    required String eventId,
    required String method,
  }) async =>
      ReminderAcknowledgmentResult(
        outcome: outcome,
        acknowledgedAt: DateTime.utc(2026, 9, 25, 8, 5),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

  group('Android reminder notification permission', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');

    setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('denied permission schedules nothing and reports denied', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          if (call.method == 'requestNotificationsPermission') return false;
          return null;
        },
      );
      final scheduler = ReminderScheduler(
        platform: TargetPlatform.android,
        deviceTimeZone: () =>
            const DeviceTimeZone('IST', Duration(hours: 5, minutes: 30)),
        now: () => DateTime.utc(2026, 9, 24, 18),
      );

      final result = await scheduler.scheduleForSchedule(
        _schedule(id: 'denied', cadence: 'daily@08:00'),
      );

      expect(result.permissionStatus, ReminderPermissionStatus.denied);
      expect(result.scheduledCount, 0);
      expect(
        calls.map((call) => call.method),
        contains('requestNotificationsPermission'),
      );
      expect(
          calls.map((call) => call.method), isNot(contains('zonedSchedule')));
    });

    test('granted permission schedules the reminder', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          if (call.method == 'requestNotificationsPermission') return true;
          return null;
        },
      );
      final scheduler = ReminderScheduler(
        platform: TargetPlatform.android,
        deviceTimeZone: () =>
            const DeviceTimeZone('IST', Duration(hours: 5, minutes: 30)),
        now: () => DateTime.utc(2026, 9, 24, 18),
      );

      final result = await scheduler.scheduleForSchedule(
        _schedule(id: 'granted', cadence: 'daily@08:00'),
      );

      expect(result.permissionStatus, ReminderPermissionStatus.granted);
      expect(result.scheduledCount, 1);
      expect(
        calls.map((call) => call.method),
        containsAllInOrder([
          'initialize',
          'requestNotificationsPermission',
          'zonedSchedule',
        ]),
      );
    });
  });

  group('reminder acknowledgment durability and honesty', () {
    test('server-confirmed acknowledgment is distinct and durable', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.upsertReminderEvent(_event());
      final api = _FakeReminderApi(const []);
      final sync = OfflineSyncService(db: db, api: api)
        ..setActiveAccount('user-a');
      final service = MobileReminderService(apiService: api, sync: sync);

      final result = await service.acknowledgeReminder(
        patientId: 'patient-1',
        eventId: 'event-1',
        method: 'button',
      );

      expect(result.outcome, ReminderAcknowledgmentOutcome.sentToServer);
      expect(api.acknowledgeCalls, 1);
      final row = await db.select(db.reminderEvents).getSingle();
      expect(row.status, 'acknowledged');
      expect(row.acknowledgedAt, isNotNull);
      expect(row.synced, isTrue);
      expect(await db.pendingSyncItems(accountId: 'user-a'), isEmpty);
    });

    test('offline acknowledgment is queued and survives service recreation',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.upsertReminderEvent(_event());
      final api = _FakeReminderApi(const [])
        ..acknowledgeError = ApiException('Network error: offline');
      final sync = OfflineSyncService(db: db, api: api)
        ..setActiveAccount('user-a');
      final service = MobileReminderService(apiService: api, sync: sync);

      final result = await service.acknowledgeReminder(
        patientId: 'patient-1',
        eventId: 'event-1',
        method: 'button',
      );

      expect(result.outcome, ReminderAcknowledgmentOutcome.queuedOffline);
      final row = await db.select(db.reminderEvents).getSingle();
      expect(row.status, 'acknowledged');
      expect(row.acknowledgedAt, isNotNull);
      final queued = await db.pendingSyncItems(accountId: 'user-a');
      expect(queued, hasLength(1));
      expect(queued.single.resourceType, 'reminder_event');

      final recreated = MobileReminderService(apiService: api, sync: sync);
      expect(
        await recreated.getLocalAcknowledgedScheduleIds('patient-1'),
        contains('schedule-1'),
      );
    });

    test('failed local record is distinct and never claims delivery', () async {
      final db = _ToggleFailingDatabase();
      addTearDown(db.close);
      await db.upsertReminderEvent(_event());
      db.failReminderWrites = true;
      final api = _FakeReminderApi(const [])
        ..acknowledgeError = ApiException('Network error: offline');
      final sync = OfflineSyncService(db: db, api: api)
        ..setActiveAccount('user-a');
      final service = MobileReminderService(apiService: api, sync: sync);

      final result = await service.acknowledgeReminder(
        patientId: 'patient-1',
        eventId: 'event-1',
        method: 'button',
      );

      expect(result.outcome, ReminderAcknowledgmentOutcome.failedToRecord);
      expect(api.acknowledgeCalls, 0);
      expect(await db.pendingSyncItems(accountId: 'user-a'), isEmpty);
    });

    test('an older local acknowledgment does not complete today', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.upsertReminderEvent(ReminderEventModel(
        id: 'yesterday-event',
        scheduleId: 'schedule-1',
        patientId: 'patient-1',
        scheduledAt: DateTime.utc(2026, 9, 24, 8),
        acknowledgedAt: DateTime.utc(2026, 9, 24, 8, 5),
        status: ReminderStatus.acknowledged,
      ));
      final service = MobileReminderService(
        apiService: _FakeReminderApi(const []),
        sync: OfflineSyncService(
          db: db,
          api: _FakeReminderApi(const []),
        ),
      );

      expect(
        await service.getLocalAcknowledgedScheduleIds(
          'patient-1',
          now: DateTime.utc(2026, 9, 25, 12),
        ),
        isEmpty,
      );
    });

    testWidgets('all three outcomes remain honest at text scale 1.3',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      const outcomes = [
        (
          ReminderAcknowledgmentOutcome.sentToServer,
          'Medicine done — saved to your care record.',
          false,
        ),
        (
          ReminderAcknowledgmentOutcome.queuedOffline,
          'Medicine done on this phone — waiting to sync.',
          false,
        ),
        (
          ReminderAcknowledgmentOutcome.failedToRecord,
          'Medicine could not be saved. Please try again.',
          true,
        ),
      ];

      for (final entry in outcomes) {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            supportedLocales: const [Locale('en')],
            localizationsDelegates: const [
              ...GlobalMaterialLocalizations.delegates,
              PatientLocalizations.delegate,
            ],
            home: RemindersScreen(
              patientId: 'patient-1',
              reminderService: _ScreenReminderService(entry.$1),
              apiService: _NoTtsApi(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.tap(find.text('I Did This'));
        await tester.pump();

        expect(find.text(entry.$2), findsOneWidget);
        expect(
            find.text('I Did This'), entry.$3 ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  });
}

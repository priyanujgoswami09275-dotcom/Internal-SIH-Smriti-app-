/// Local reminder scheduling with flutter_local_notifications — fires
/// notifications on-device without any network, per the offline-first design.
///
/// This client parser is the single mobile source of truth for the backend
/// cadence grammar. Keep its examples and acceptance rules aligned with
/// backend `CADENCE_GRAMMAR`; the wire value itself remains unchanged.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/shared_models.dart';

const reminderCadenceGrammar =
    '[daily|everyday|every day][@|at|:]? HH:MM[,HH:MM;HH:MM]... '
    '(case-insensitive, 24-hour); legacy HH:MM AM|PM Daily is accepted.';

final RegExp _cadencePrefix = RegExp(
  r'^(?:(?:daily|everyday|every\s+day)\s*(?:@|at|:)?\s*)?',
  caseSensitive: false,
);
final RegExp _timeToken = RegExp(
  r'^(\d{1,2}):(\d{2})(?:\s*(am|pm))?(?:\s+(daily))?$',
  caseSensitive: false,
);

String _formatTime(ReminderTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

class ReminderTime {
  const ReminderTime({required this.hour, required this.minute});

  final int hour;
  final int minute;
}

class DeviceTimeZone {
  const DeviceTimeZone(this.name, this.offset);

  final String name;
  final Duration offset;
}

class ScheduledReminderNotification {
  const ScheduledReminderNotification({
    required this.id,
    required this.scheduleId,
    required this.signature,
    required this.title,
    required this.body,
    required this.scheduledAt,
  });

  final int id;
  final String scheduleId;
  final String signature;
  final String title;
  final String body;
  final tz.TZDateTime scheduledAt;
}

abstract interface class ReminderNotificationGateway {
  Future<void> initialize(TargetPlatform platform);

  Future<bool?> requestPermission(TargetPlatform platform);

  Future<List<ScheduledReminderNotification>> pendingNotifications();

  Future<void> schedule(ScheduledReminderNotification notification);

  Future<void> cancel(int id);

  Future<void> cancelAll();
}

enum ReminderPermissionStatus { granted, denied, unavailable }

class ReminderReconciliationResult {
  const ReminderReconciliationResult({
    required this.permissionStatus,
    required this.scheduledCount,
    required this.canceledCount,
    required this.unchangedCount,
  });

  final ReminderPermissionStatus permissionStatus;
  final int scheduledCount;
  final int canceledCount;
  final int unchangedCount;
}

DeviceTimeZone _currentDeviceTimeZone() {
  final now = DateTime.now();
  return DeviceTimeZone(now.timeZoneName, now.timeZoneOffset);
}

class ReminderScheduler {
  ReminderScheduler({
    ReminderNotificationGateway? gateway,
    TargetPlatform? platform,
    DeviceTimeZone Function()? deviceTimeZone,
    DateTime Function()? now,
  })  : _gateway = gateway ?? _PluginReminderNotificationGateway(),
        _platform = platform ?? defaultTargetPlatform,
        _deviceTimeZone = deviceTimeZone ?? _currentDeviceTimeZone,
        _now = now ?? DateTime.now;

  static final ReminderScheduler instance = ReminderScheduler();
  static const fallbackTimeZoneName = 'Asia/Kolkata';

  final ReminderNotificationGateway _gateway;
  final TargetPlatform _platform;
  final DeviceTimeZone Function() _deviceTimeZone;
  final DateTime Function() _now;
  bool _initialized = false;
  ReminderPermissionStatus _permissionStatus =
      ReminderPermissionStatus.unavailable;

  ReminderPermissionStatus get permissionStatus => _permissionStatus;

  static List<ReminderTime> parseCadence(String cadence) {
    final trimmed = cadence.trim();
    if (trimmed.isEmpty) {
      throw const FormatException(
          'Invalid reminder cadence: $reminderCadenceGrammar');
    }
    final raw = trimmed.replaceFirst(_cadencePrefix, '').trim();
    if (raw.isEmpty) {
      throw const FormatException(
          'Invalid reminder cadence: $reminderCadenceGrammar');
    }
    final times = <ReminderTime>[];
    for (final part in raw.split(RegExp(r'[,;]+'))) {
      final match = _timeToken.firstMatch(part.trim());
      if (match == null) {
        throw const FormatException(
            'Invalid reminder cadence: $reminderCadenceGrammar');
      }
      var hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final meridiem = match.group(3)?.toLowerCase();
      final dailySuffix = match.group(4);
      if ((dailySuffix != null) != (meridiem != null)) {
        throw const FormatException(
            'Invalid reminder cadence: $reminderCadenceGrammar');
      }
      if (meridiem != null) {
        if (hour < 1 || hour > 12 || minute > 59) {
          throw const FormatException(
              'Invalid reminder cadence: $reminderCadenceGrammar');
        }
        if (meridiem == 'am' && hour == 12) {
          hour = 0;
        } else if (meridiem == 'pm' && hour != 12) {
          hour += 12;
        }
      } else if (hour > 23 || minute > 59) {
        throw const FormatException(
            'Invalid reminder cadence: $reminderCadenceGrammar');
      }
      final value = ReminderTime(hour: hour, minute: minute);
      if (!times.any(
          (time) => time.hour == value.hour && time.minute == value.minute)) {
        times.add(value);
      }
    }
    times.sort((left, right) {
      final byHour = left.hour.compareTo(right.hour);
      return byHour == 0 ? left.minute.compareTo(right.minute) : byHour;
    });
    return List<ReminderTime>.unmodifiable(times);
  }

  /// Uses an IANA location when Dart exposes one and maps IST to the NER
  /// operating zone. Dart otherwise exposes only an abbreviation, so an
  /// unknown value deliberately falls back to Asia/Kolkata: this is safe for
  /// the target NER deployment but can be wrong outside India.
  static tz.Location resolveTimeZone(DeviceTimeZone deviceTimeZone) {
    tzdata.initializeTimeZones();
    final name = deviceTimeZone.name.trim();
    if (name.isNotEmpty) {
      try {
        return tz.getLocation(name);
      } on tz.LocationNotFoundException {
        if (name.toUpperCase() == 'IST' &&
            deviceTimeZone.offset == const Duration(hours: 5, minutes: 30)) {
          return tz.getLocation(fallbackTimeZoneName);
        }
      }
    }
    return tz.getLocation(fallbackTimeZoneName);
  }

  static int notificationIdFor(String scheduleId, ReminderTime time) {
    var hash = 0x811c9dc5;
    final value = '$scheduleId:${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    tz.setLocalLocation(resolveTimeZone(_deviceTimeZone()));
    await _gateway.initialize(_platform);
    try {
      final granted = await _gateway.requestPermission(_platform);
      _permissionStatus = granted == true
          ? ReminderPermissionStatus.granted
          : granted == false
              ? ReminderPermissionStatus.denied
              : ReminderPermissionStatus.unavailable;
    } on Exception {
      _permissionStatus = ReminderPermissionStatus.unavailable;
    }
    _initialized = true;
  }

  Future<ReminderReconciliationResult> scheduleForSchedule(
      ReminderScheduleModel schedule) async {
    await initialize();
    final notifications = _notificationsFor(schedule);
    if (_permissionStatus != ReminderPermissionStatus.granted) {
      return ReminderReconciliationResult(
        permissionStatus: _permissionStatus,
        scheduledCount: 0,
        canceledCount: 0,
        unchangedCount: 0,
      );
    }
    for (final notification in notifications) {
      await _gateway.schedule(notification);
    }
    return ReminderReconciliationResult(
      permissionStatus: _permissionStatus,
      scheduledCount: notifications.length,
      canceledCount: 0,
      unchangedCount: 0,
    );
  }

  Future<ReminderReconciliationResult> reconcile(
      List<ReminderScheduleModel> schedules) async {
    await initialize();
    final desired = <int, ScheduledReminderNotification>{};
    for (final schedule in schedules.where((value) => value.isActive)) {
      for (final notification in _notificationsFor(schedule)) {
        if (desired.containsKey(notification.id)) {
          throw StateError(
              'Reminder notification id collision for ${schedule.id}');
        }
        desired[notification.id] = notification;
      }
    }

    var canceledCount = 0;
    var unchangedCount = 0;
    final matchedIds = <int>{};
    final pending = await _gateway.pendingNotifications();
    for (final notification in pending) {
      final expected = desired[notification.id];
      final matches = expected != null &&
          expected.scheduleId == notification.scheduleId &&
          expected.signature == notification.signature;
      if (!matches || !matchedIds.add(notification.id)) {
        await _gateway.cancel(notification.id);
        canceledCount++;
      } else {
        unchangedCount++;
      }
    }

    var scheduledCount = 0;
    if (_permissionStatus == ReminderPermissionStatus.granted) {
      for (final entry in desired.entries) {
        if (matchedIds.contains(entry.key)) continue;
        await _gateway.schedule(entry.value);
        scheduledCount++;
      }
    }
    return ReminderReconciliationResult(
      permissionStatus: _permissionStatus,
      scheduledCount: scheduledCount,
      canceledCount: canceledCount,
      unchangedCount: unchangedCount,
    );
  }

  Future<void> cancelSchedule(ReminderScheduleModel schedule) async {
    await initialize();
    final pending = await _gateway.pendingNotifications();
    final ids = <int>{};
    for (final notification in pending) {
      if (notification.scheduleId == schedule.id) ids.add(notification.id);
    }
    for (final time in parseCadence(schedule.cadence)) {
      ids.add(notificationIdFor(schedule.id, time));
    }
    for (final id in ids) {
      await _gateway.cancel(id);
    }
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _gateway.cancelAll();
  }

  List<ScheduledReminderNotification> _notificationsFor(
      ReminderScheduleModel schedule) {
    final times = parseCadence(schedule.cadence);
    final signature = '${schedule.reminderType.name}|'
        '${times.map(_formatTime).join(',')}';
    return [
      for (final time in times)
        ScheduledReminderNotification(
          id: notificationIdFor(schedule.id, time),
          scheduleId: schedule.id,
          signature: signature,
          title: 'Reminder — ${schedule.reminderType.name.toUpperCase()}',
          body: 'Time for your ${schedule.reminderType.name} routine.',
          scheduledAt: nextInstanceOf(time),
        ),
    ];
  }

  tz.TZDateTime nextInstanceOf(ReminderTime time) {
    final now = tz.TZDateTime.from(_now(), tz.local);
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

class _PluginReminderNotificationGateway
    implements ReminderNotificationGateway {
  _PluginReminderNotificationGateway()
      : _plugin = FlutterLocalNotificationsPlugin();

  static const _payloadVersion = 1;

  final FlutterLocalNotificationsPlugin _plugin;
  bool? _darwinInitializationResult;

  @override
  Future<void> initialize(TargetPlatform platform) async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    _darwinInitializationResult = await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
  }

  @override
  Future<bool?> requestPermission(TargetPlatform platform) async {
    if (platform == TargetPlatform.android) {
      return _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    if (platform == TargetPlatform.iOS) {
      return _darwinInitializationResult;
    }
    return _darwinInitializationResult ?? true;
  }

  @override
  Future<List<ScheduledReminderNotification>> pendingNotifications() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map(_decodePending).toList(growable: false);
  }

  @override
  Future<void> schedule(ScheduledReminderNotification notification) async {
    await _plugin.zonedSchedule(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      scheduledDate: notification.scheduledAt,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Daily reminders',
          channelDescription: 'Medicine, water, food and exercise reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: jsonEncode({
        'version': _payloadVersion,
        'schedule_id': notification.scheduleId,
        'signature': notification.signature,
      }),
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  ScheduledReminderNotification _decodePending(
      PendingNotificationRequest request) {
    try {
      final payload = jsonDecode(request.payload ?? '') as Map<String, dynamic>;
      if (payload['version'] == _payloadVersion &&
          payload['schedule_id'] is String &&
          payload['signature'] is String) {
        return ScheduledReminderNotification(
          id: request.id,
          scheduleId: payload['schedule_id'] as String,
          signature: payload['signature'] as String,
          title: request.title ?? '',
          body: request.body ?? '',
          scheduledAt: tz.TZDateTime.utc(1970),
        );
      }
    } on FormatException {
      return _unknownPending(request);
    } on TypeError {
      return _unknownPending(request);
    }
    return _unknownPending(request);
  }

  ScheduledReminderNotification _unknownPending(
          PendingNotificationRequest request) =>
      ScheduledReminderNotification(
        id: request.id,
        scheduleId: '',
        signature: '',
        title: request.title ?? '',
        body: request.body ?? '',
        scheduledAt: tz.TZDateTime.utc(1970),
      );
}

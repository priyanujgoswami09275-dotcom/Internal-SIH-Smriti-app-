/// Local reminder scheduling with flutter_local_notifications — fires
/// notifications on-device without any network, per the offline-first design.
///
/// This client parser is the single mobile source of truth for the backend
/// cadence grammar. Keep its examples and acceptance rules aligned with
/// backend `CADENCE_GRAMMAR`; the wire value itself remains unchanged.
library;

import 'package:flutter/material.dart' show TimeOfDay;
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

class ReminderTime {
  const ReminderTime({required this.hour, required this.minute});

  final int hour;
  final int minute;
}

class ReminderScheduler {
  ReminderScheduler._();

  static final ReminderScheduler instance = ReminderScheduler._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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

  /// Must be called once at startup (after `flutter create .` has added the
  /// platform folders). Uses a placeholder icon id for the demo; replace with
  /// your app's notification icon on Android.
  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  /// Schedule one daily notification per time token found in the cadence.
  Future<void> scheduleForSchedule(ReminderScheduleModel schedule) async {
    await initialize();
    for (final time in _parseTimes(schedule.cadence)) {
      await _plugin.zonedSchedule(
        id: schedule.id.hashCode * 31 + time.minute + time.hour * 60,
        title: 'Reminder — ${schedule.reminderType.name.toUpperCase()}',
        body: 'Time for your ${schedule.reminderType.name} routine.',
        scheduledDate: _nextInstanceOf(time),
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
      );
    }
  }

  Future<void> cancelSchedule(ReminderScheduleModel schedule) async {
    await initialize();
    for (final time in _parseTimes(schedule.cadence)) {
      await _plugin.cancel(
          id: schedule.id.hashCode * 31 + time.minute + time.hour * 60);
    }
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  List<TimeOfDay> _parseTimes(String cadence) => parseCadence(cadence)
      .map((time) => TimeOfDay(hour: time.hour, minute: time.minute))
      .toList(growable: false);

  tz.TZDateTime _nextInstanceOf(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

/// Mobile Reminder Service — fetches reminder schedules + today's events from
/// the backend and acknowledges events by their REAL event id. Acknowledgments
/// that can't reach the server are queued (drift outbox) and replayed later, so
/// an offline "I Did This" is never lost.
library;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/shared_models.dart';
import 'api_service.dart';
import 'offline_sync_service.dart';
import 'reminder_scheduler.dart';

enum ReminderAcknowledgmentOutcome {
  sentToServer,
  queuedOffline,
  failedToRecord,
}

class ReminderAcknowledgmentResult {
  const ReminderAcknowledgmentResult({
    required this.outcome,
    required this.acknowledgedAt,
  });

  final ReminderAcknowledgmentOutcome outcome;
  final DateTime? acknowledgedAt;
}

class MobileReminderService {
  final ApiService apiService;
  final OfflineSyncService sync;
  final AppDatabase database;
  final ReminderScheduler scheduler;
  int _startupGeneration = 0;

  ReminderReconciliationResult? lastScheduleReconciliation;

  MobileReminderService({
    ApiService? apiService,
    OfflineSyncService? sync,
    AppDatabase? database,
    ReminderScheduler? scheduler,
  })  : apiService = apiService ?? ApiService.instance,
        sync = sync ?? OfflineSyncService.instance,
        database = database ?? (sync ?? OfflineSyncService.instance).db,
        scheduler = scheduler ?? ReminderScheduler.instance;

  Future<List<ReminderScheduleModel>> getSchedules(String patientId) async {
    final schedules = await _fetchSchedules(patientId);
    lastScheduleReconciliation = await scheduler.reconcile(schedules);
    return schedules;
  }

  Future<void> reconcileOnStartup(String patientId) async {
    final generation = ++_startupGeneration;
    try {
      final schedules = await _fetchSchedules(patientId);
      if (generation != _startupGeneration) return;
      lastScheduleReconciliation = await scheduler.reconcile(schedules);
    } on Exception catch (error) {
      debugPrint('Reminder startup reconciliation failed: $error');
    }
  }

  Future<void> stop() async {
    _startupGeneration++;
    lastScheduleReconciliation = null;
    await scheduler.cancelAll();
  }

  Future<List<ReminderScheduleModel>> _fetchSchedules(String patientId) async {
    try {
      return await apiService.reminderSchedules(patientId);
    } catch (error) {
      debugPrint('Reminder fetch failed (offline?): $error');
      rethrow;
    }
  }

  /// Today's reminder events (real ids + status). Returns [] when offline so the
  /// screen still renders the schedule cards.
  Future<List<ReminderEventModel>> getTodaysEvents(String patientId) async {
    try {
      final events = await apiService.reminderEvents(patientId);
      for (final event in events) {
        try {
          await database.upsertReminderEvent(event);
        } on Exception catch (error) {
          debugPrint('Reminder event could not be stored locally: $error');
        }
      }
      return events;
    } on Exception catch (error) {
      debugPrint('Reminder events fetch failed (offline?): $error');
      return const [];
    }
  }

  Future<Set<String>> getLocalAcknowledgedScheduleIds(
    String patientId, {
    DateTime? now,
  }) async {
    final rows = await (database.select(database.reminderEvents)
          ..where((table) =>
              table.patientId.equals(patientId) &
              table.acknowledgedAt.isNotNull()))
        .get();
    final localNow = (now ?? DateTime.now()).toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    return rows
        .where((row) {
          final scheduled = row.scheduledAt.toLocal();
          return DateTime(scheduled.year, scheduled.month, scheduled.day) ==
              today;
        })
        .map((row) => row.scheduleId)
        .toSet();
  }

  Future<ReminderAcknowledgmentResult> acknowledgeReminder({
    required String patientId,
    required String eventId,
    required String method,
  }) async {
    final event = await _localEvent(eventId);
    if (event == null) {
      return ReminderAcknowledgmentResult(
        outcome: ReminderAcknowledgmentOutcome.failedToRecord,
        acknowledgedAt: null,
      );
    }
    final acknowledgedAt = DateTime.now().toUtc();
    try {
      await database.upsertReminderEvent(ReminderEventModel(
        id: event.id,
        scheduleId: event.scheduleId,
        patientId: event.patientId,
        scheduledAt: event.scheduledAt,
        deliveredAt: event.deliveredAt,
        acknowledgedAt: acknowledgedAt,
        acknowledgmentMethod: method,
        status: ReminderStatus.acknowledged,
      ));
    } on Object catch (error) {
      debugPrint('Reminder acknowledgment could not be stored locally: $error');
      return ReminderAcknowledgmentResult(
        outcome: ReminderAcknowledgmentOutcome.failedToRecord,
        acknowledgedAt: null,
      );
    }

    try {
      final confirmed = await apiService.acknowledgeReminder(
        eventId,
        method: method,
      );
      if (!confirmed) {
        throw ApiException('Server did not record reminder acknowledgment');
      }
      try {
        await database.markReminderSynced(eventId);
      } on Exception catch (error) {
        debugPrint('Reminder sync marker could not be updated: $error');
      }
      return ReminderAcknowledgmentResult(
        outcome: ReminderAcknowledgmentOutcome.sentToServer,
        acknowledgedAt: acknowledgedAt,
      );
    } on Exception catch (error) {
      debugPrint(
          'Ack could not reach server (offline?), queueing for sync: $error');
      try {
        await sync.enqueueReminderAck(
          patientId: patientId,
          eventId: eventId,
          method: method,
        );
      } on Object catch (queueError) {
        debugPrint('Failed to enqueue offline ack: $queueError');
        return ReminderAcknowledgmentResult(
          outcome: ReminderAcknowledgmentOutcome.failedToRecord,
          acknowledgedAt: acknowledgedAt,
        );
      }
      return ReminderAcknowledgmentResult(
        outcome: ReminderAcknowledgmentOutcome.queuedOffline,
        acknowledgedAt: acknowledgedAt,
      );
    }
  }

  Future<ReminderEventModel?> _localEvent(String eventId) async {
    final row = await (database.select(database.reminderEvents)
          ..where((table) => table.id.equals(eventId)))
        .getSingleOrNull();
    if (row == null) return null;
    return ReminderEventModel(
      id: row.id,
      scheduleId: row.scheduleId,
      patientId: row.patientId,
      scheduledAt: row.scheduledAt,
      deliveredAt: row.deliveredAt,
      acknowledgedAt: row.acknowledgedAt,
      status: reminderStatusFromApi(row.status),
    );
  }
}

/// Offline-first local database (drift / SQLite).
///
/// Stores everything the patient needs when connectivity drops:
///   - game sessions + per-action logs (synced on reconnect)
///   - reminder events (acknowledgments queued offline)
///   - a sync queue of pending backend operations
///   - the patient's routine (for offline routine sequencing)
///
/// Generated code: this file declares `part 'app_database.g.dart';` — run
///   flutter pub get && dart run build_runner build --delete-conflicting-outputs
/// to generate it. See README.md in this folder for the enablement steps.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/game_models.dart';
import '../models/shared_models.dart';

part 'app_database.g.dart';

// =====================================================================
// Tables
// =====================================================================

/// Completed/in-progress game sessions kept until synced to the backend.
@DataClassName('GameSessionRow')
class GameSessions extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text()();
  TextColumn get gameType => text()(); // match_it | routine_sequencing
  IntColumn get difficultyLevel => integer().withDefault(const Constant(1))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get correctCount => integer().withDefault(const Constant(0))();
  IntColumn get incorrectCount => integer().withDefault(const Constant(0))();
  RealColumn get avgResponseTimeMs => real().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-flip / per-placement actions for a game session.
@DataClassName('GameActionRow')
class GameActions extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(GameSessions, #id)();
  TextColumn get actionType => text()();
  TextColumn get actionData => text()(); // JSON string
  BoolColumn get isCorrect => boolean().nullable()();
  IntColumn get responseTimeMs => integer().nullable()();
  DateTimeColumn get timestamp => dateTime()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Reminder events scheduled on this device (offline delivery + ack queue).
@DataClassName('ReminderEventRow')
class ReminderEvents extends Table {
  TextColumn get id => text()();
  TextColumn get scheduleId => text()();
  TextColumn get patientId => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Outbox of operations to push to POST /api/v1/sync when online.
@DataClassName('SyncQueueRow')
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text().nullable()();
  TextColumn get accountId => text().nullable()();
  TextColumn get resourceType => text()(); // game_session | reminder_event | ...
  TextColumn get operation => text()(); // create | update | delete
  TextColumn get resourceId => text()();
  TextColumn get payload => text()(); // JSON string
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The patient's routine cached locally so Routine Sequencing works offline.
@DataClassName('PatientRoutineRow')
class PatientRoutines extends Table {
  TextColumn get patientId => text()();
  TextColumn get stepsJson => text()(); // JSON array
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {patientId};
}

// =====================================================================
// Database
// =====================================================================

@DriftDatabase(
  tables: [GameSessions, GameActions, ReminderEvents, SyncQueue, PatientRoutines],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(syncQueue, syncQueue.accountId);
          }
        },
      );

  // ----- game sessions -----

  Future<void> insertSession(GameSessionModel session) async {
    await into(gameSessions).insertOnConflictUpdate(GameSessionsCompanion.insert(
      id: session.id,
      patientId: session.patientId,
      gameType: gameTypeToApi(session.gameType),
      difficultyLevel: Value(session.difficultyLevel),
      attempts: Value(session.attempts),
      correctCount: Value(session.correctCount),
      incorrectCount: Value(session.incorrectCount),
      avgResponseTimeMs: Value(session.avgResponseTimeMs),
      startedAt: session.startedAt,
      completedAt: Value(session.completedAt),
    ));
  }

  Future<List<GameSessionModel>> getUnsyncedSessions() async {
    final rows = await (select(gameSessions)
          ..where((t) => t.synced.equals(false)))
        .get();
    return rows.map(_sessionFromRow).toList();
  }

  Future<void> markSessionSynced(String sessionId) async {
    await (update(gameSessions)..where((t) => t.id.equals(sessionId)))
        .write(const GameSessionsCompanion(synced: Value(true)));
  }

  GameSessionModel _sessionFromRow(GameSessionRow row) => GameSessionModel(
        id: row.id,
        patientId: row.patientId,
        gameType: gameTypeFromApi(row.gameType),
        difficultyLevel: row.difficultyLevel,
        attempts: row.attempts,
        correctCount: row.correctCount,
        incorrectCount: row.incorrectCount,
        avgResponseTimeMs: row.avgResponseTimeMs,
        startedAt: row.startedAt,
        completedAt: row.completedAt,
      );

  // ----- game actions -----

  Future<void> insertAction(GameAction action) async {
    await into(gameActions).insertOnConflictUpdate(GameActionsCompanion.insert(
      id: action.id,
      sessionId: action.sessionId,
      actionType: action.actionType,
      actionData: jsonEncode(action.actionData),
      isCorrect: Value(action.isCorrect),
      responseTimeMs: Value(action.responseTimeMs),
      timestamp: action.timestamp,
    ));
  }

  Future<List<GameAction>> getUnsyncedActions() async {
    final rows = await (select(gameActions)
          ..where((t) => t.synced.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
        .get();
    return rows
        .map((r) => GameAction(
              id: r.id,
              sessionId: r.sessionId,
              actionType: r.actionType,
              actionData: _decodeMap(r.actionData),
              isCorrect: r.isCorrect,
              responseTimeMs: r.responseTimeMs,
              timestamp: r.timestamp,
              synced: r.synced,
            ))
        .toList();
  }

  Future<void> markActionSynced(String actionId) async {
    await (update(gameActions)..where((t) => t.id.equals(actionId)))
        .write(const GameActionsCompanion(synced: Value(true)));
  }

  // ----- reminder events -----

  Future<void> upsertReminderEvent(ReminderEventModel event) async {
    await into(reminderEvents).insertOnConflictUpdate(ReminderEventsCompanion.insert(
      id: event.id,
      scheduleId: event.scheduleId,
      patientId: event.patientId,
      scheduledAt: event.scheduledAt,
      deliveredAt: Value(event.deliveredAt),
      acknowledgedAt: Value(event.acknowledgedAt),
      status: Value(event.status.name),
    ));
  }

  Future<List<ReminderEventModel>> pendingReminderEvents(String patientId) async {
    final now = DateTime.now();
    final rows = await (select(reminderEvents)
          ..where((t) =>
              t.patientId.equals(patientId) &
              t.acknowledgedAt.isNull() &
              t.scheduledAt.isSmallerOrEqualValue(now)))
        .get();
    return rows
        .map((r) => ReminderEventModel(
              id: r.id,
              scheduleId: r.scheduleId,
              patientId: r.patientId,
              scheduledAt: r.scheduledAt,
              deliveredAt: r.deliveredAt,
              acknowledgedAt: r.acknowledgedAt,
              status: reminderStatusFromApi(r.status),
            ))
        .toList();
  }

  Future<void> markReminderSynced(String eventId) async {
    await (update(reminderEvents)..where((t) => t.id.equals(eventId)))
        .write(const ReminderEventsCompanion(synced: Value(true)));
  }

  // ----- sync queue (outbox) -----

  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    final existing = await (select(syncQueue)..where((t) => t.id.equals(item.id)))
        .getSingleOrNull();
    final existingPayload =
        existing == null ? null : _decodeMap(existing.payload);
    final payload = <String, dynamic>{...item.payload};
    final existingKey = existingPayload?['idempotency_key'];
    if (existingKey is String && existingKey.isNotEmpty) {
      payload['idempotency_key'] = existingKey;
    }
    final payloadAccount = payload['account_id'];
    final accountId = existing?.accountId ??
        item.accountId ??
        (payloadAccount is String && payloadAccount.isNotEmpty
            ? payloadAccount
            : null);
    await into(syncQueue).insertOnConflictUpdate(SyncQueueCompanion.insert(
      id: item.id,
      patientId: Value(item.patientId),
      accountId: Value(accountId),
      resourceType: item.resourceType,
      operation: item.operation,
      resourceId: item.resourceId,
      payload: jsonEncode(payload),
      createdAt: item.createdAt,
    ));
  }

  Future<List<SyncQueueItem>> pendingSyncItems({
    int limit = 200,
    String? accountId,
    bool unscopedOnly = false,
  }) async {
    final query = select(syncQueue)
      ..where((t) => t.syncedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
      ..limit(limit);
    if (accountId != null) {
      query.where((t) => t.accountId.equals(accountId));
    } else if (unscopedOnly) {
      query.where((t) => t.accountId.isNull());
    }
    final rows = await query.get();
    return rows
        .map((r) => SyncQueueItem(
              id: r.id,
              patientId: r.patientId,
              accountId: r.accountId,
              resourceType: r.resourceType,
              operation: r.operation,
              resourceId: r.resourceId,
              payload: _decodeMap(r.payload),
              createdAt: r.createdAt,
              retryCount: r.retryCount,
              lastError: r.lastError,
            ))
        .toList();
  }

  Future<void> markSyncItemSynced(String itemId, {DateTime? at}) async {
    await (update(syncQueue)..where((t) => t.id.equals(itemId))).write(
      SyncQueueCompanion(syncedAt: Value(at ?? DateTime.now())),
    );
  }

  Future<void> markSyncItemFailed(String itemId, String error) async {
    final row = (await (select(syncQueue)
          ..where((t) => t.id.equals(itemId)))
        .getSingleOrNull());
    final currentRetry = row?.retryCount ?? 0;
    await (update(syncQueue)..where((t) => t.id.equals(itemId))).write(
      SyncQueueCompanion(
        lastError: Value(error),
        retryCount: Value(currentRetry + 1),
      ),
    );
  }

  Future<int> clearSyncedItems({int olderThanSeconds = 0}) async {
    final cutoff =
        DateTime.now().subtract(Duration(seconds: olderThanSeconds));
    return await (delete(syncQueue)
          ..where((t) => t.syncedAt.isNotNull() & t.syncedAt.isSmallerOrEqualValue(cutoff)))
        .go();
  }

  // ----- routines -----

  Future<void> saveRoutine(String patientId, List<RoutineStep> steps) async {
    await into(patientRoutines).insertOnConflictUpdate(
      PatientRoutinesCompanion.insert(
        patientId: patientId,
        stepsJson: jsonEncode(steps.map((s) => s.toJson()).toList()),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<List<RoutineStep>> getRoutine(String patientId) async {
    final row = await (select(patientRoutines)
          ..where((t) => t.patientId.equals(patientId)))
        .getSingleOrNull();
    if (row == null) return [];
    final data = jsonDecode(row.stepsJson) as List;
    return data.map((s) => RoutineStep.fromJson(s as Map<String, dynamic>)).toList();
  }

  // ----- helpers -----

  Map<String, dynamic> _decodeMap(String source) {
    try {
      return jsonDecode(source) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'eldercare.db'));
    return NativeDatabase.createInBackground(file);
  });
}

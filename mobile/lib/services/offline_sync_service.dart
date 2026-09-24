/// Offline-first sync — queues game sessions, game actions, and reminder
/// acknowledgments locally (drift/SQLite) and flushes them to the backend
/// when connectivity returns.
///
/// Replay strategy (matches the backend contract):
///   - game_session: create a fresh server session, replay the recorded
///     actions (each is_correct / response_time_ms), then complete it so the
///     server computes the same metrics as the online path.
///   - reminder_event: acknowledge the event; 404s are treated as handled
///     (the event was never delivered server-side) and marked synced.
///
/// Backend `/api/v1/sync` exists for generic resource types (offline_symptom
/// etc.); game/reminder events use the live endpoints so analytics stay
/// correct.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../database/app_database.dart';
import '../models/game_models.dart';
import '../models/shared_models.dart';
import 'api_service.dart';

class OfflineSyncService {
  final AppDatabase db;
  final ApiService api;

  OfflineSyncService({AppDatabase? db, ApiService? api})
      : db = db ?? AppDatabase(),
        api = api ?? ApiService.instance;

  static final OfflineSyncService instance = OfflineSyncService();

  Timer? _timer;
  bool _syncing = false;
  String? _activeAccountId;
  int _syncGeneration = 0;
  int _runId = 0;
  String? _lastFailure;

  /// Lightweight connectivity probe (no auth required).
  Future<bool> probeOnline() async {
    try {
      await api.getJson('${AppConfig.apiV1}/language/status',
          includeAuth: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  String? get activeAccountId => _activeAccountId;

  String? get lastFailure => _lastFailure;

  bool get isRunning => _timer != null;

  void setActiveAccount(String? accountId) {
    if (_activeAccountId == accountId) return;
    _activeAccountId = accountId;
    _syncGeneration++;
    _runId++;
    _syncing = false;
    _lastFailure = null;
  }

  void resetForLogout() {
    stop();
    _activeAccountId = null;
  }

  bool _isCancelled(int generation) => generation != _syncGeneration;

  void _throwIfCancelled(int generation) {
    if (_isCancelled(generation)) throw const _SyncCancelled();
  }

  String _idempotencyKey(SyncQueueItem item) =>
      item.idempotencyKey ?? 'offline-sync-${item.id}';

  String? _stringValue(Object? value) {
    if (value == null) return null;
    if (value is! String || value.isEmpty) {
      throw ApiException('Invalid sync metadata');
    }
    return value;
  }

  DateTime? _dateTimeValue(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null) throw ApiException('Invalid sync timestamp');
      return parsed;
    }
    throw ApiException('Invalid sync timestamp');
  }

  String? _accountIdForItem(SyncQueueItem item) {
    if (item.accountId != null && item.accountId!.isNotEmpty) {
      return item.accountId;
    }
    final value = item.payload['account_id'];
    return value is String && value.isNotEmpty ? value : null;
  }

  // ------------------------------------------------------------------
  // Enqueue helpers (call these when the online request fails)
  // ------------------------------------------------------------------

  Future<void> enqueueReminderAck({
    required String patientId,
    required String eventId,
    required String method,
  }) async {
    final createdAt = DateTime.now();
    await db.enqueueSyncItem(SyncQueueItem(
      id: 'ack_${createdAt.millisecondsSinceEpoch}_$eventId',
      patientId: patientId,
      accountId: _activeAccountId,
      resourceType: 'reminder_event',
      operation: 'update',
      resourceId: eventId,
      payload: {
        'status': 'acknowledged',
        'acknowledgment_method': method,
        'acknowledged_at': createdAt.toIso8601String(),
        'idempotency_key': _newUuidV4(),
        if (_activeAccountId != null) 'account_id': _activeAccountId,
      },
      createdAt: createdAt,
    ));
  }

  /// Clinical-note queue item builder (pure — unit-tested without a database).
  ///
  /// Notes ride the existing `offline_symptom` pipeline (no new enum, no
  /// migration): the backend consumer materializes `offline_symptom`/`create`
  /// into an encrypted `SymptomLog`, categorized by entry `source`. The local
  /// queue id is timestamp-based like the other enqueue helpers; `resourceId`
  /// is a client-generated UUID v4 (stdlib `dart:math` only — no new
  /// dependency) because `/api/v1/sync` requires a UUID `resource_id`.
  static SyncQueueItem clinicalNoteItem({
    required String patientId,
    required String enteredBy,
    required String source,
    required int severity,
    required String notes,
    required DateTime recordedAt,
    String? accountId,
    String? idempotencyKey,
  }) {
    assert(severity >= 1 && severity <= 5, 'severity must be 1-5');
    final ms = DateTime.now().millisecondsSinceEpoch;
    return SyncQueueItem(
      id: 'clinical_${ms}_$patientId',
      patientId: patientId,
      accountId: accountId,
      resourceType: 'offline_symptom',
      operation: 'create',
      resourceId: _newUuidV4(),
      payload: {
        'entered_by': enteredBy,
        'source': source,
        'severity': severity,
        'notes': notes,
        'recorded_at': recordedAt.toIso8601String(),
        if (accountId != null) 'account_id': accountId,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      },
      createdAt: DateTime.now(),
    );
  }

  /// Queue a clinical note for offline-safe delivery via the symptom pipeline.
  /// The flush path (`syncNow` → `_pushGeneric`) already posts the correct
  /// `/api/v1/sync` envelope for generic items, so nothing changes there.
  Future<void> enqueueClinicalNote({
    required String patientId,
    required String enteredBy,
    required String source,
    required int severity,
    required String notes,
    required DateTime recordedAt,
  }) async {
    await db.enqueueSyncItem(clinicalNoteItem(
      patientId: patientId,
      enteredBy: enteredBy,
      source: source,
      severity: severity,
      notes: notes,
      recordedAt: recordedAt,
      accountId: _activeAccountId,
      idempotencyKey: _newUuidV4(),
    ));
  }

  /// Client-generated UUID v4 without new dependencies.
  static String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant RFC 4122
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> enqueueGameSession({
    required String patientId,
    required GameSessionModel session,
    required List<GameAction> actions,
    String? contentPackId,
    String? routineId,
  }) async {
    final createdAt = DateTime.now();
    await db.enqueueSyncItem(SyncQueueItem(
      id: 'game_${session.id}',
      patientId: patientId,
      accountId: _activeAccountId,
      resourceType: 'game_session',
      operation: 'create',
      resourceId: session.id,
      payload: {
        'game_type': gameTypeToApi(session.gameType),
        'difficulty_level': session.difficultyLevel,
        'patient_id': patientId,
        if (contentPackId != null) 'content_pack_id': contentPackId,
        if (routineId != null) 'routine_id': routineId,
        'started_at': session.startedAt.toIso8601String(),
        'completed_at': session.completedAt?.toIso8601String(),
        'idempotency_key': _newUuidV4(),
        if (_activeAccountId != null) 'account_id': _activeAccountId,
        'actions': actions.map((a) => a.toJson()).toList(),
      },
      createdAt: createdAt,
    ));
  }

  /// Push unsynced local session/action rows through the same replay path.
  Future<void> enqueueStoredUnsynced({required String patientId}) async {
    final sessions = await db.getUnsyncedSessions();
    final actions = await db.getUnsyncedActions();
    for (final session in sessions) {
      final sessionActions =
          actions.where((a) => a.sessionId == session.id).toList();
      await enqueueGameSession(
        patientId: patientId,
        session: session,
        actions: sessionActions,
      );
      await db.markSessionSynced(session.id);
      for (final a in sessionActions) {
        await db.markActionSynced(a.id);
      }
    }
  }

  // ------------------------------------------------------------------
  // Flush
  // ------------------------------------------------------------------

  Future<int> syncNow() async {
    if (_syncing) return 0;
    _syncing = true;
    final generation = _syncGeneration;
    final runId = ++_runId;
    var done = 0;
    _lastFailure = null;
    try {
      if (!await probeOnline()) return 0;
      _throwIfCancelled(generation);
      final items = await db.pendingSyncItems(
        accountId: _activeAccountId,
        unscopedOnly: _activeAccountId == null,
      );
      for (final item in items) {
        if (_isCancelled(generation)) break;
        try {
          final replayed = await _replay(item, generation);
          if (!replayed) continue;
          _throwIfCancelled(generation);
          await db.markSyncItemSynced(item.id);
          done++;
        } on _SyncCancelled {
          break;
        } on Exception catch (e) {
          if (_isCancelled(generation)) break;
          _lastFailure = '$e';
          debugPrint('Sync failed for ${item.id}: $e');
          await db.markSyncItemFailed(item.id, '$e');
        }
      }
      if (!_isCancelled(generation)) {
        await db.clearSyncedItems(olderThanSeconds: 7 * 24 * 3600);
      }
    } on _SyncCancelled {
      return done;
    } finally {
      if (runId == _runId) _syncing = false;
    }
    return done;
  }

  Future<bool> _replay(SyncQueueItem item, int generation) async {
    final itemAccountId = _accountIdForItem(item);
    final belongsToActiveAccount = _activeAccountId == null
        ? itemAccountId == null
        : itemAccountId == _activeAccountId;
    if (!belongsToActiveAccount) return false;
    if (item.resourceType == 'game_session') {
      await _replayGameSession(item, generation);
    } else if (item.resourceType == 'reminder_event') {
      await _replayReminderAck(item, generation);
    } else {
      await _pushGeneric(item, generation);
    }
    return true;
  }

  Future<void> _replayGameSession(SyncQueueItem item, int generation) async {
    final payload = Map<String, dynamic>.from(item.payload);
    final gameType = _stringValue(payload['game_type']) ?? 'match_it';
    final difficultyValue = payload['difficulty_level'];
    final difficultyLevel =
        difficultyValue is num ? difficultyValue.toInt() : 1;
    final patientId = _stringValue(payload['patient_id']) ?? item.patientId;
    if (patientId == null || patientId.isEmpty) {
      throw ApiException('Cannot replay game session without a patient id');
    }
    final startedAt = _dateTimeValue(payload['started_at']);
    final completedAt = _dateTimeValue(payload['completed_at']);
    final contentPackId = _stringValue(payload['content_pack_id']);
    final routineId = _stringValue(payload['routine_id']);
    final idempotencyKey = _idempotencyKey(item);
    final sessionId = await api.startGame(
      gameType: gameType,
      difficultyLevel: difficultyLevel,
      patientId: patientId,
      contentPackId: contentPackId,
      routineId: routineId,
      startedAt: startedAt,
      completedAt: completedAt,
      idempotencyKey: idempotencyKey,
    );
    _throwIfCancelled(generation);
    if (gameType == 'match_it') {
      if (contentPackId == null || contentPackId.isEmpty) {
        throw ApiException('Cannot replay Match It without a content pack');
      }
      await api.matchItBoard(
        packId: contentPackId,
        difficultyLevel: difficultyLevel,
        sessionId: sessionId,
      );
    } else if (gameType == 'routine_sequencing') {
      await api.routineBoard(
        patientId: patientId,
        difficultyLevel: difficultyLevel,
        sessionId: sessionId,
      );
    } else if (gameType == 'number_recall') {
      await api.recallBoard(
        difficultyLevel: difficultyLevel,
        sessionId: sessionId,
      );
    } else if (gameType == 'odd_one_out') {
      await api.getJson(
        '${AppConfig.apiV1}/games/odd-one-out/board',
        query: {
          'session_id': sessionId,
          'difficulty_level': '$difficultyLevel',
        },
      );
    }
    _throwIfCancelled(generation);
    final rawActions = payload['actions'];
    final actions = <Map<String, dynamic>>[];
    if (rawActions is List) {
      for (final rawAction in rawActions) {
        if (rawAction is Map) {
          actions.add(Map<String, dynamic>.from(rawAction));
        }
      }
    }
    final expectedActionIds = <String>[];
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index];
      final rawActionData = action['action_data'];
      final actionData = rawActionData is Map
          ? Map<String, dynamic>.from(rawActionData)
          : <String, dynamic>{};
      final actionId =
          action['id'] is String ? action['id'] as String : '$index';
      final responseTime = action['response_time_ms'];
      final actionIdempotencyKey = ApiService.actionIdempotencyKey(
        sessionId: sessionId,
        actionIndex: index,
        actionId: actionId,
      );
      expectedActionIds.add(actionIdempotencyKey);
      await api.recordGameAction(
        sessionId: sessionId,
        actionType: action['action_type'] is String
            ? action['action_type'] as String
            : 'tap',
        actionData: actionData,
        isCorrect: action['is_correct'] as bool?,
        responseTimeMs: responseTime is num ? responseTime.toInt() : null,
        idempotencyKey: actionIdempotencyKey,
      );
      _throwIfCancelled(generation);
    }
    await api.completeGame(
      sessionId,
      idempotencyKey: ApiService.completionIdempotencyKey(sessionId),
      expectedActionIds: expectedActionIds,
      completedAt: completedAt,
    );
    _throwIfCancelled(generation);
  }

  Future<void> _replayReminderAck(SyncQueueItem item, int generation) async {
    try {
      final acknowledged = await api.acknowledgeReminder(
        item.resourceId,
        method: item.payload['acknowledgment_method'] as String? ?? 'button',
        idempotencyKey: _idempotencyKey(item),
      );
      if (!acknowledged) {
        throw ApiException('Server did not apply reminder acknowledgment');
      }
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    _throwIfCancelled(generation);
  }

  Future<void> _pushGeneric(SyncQueueItem item, int generation) async {
    if (item.resourceType != 'offline_symptom' || item.operation != 'create') {
      throw ApiException('Sync item cannot be materialized: '
          '${item.resourceType}/${item.operation}');
    }
    final patientId =
        item.patientId ?? _stringValue(item.payload['patient_id']);
    if (patientId == null || patientId.isEmpty) {
      throw ApiException('Cannot sync item without a patient id');
    }
    final data = await api.postJson('${AppConfig.apiV1}/sync', body: {
      'patient_id': patientId,
      'items': [
        {
          'resource_type': item.resourceType,
          'operation': item.operation,
          'resource_id': item.resourceId,
          'payload': item.payload,
          'idempotency_key': _idempotencyKey(item),
        },
      ],
    });
    _throwIfCancelled(generation);
    if (data is! Map) {
      throw ApiException('Sync server returned an invalid response');
    }
    final map = Map<String, dynamic>.from(data);
    final errors = map['errors'];
    if (errors is List && errors.isNotEmpty) {
      throw ApiException('Backend rejected sync item: $errors');
    }
    final synced = map['synced'];
    if (synced is! num || synced.toInt() < 1) {
      throw ApiException('Sync server did not apply the item');
    }
  }

  // ------------------------------------------------------------------
  // Periodic sync (call start() from main after login)
  // ------------------------------------------------------------------

  void start({Duration interval = const Duration(seconds: 30)}) {
    _timer ??= Timer.periodic(interval, (_) => syncNow());
  }

  void stop() {
    _syncGeneration++;
    _runId++;
    _syncing = false;
    _timer?.cancel();
    _timer = null;
  }
}

class _SyncCancelled implements Exception {
  const _SyncCancelled();
}

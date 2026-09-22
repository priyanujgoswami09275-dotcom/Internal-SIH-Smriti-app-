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

  /// Lightweight connectivity probe (no auth required).
  Future<bool> probeOnline() async {
    try {
      await api.getJson('${AppConfig.apiV1}/language/status', includeAuth: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Enqueue helpers (call these when the online request fails)
  // ------------------------------------------------------------------

  Future<void> enqueueReminderAck({
    required String patientId,
    required String eventId,
    required String method,
  }) async {
    await db.enqueueSyncItem(SyncQueueItem(
      id: 'ack_${DateTime.now().millisecondsSinceEpoch}_$eventId',
      patientId: patientId,
      resourceType: 'reminder_event',
      operation: 'update',
      resourceId: eventId,
      payload: {
        'status': 'acknowledged',
        'acknowledgment_method': method,
        'acknowledged_at': DateTime.now().toIso8601String(),
      },
      createdAt: DateTime.now(),
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
  }) {
    assert(severity >= 1 && severity <= 5, 'severity must be 1-5');
    final ms = DateTime.now().millisecondsSinceEpoch;
    return SyncQueueItem(
      id: 'clinical_${ms}_$patientId',
      patientId: patientId,
      resourceType: 'offline_symptom',
      operation: 'create',
      resourceId: _newUuidV4(),
      payload: {
        'entered_by': enteredBy,
        'source': source,
        'severity': severity,
        'notes': notes,
        'recorded_at': recordedAt.toIso8601String(),
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
  }) async {
    await db.enqueueSyncItem(SyncQueueItem(
      id: 'game_${session.id}',
      patientId: patientId,
      resourceType: 'game_session',
      operation: 'create',
      resourceId: session.id,
      payload: {
        'game_type': gameTypeToApi(session.gameType),
        'difficulty_level': session.difficultyLevel,
        'content_pack_id': null,
        'started_at': session.startedAt.toIso8601String(),
        'completed_at': session.completedAt?.toIso8601String(),
        'actions': actions.map((a) => a.toJson()).toList(),
      },
      createdAt: DateTime.now(),
    ));
  }

  /// Push unsynced local session/action rows through the same replay path.
  Future<void> enqueueStoredUnsynced({required String patientId}) async {
    final sessions = await db.getUnsyncedSessions();
    final actions = await db.getUnsyncedActions();
    for (final session in sessions) {
      final sessionActions = actions.where((a) => a.sessionId == session.id).toList();
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
    var done = 0;
    try {
      if (!await probeOnline()) return 0;
      final items = await db.pendingSyncItems();
      for (final item in items) {
        try {
          await _replay(item);
          await db.markSyncItemSynced(item.id);
          done++;
        } on Exception catch (e) {
          debugPrint('Sync failed for ${item.id}: $e');
          await db.markSyncItemFailed(item.id, '$e');
        }
      }
      await db.clearSyncedItems(olderThanSeconds: 7 * 24 * 3600);
    } finally {
      _syncing = false;
    }
    return done;
  }

  Future<void> _replay(SyncQueueItem item) async {
    if (item.resourceType == 'game_session') {
      await _replayGameSession(item);
    } else if (item.resourceType == 'reminder_event') {
      await _replayReminderAck(item);
    } else {
      // Generic offline payloads are pushed to the backend sync outbox.
      await _pushGeneric(item);
    }
  }

  Future<void> _replayGameSession(SyncQueueItem item) async {
    final payload = Map<String, dynamic>.from(item.payload);
    final sessionId = await api.startGame(
      gameType: payload['game_type'] as String? ?? 'match_it',
      difficultyLevel: payload['difficulty_level'] as int? ?? 1,
    );
    final actions = (payload['actions'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    for (final action in actions) {
      await api.recordGameAction(
        sessionId: sessionId,
        actionType: action['action_type'] as String? ?? 'tap',
        actionData: action['action_data'] as Map<String, dynamic>? ?? const {},
        isCorrect: action['is_correct'] as bool?,
        responseTimeMs: action['response_time_ms'] as int?,
      );
    }
    await api.completeGame(sessionId);
  }

  Future<void> _replayReminderAck(SyncQueueItem item) async {
    try {
      await api.acknowledgeReminder(
        item.resourceId,
        method: item.payload['acknowledgment_method'] as String? ?? 'button',
      );
    } on ApiException catch (e) {
      // Event never reached the server — nothing to acknowledge; drop it.
      if (e.statusCode != 404) rethrow;
    }
  }

  Future<void> _pushGeneric(SyncQueueItem item) async {
    final patientId = item.patientId;
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
        },
      ],
    });
    final map = data as Map<String, dynamic>;
    if ((map['errors'] as List? ?? const []).isNotEmpty) {
      throw ApiException('Backend rejected sync item');
    }
  }

  // ------------------------------------------------------------------
  // Periodic sync (call start() from main after login)
  // ------------------------------------------------------------------

  void start({Duration interval = const Duration(seconds: 30)}) {
    _timer ??= Timer.periodic(interval, (_) => syncNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

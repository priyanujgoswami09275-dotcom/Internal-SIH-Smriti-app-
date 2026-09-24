/// Wave 3 Batch A tests (fix-it PLAN task 3.1): Odd-One-Out offline replay.
///
/// Offline odd-one-out taps are buffered with `isCorrect: null` and the
/// fresh server session has no board, so `_replayGameSession` must fetch a
/// fresh board for the NEW session (same path + query the screen uses)
/// after `startGame` and BEFORE replaying actions. Non-odd-one-out games
/// keep the byte-identical replay path (no board fetch). A failing board
/// fetch propagates so the item stays failed/retryable (`syncedAt` NULL).
///
/// Drives the public `syncNow` with an in-memory database + fake `ApiService`
/// (the `OfflineSyncService({db, api})` constructor seam — no refactor).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:eldercare_mobile/config/app_config.dart';
import 'package:eldercare_mobile/database/app_database.dart';
import 'package:eldercare_mobile/models/game_models.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:eldercare_mobile/services/offline_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReplayApi extends ApiService {
  FakeReplayApi() : super(baseUrl: 'http://fake.invalid');

  final List<String> calls = [];
  final List<Map<String, String>?> boardQueries = [];
  String? boardSessionId;
  final List<Map<String, dynamic>> recordedActions = [];
  bool failBoard = false;

  @override
  Future<String> startGame({
    required String gameType,
    required int difficultyLevel,
    String? contentPackId,
    String? routineId,
    String? patientId,
    DateTime? startedAt,
    DateTime? completedAt,
    String? idempotencyKey,
  }) async {
    calls.add('startGame:$gameType:$difficultyLevel');
    return 'server-new-1';
  }

  @override
  Future<dynamic> getJson(
    String path, {
    Map<String, String>? query,
    bool includeAuth = true,
  }) async {
    if (path.contains('language/status')) return {'status': 'ok'};
    if (path.contains('odd-one-out/board')) {
      calls.add('board:$path');
      boardQueries.add(query);
      boardSessionId = query?['session_id'];
      if (failBoard) throw ApiException('board down');
      return {'board': 'fresh'};
    }
    throw ApiException('unknown path $path');
  }

  @override
  Future<bool> recordGameAction({
    required String sessionId,
    required String actionType,
    Map<String, dynamic>? actionData,
    bool? isCorrect,
    int? responseTimeMs,
    String? idempotencyKey,
  }) async {
    calls.add('record:$actionType:$sessionId');
    recordedActions.add({
      'session_id': sessionId,
      'action_type': actionType,
      'action_data': actionData ?? const {},
      'is_correct': isCorrect,
      'response_time_ms': responseTimeMs,
    });
    return true;
  }

  @override
  Future<GameSessionSummary> completeGame(
    String sessionId, {
    String? idempotencyKey,
    DateTime? completedAt,
  }) async {
    calls.add('complete:$sessionId');
    return GameSessionSummary(
      sessionId: sessionId,
      gameType: 'odd_one_out',
      difficultyLevel: 2,
      totalAttempts: 1,
      correctCount: 1,
      incorrectCount: 0,
      accuracyPct: 100.0,
      avgResponseTimeMs: 800.0,
      startedAt: DateTime(2026, 9, 22, 10, 0, 0),
      completedAt: DateTime(2026, 9, 22, 10, 1, 0),
    );
  }
}

SyncQueueItem _gameItem({
  required String gameType,
  required int difficulty,
  required List<GameAction> actions,
}) {
  return SyncQueueItem(
    id: 'game_offline_1',
    patientId: 'p1',
    resourceType: 'game_session',
    operation: 'create',
    resourceId: 'offline_1',
    payload: {
      'game_type': gameType,
      'difficulty_level': difficulty,
      'content_pack_id': null,
      'started_at': DateTime(2026, 9, 22, 10, 0, 0).toIso8601String(),
      'completed_at': DateTime(2026, 9, 22, 10, 1, 0).toIso8601String(),
      'actions': actions.map((a) => a.toJson()).toList(),
    },
    createdAt: DateTime(2026, 9, 22, 10, 2, 0),
  );
}

GameAction _tap(String itemId) => GameAction(
      id: 'act_1_$itemId',
      sessionId: 'offline_1',
      actionType: 'select_odd_item',
      actionData: {'selected_item_id': itemId},
      responseTimeMs: 800,
      timestamp: DateTime(2026, 9, 22, 10, 0, 5),
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('odd-one-out replay fetches a fresh board before replaying actions',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final api = FakeReplayApi();
    final sync = OfflineSyncService(db: db, api: api);
    await db.enqueueSyncItem(_gameItem(
      gameType: 'odd_one_out',
      difficulty: 2,
      actions: [_tap('dhol'), _tap('kaji_nemu')],
    ));

    expect(await sync.syncNow(), 1);

    // Order: startGame → board fetch (NEW session id) → actions → complete.
    expect(api.calls, [
      'startGame:odd_one_out:2',
      'board:${AppConfig.apiV1}/games/odd-one-out/board',
      'record:select_odd_item:server-new-1',
      'record:select_odd_item:server-new-1',
      'complete:server-new-1',
    ]);
    // Board fetch targets the NEW session + the queued difficulty.
    expect(api.boardSessionId, 'server-new-1');
    expect(api.boardQueries.single?['difficulty_level'], '2');
    // Buffered actions replay unchanged (server re-scores; offline taps
    // were never judged locally).
    expect(api.recordedActions, hasLength(2));
    expect(
      api.recordedActions[0]['action_data'],
      {'selected_item_id': 'dhol'},
    );
    expect(api.recordedActions[0]['is_correct'], isNull);
    expect(api.recordedActions[1]['action_data'],
        {'selected_item_id': 'kaji_nemu'});
    // Item marked synced.
    expect(await db.pendingSyncItems(), isEmpty);
  });

  test('match_it replay performs no board fetch', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final api = FakeReplayApi();
    final sync = OfflineSyncService(db: db, api: api);
    await db.enqueueSyncItem(_gameItem(
      gameType: 'match_it',
      difficulty: 1,
      actions: [
        GameAction(
          id: 'act_1_flip',
          sessionId: 'offline_1',
          actionType: 'flip',
          actionData: {'card': 3},
          isCorrect: true,
          responseTimeMs: 500,
          timestamp: DateTime(2026, 9, 22, 10, 0, 5),
        ),
      ],
    ));

    expect(await sync.syncNow(), 1);

    expect(api.calls, [
      'startGame:match_it:1',
      'record:flip:server-new-1',
      'complete:server-new-1',
    ]);
    expect(api.boardQueries, isEmpty);
  });

  test('board fetch failure leaves the item failed/retryable', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final api = FakeReplayApi()..failBoard = true;
    final sync = OfflineSyncService(db: db, api: api);
    await db.enqueueSyncItem(_gameItem(
      gameType: 'odd_one_out',
      difficulty: 2,
      actions: [_tap('dhol')],
    ));

    expect(await sync.syncNow(), 0);

    // Nothing replayed past the board fetch; completion never ran.
    expect(api.recordedActions, isEmpty);
    expect(api.calls.any((c) => c.startsWith('complete:')), isFalse);
    // Item stays failed/retryable: syncedAt NULL so it is still pending.
    final pending = await db.pendingSyncItems();
    expect(pending, hasLength(1));
    expect(pending.single.lastError, isNotNull);
  });

  test('markSyncItemFailed increments retryCount and stays pending', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.enqueueSyncItem(_gameItem(
      gameType: 'match_it',
      difficulty: 1,
      actions: [],
    ));
    await db.markSyncItemFailed('game_offline_1', 'network error');
    var pending = await db.pendingSyncItems();
    expect(pending, hasLength(1));
    expect(pending.single.retryCount, 1);
    expect(pending.single.lastError, 'network error');
    await db.markSyncItemFailed('game_offline_1', 'network error');
    pending = await db.pendingSyncItems();
    expect(pending, hasLength(1));
    expect(pending.single.retryCount, 2);
  });
}

/// Odd-One-Out screen tests (slice C-03', task 3).
///
/// Covers the brief's test list: four distinct API mappings, no fifth game,
/// Recall intact, server config override changes item count/timing,
/// correct/incorrect selection (flat + real event-envelope echo),
/// informational vs resolved attempts, all three config levels, reconnect
/// retry, server-level mismatch, unavailable cached content, source/reason
/// labels shown when the summary carries them (hidden otherwise).
/// Home card→screen wiring lives in the private patient home behind the
/// auth gate (append-only fourth card per review); it is a C-04' device
/// check, not a widget test.
///
/// Real widgets throughout; only the network/sync seams are faked
/// (FakeApiService / FakeSync injected via the screen constructor).
library;

import 'dart:convert';

import 'package:eldercare_mobile/games/level_config.dart';
import 'package:eldercare_mobile/models/game_models.dart';
import 'package:eldercare_mobile/models/shared_models.dart';
import 'package:eldercare_mobile/screens/odd_one_out_screen.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:eldercare_mobile/services/offline_sync_service.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Board payload shape per the brief (backend contract, authoritative).
/// NEVER contains the answer.
Map<String, dynamic> _boardJson({
  int difficultyLevel = 1,
  List<Map<String, String>>? items,
  String groupLabel = 'Fruits',
}) {
  final list = items ??
      const [
        {'item_id': 'kaji_nemu', 'name': 'Kaji Nemu'},
        {'item_id': 'ou_tenga', 'name': 'Ou Tenga'},
        {'item_id': 'dhol', 'name': 'Dhol'},
      ];
  return {
    'game_type': 'odd_one_out',
    'difficulty_level': difficultyLevel,
    'items': list,
    'item_count': list.length,
    'target_seconds': 45,
    'group_label': groupLabel,
    'explanation': 'Dhol is an instrument, not a fruit.',
  };
}

Map<String, dynamic> _nItemBoard(int n,
    {int difficultyLevel = 1, int targetSeconds = 45}) {
  return {
    'game_type': 'odd_one_out',
    'difficulty_level': difficultyLevel,
    'items': [
      for (var i = 0; i < n; i++) {'item_id': 'item_$i', 'name': 'Item $i'},
    ],
    'item_count': n,
    'target_seconds': targetSeconds,
    'group_label': 'Things',
    'explanation': 'Item 0 does not belong with the rest.',
  };
}

class FakeApiService extends ApiService {
  FakeApiService() : super(baseUrl: 'http://fake.invalid');

  /// When non-null, fetchLevelConfig returns {'config': this}.
  Map<String, dynamic>? levelConfigJson;
  bool failStart = false;
  Map<String, dynamic>? boardJson;
  Future<Map<String, dynamic>> Function(Map<String, dynamic> body)?
      actionHandler;
  GameSessionSummary? completeSummary;

  int startCalls = 0;
  String? lastGameType;
  int? lastDifficulty;
  String sessionId = 'sess-ooo-1';
  final List<Map<String, dynamic>> postedActions = [];
  int completeCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchLevelConfig() async {
    final cfg = levelConfigJson;
    if (cfg == null) throw ApiException('offline');
    return {'config': cfg};
  }

  @override
  Future<String> startGame({
    required String gameType,
    required int difficultyLevel,
    String? contentPackId,
    String? routineId,
  }) async {
    startCalls++;
    lastGameType = gameType;
    lastDifficulty = difficultyLevel;
    if (failStart) throw ApiException('offline');
    return sessionId;
  }

  @override
  Future<dynamic> getJson(
    String path, {
    Map<String, String>? query,
    bool includeAuth = true,
  }) async {
    if (path.contains('odd-one-out/board')) {
      final board = boardJson;
      if (board == null) throw ApiException('offline');
      return board;
    }
    throw ApiException('unknown path $path');
  }

  @override
  Future<dynamic> postJson(
    String path, {
    Map<String, dynamic>? body,
    bool includeAuth = true,
  }) async {
    if (path.contains('/actions')) {
      postedActions.add(body ?? const {});
      final handler = actionHandler;
      if (handler == null) throw ApiException('offline');
      return handler(body ?? const {});
    }
    throw ApiException('unknown path $path');
  }

  @override
  Future<GameSessionSummary> completeGame(String sessionId) async {
    completeCalls++;
    final summary = completeSummary;
    if (summary == null) throw ApiException('offline');
    return summary;
  }
}

GameSessionSummary _summary({
  int nextLevel = 2,
  String source = 'rule_fallback',
  String reason = 'steady',
}) {
  return GameSessionSummary(
    sessionId: 'sess-ooo-1',
    gameType: 'odd_one_out',
    difficultyLevel: 1,
    totalAttempts: 1,
    correctCount: 1,
    incorrectCount: 0,
    accuracyPct: 100.0,
    avgResponseTimeMs: 1200.0,
    startedAt: DateTime(2026, 9, 21, 10, 0, 0),
    completedAt: DateTime(2026, 9, 21, 10, 1, 0),
    nextDifficultyLevel: nextLevel,
    source: source,
    reason: reason,
  );
}

/// Real endpoint shape: summary fields only, no continuation keys.
GameSessionSummary _plainSummary() {
  return GameSessionSummary(
    sessionId: 'sess-ooo-1',
    gameType: 'odd_one_out',
    difficultyLevel: 1,
    totalAttempts: 1,
    correctCount: 1,
    incorrectCount: 0,
    accuracyPct: 100.0,
    avgResponseTimeMs: 1200.0,
    startedAt: DateTime(2026, 9, 21, 10, 0, 0),
    completedAt: DateTime(2026, 9, 21, 10, 1, 0),
  );
}

class FakeSync extends OfflineSyncService {
  FakeSync() : super(api: FakeApiService());

  final List<GameSessionModel> enqueuedSessions = [];
  final List<List<GameAction>> enqueuedActions = [];

  @override
  Future<void> enqueueGameSession({
    required String patientId,
    required GameSessionModel session,
    required List<GameAction> actions,
  }) async {
    enqueuedSessions.add(session);
    enqueuedActions.add(actions);
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeApiService api,
  required FakeSync sync,
  int initialDifficulty = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OddOneOutScreen(
        patientId: 'p1',
        initialDifficulty: initialDifficulty,
        api: api,
        sync: sync,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapStart(WidgetTester tester) async {
  await tester.tap(find.text('START ▸'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Finder _tiles() => find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey &&
          (w.key as ValueKey)
              .value
              .toString()
              .startsWith('ooo_tile_'),
    );

void main() {
  // FakeSync builds a lazy (never opened) AppDatabase per instance; silence
  // drift's multiple-database warning for these unopened test doubles.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Reset the static LevelConfig to bundled between tests.
    await LevelConfig.refresh(FakeApiService());
  });

  group('GameType API mappings', () {
    test('four distinct snake_case mappings round-trip', () {
      expect(gameTypeFromApi('match_it'), GameType.matchIt);
      expect(gameTypeFromApi('routine_sequencing'), GameType.routineSequencing);
      expect(gameTypeFromApi('number_recall'), GameType.numberRecall);
      expect(gameTypeFromApi('odd_one_out'), GameType.oddOneOut);
      expect(gameTypeToApi(GameType.matchIt), 'match_it');
      expect(gameTypeToApi(GameType.routineSequencing), 'routine_sequencing');
      expect(gameTypeToApi(GameType.numberRecall), 'number_recall');
      expect(gameTypeToApi(GameType.oddOneOut), 'odd_one_out');
    });

    test('no fifth game', () {
      expect(GameType.values.length, 4);
    });

    test('Recall routing intact', () {
      expect(gameTypeFromApi('number_recall'), GameType.numberRecall);
      expect(gameTypeToApi(GameType.numberRecall), 'number_recall');
      // Unknown values still fall back to Match It, as before.
      expect(gameTypeFromApi('word_mode'), GameType.matchIt);
    });
  });

  group('OddOneOutBoard model', () {
    test('parses the brief board shape', () {
      final board = OddOneOutBoard.fromServerJson(_boardJson());
      expect(board.gameType, 'odd_one_out');
      expect(board.difficultyLevel, 1);
      expect(board.items.map((i) => i.itemId),
          ['kaji_nemu', 'ou_tenga', 'dhol']);
      expect(board.items.map((i) => i.name),
          ['Kaji Nemu', 'Ou Tenga', 'Dhol']);
      expect(board.itemCount, 3);
      expect(board.targetSeconds, 45);
      expect(board.groupLabel, 'Fruits');
      expect(board.explanation, contains('instrument'));
    });

    test('never carries the answer, even if the server sent one', () {
      final raw = _boardJson()..['answer_item_id'] = 'dhol';
      final board = OddOneOutBoard.fromServerJson(raw);
      // The model has no answer surface: serializing it cannot leak one.
      expect(jsonEncode(board.toJson()), isNot(contains('answer_item_id')));
      expect(board.toJson().keys,
          isNot(contains('answer_item_id')));
    });

    test('cache round-trip preserves items and labels', () {
      final board = OddOneOutBoard.fromServerJson(_boardJson());
      final restored = OddOneOutBoard.fromJson(board.toJson());
      expect(restored.items.map((i) => i.itemId).toList(),
          board.items.map((i) => i.itemId).toList());
      expect(restored.groupLabel, board.groupLabel);
      expect(restored.explanation, board.explanation);
    });
  });

  group('GameSessionSummary server-truth fields', () {
    test('ignores non-summary keys (endpoint returns summary fields only)',
        () {
      final summary = GameSessionSummary.fromJson({
        'session_id': 's1',
        'game_type': 'odd_one_out',
        'difficulty_level': 1,
        'total_attempts': 1,
        'correct_count': 1,
        'incorrect_count': 0,
        'accuracy_pct': 100.0,
        'avg_response_time_ms': 1200.0,
        'started_at': '2026-09-21T10:00:00',
        'completed_at': '2026-09-21T10:01:00',
        // Speculative shapes with no backend source are never trusted.
        'next_difficulty_level': 2,
        'next_level': 2,
        'source': 'rule_fallback',
        'decision_source': 'rule_fallback',
        'reason': 'steady',
        'decision_reason': 'steady',
      });
      expect(summary.accuracyPct, 100.0);
      expect(summary.nextDifficultyLevel, isNull);
      expect(summary.source, isNull);
      expect(summary.reason, isNull);
    });

    test('older payloads without the fields still parse (nulls)', () {
      final summary = GameSessionSummary.fromJson({
        'session_id': 's1',
        'game_type': 'match_it',
        'difficulty_level': 1,
        'total_attempts': 2,
        'correct_count': 1,
        'incorrect_count': 1,
        'accuracy_pct': 50.0,
        'avg_response_time_ms': 900.0,
        'started_at': '2026-09-21T10:00:00',
        'completed_at': '2026-09-21T10:01:00',
      });
      expect(summary.nextDifficultyLevel, isNull);
      expect(summary.source, isNull);
      expect(summary.reason, isNull);
    });
  });

  group('LevelConfig odd_one_out', () {
    test('bundled levels are 3/4/6 items with 45/70/120s targets', () {
      const levels = LevelConfig.bundled;
      expect(levels.oddOneOutItems(1), 3);
      expect(levels.oddOneOutItems(2), 4);
      expect(levels.oddOneOutItems(3), 6);
      expect(levels.targetSeconds('odd_one_out', 1), 45);
      expect(levels.targetSeconds('odd_one_out', 2), 70);
      expect(levels.targetSeconds('odd_one_out', 3), 120);
    });

    test('unknown level falls back to 3 items', () {
      expect(LevelConfig.bundled.oddOneOutItems(99), 3);
    });
  });

  // NOTE (review round 1, item 2): the patient home is a private widget
  // behind the auth gate, so card→screen wiring is not reachable from
  // widget tests; it is covered by the C-04' device checkpoint instead.
  // The four API mappings + no-fifth-game pins above guard the routing.
  group('OddOneOutScreen online', () {
    testWidgets('loads board: tiles, group label, server level header',
        (tester) async {
      final api = FakeApiService()..boardJson = _boardJson();
      await _pumpScreen(tester, api: api, sync: FakeSync());
      expect(api.lastGameType, 'odd_one_out');
      expect(api.lastDifficulty, 1);
      // Ready panel shows bundled params before Start.
      expect(find.text('3 items · 45s target'), findsOneWidget);
      await _tapStart(tester);
      expect(find.text('Kaji Nemu'), findsOneWidget);
      expect(find.text('Ou Tenga'), findsOneWidget);
      expect(find.text('Dhol'), findsOneWidget);
      expect(_tiles(), findsNWidgets(3));
      expect(find.text('Fruits'), findsOneWidget);
      expect(find.text('Level 1'), findsOneWidget);
    });

    testWidgets('server config override changes item count and timing',
        (tester) async {
      final api = FakeApiService()
        ..levelConfigJson = {
          'odd_one_out': {
            '1': {'items': 5, 'target_seconds': 90},
            '2': {'items': 4, 'target_seconds': 70},
            '3': {'items': 6, 'target_seconds': 120},
          },
        }
        ..boardJson = _nItemBoard(5, targetSeconds: 90);
      await _pumpScreen(tester, api: api, sync: FakeSync());
      expect(find.text('5 items · 90s target'), findsOneWidget);
      await _tapStart(tester);
      expect(_tiles(), findsNWidgets(5));
      expect(find.text('Time 1s of 90s'), findsOneWidget);
    });

    testWidgets('correct selection shows correct state + server summary',
        (tester) async {
      final api = FakeApiService()
        ..boardJson = _boardJson()
        ..completeSummary = _summary();
      api.actionHandler = (body) async => {'is_correct': true};
      await _pumpScreen(tester, api: api, sync: FakeSync());
      await _tapStart(tester);
      await tester.tap(find.text('Dhol'));
      await tester.pumpAndSettle();
      // Server verdict posted with the brief's action shape.
      expect(api.postedActions, hasLength(1));
      expect(api.postedActions.single['action_type'], 'select_odd_item');
      expect(
        (api.postedActions.single['action_data']
            as Map)['selected_item_id'],
        'dhol',
      );
      expect(api.completeCalls, 1);
      // Resolved correct state + server-truth labels in the result view.
      expect(find.byIcon(Icons.check_circle), findsWidgets);
      expect(find.text('Game completed'), findsOneWidget);
      expect(find.text('Correct!'), findsOneWidget);
      expect(find.text('Level 2'), findsWidgets);
      expect(find.text('rule_fallback'), findsOneWidget);
      expect(find.text('steady'), findsOneWidget);
    });

    testWidgets('real action echo envelope resolves correct', (tester) async {
      final api = FakeApiService()
        ..boardJson = _boardJson()
        ..completeSummary = _summary();
      // Real backend echo: {status, event{timestamp, action_type,
      // action_data{...server verdict...}, is_correct, response_time_ms}}.
      api.actionHandler = (body) async => {
            'status': 'ok',
            'event': {
              'timestamp': '2026-09-21T10:00:05',
              'action_type': 'select_odd_item',
              'action_data': {
                'selected_item_id': 'dhol',
                'is_correct': true,
                'error_category': 'none',
              },
              'is_correct': true,
              'response_time_ms': 800,
            },
          };
      await _pumpScreen(tester, api: api, sync: FakeSync());
      await _tapStart(tester);
      await tester.tap(find.text('Dhol'));
      await tester.pumpAndSettle();
      expect(api.completeCalls, 1);
      expect(find.byIcon(Icons.check_circle), findsWidgets);
      expect(find.text('Game completed'), findsOneWidget);
      expect(find.text('Correct!'), findsOneWidget);
    });

    testWidgets('real action echo envelope resolves incorrect',
        (tester) async {
      final api = FakeApiService()
        ..boardJson = _boardJson()
        ..completeSummary = _summary();
      api.actionHandler = (body) async => {
            'status': 'ok',
            'event': {
              'timestamp': '2026-09-21T10:00:05',
              'action_type': 'select_odd_item',
              'action_data': {
                'selected_item_id': 'kaji_nemu',
                'is_correct': false,
                'error_category': 'semantic_category',
              },
              'is_correct': false,
              'response_time_ms': 900,
            },
          };
      await _pumpScreen(tester, api: api, sync: FakeSync());
      await _tapStart(tester);
      await tester.tap(find.text('Kaji Nemu'));
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('Game completed'), findsNothing);
      expect(api.completeCalls, 0);
    });

    testWidgets('summary without continuation keys hides those rows',
        (tester) async {
      final api = FakeApiService()
        ..boardJson = _boardJson()
        ..completeSummary = _plainSummary();
      api.actionHandler = (body) async => {'is_correct': true};
      await _pumpScreen(tester, api: api, sync: FakeSync());
      await _tapStart(tester);
      await tester.tap(find.text('Dhol'));
      await tester.pumpAndSettle();
      expect(find.text('Game completed'), findsOneWidget);
      expect(find.text('Correct!'), findsOneWidget);
      expect(find.text('Attempts'), findsOneWidget);
      // Never fabricated when the endpoint does not send them.
      expect(find.text('Next level'), findsNothing);
      expect(find.text('Source'), findsNothing);
      expect(find.text('Reason'), findsNothing);
    });

    testWidgets('incorrect selection marks the tile, game continues',
        (tester) async {
      final api = FakeApiService()
        ..boardJson = _boardJson()
        ..completeSummary = _summary();
      api.actionHandler = (body) async => {'is_correct': false};
      await _pumpScreen(tester, api: api, sync: FakeSync());
      await _tapStart(tester);
      await tester.tap(find.text('Kaji Nemu'));
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);
      // No completion dialog: the round continues for another pick.
      expect(find.text('Game completed'), findsNothing);
      expect(api.completeCalls, 0);
      // A second pick posts a second resolved attempt.
      await tester.tap(find.text('Ou Tenga'));
      await tester.pump();
      expect(api.postedActions, hasLength(2));
    });

    testWidgets('server-level mismatch adopts the server level',
        (tester) async {
      final api = FakeApiService()
        ..boardJson = _boardJson(difficultyLevel: 2);
      await _pumpScreen(tester,
          api: api, sync: FakeSync(), initialDifficulty: 1);
      await _tapStart(tester);
      // The board's level (server truth) is displayed, not the request.
      expect(find.text('Level 2'), findsOneWidget);
    });

    testWidgets('all three config levels render 3/4/6 tiles',
        (tester) async {
      for (final entry in {1: 3, 2: 4, 3: 6}.entries) {
        final api = FakeApiService()
          ..boardJson = _nItemBoard(entry.value,
              difficultyLevel: entry.key);
        // Dispose the previous screen: same-type pumpWidget would reuse it.
        await tester.pumpWidget(const SizedBox());
        await _pumpScreen(tester,
            api: api,
            sync: FakeSync(),
            initialDifficulty: entry.key);
        await _tapStart(tester);
        expect(_tiles(), findsNWidgets(entry.value),
            reason: 'level ${entry.key}');
      }
    });

    testWidgets('disposing mid-play cancels timers cleanly',
        (tester) async {
      final api = FakeApiService()..boardJson = _boardJson();
      await _pumpScreen(tester, api: api, sync: FakeSync());
      await _tapStart(tester);
      expect(_tiles(), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      // No exception from a dangling timer.
      expect(tester.takeException(), isNull);
    });
  });

  group('OddOneOutScreen offline', () {
    testWidgets('cached board plays + queues with pending-sync label',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'smriti_ooo_board_v1': jsonEncode({'1': _boardJson()}),
      });
      final api = FakeApiService()..failStart = true;
      final sync = FakeSync();
      await _pumpScreen(tester, api: api, sync: sync);
      // Offline ready panel is honest about pending sync.
      expect(find.text('Pending sync'), findsOneWidget);
      await _tapStart(tester);
      expect(_tiles(), findsNWidgets(3));
      // Informational taps: selected state, nothing posted (no network).
      await tester.tap(find.text('Dhol'));
      await tester.pump();
      await tester.tap(find.text('Kaji Nemu'));
      await tester.pump();
      expect(api.postedActions, isEmpty);
      expect(find.text('Game completed'), findsNothing);
      // Finish queues the session with stable ids + original timestamps.
      await tester.tap(find.text('FINISH'));
      await tester.pumpAndSettle();
      expect(sync.enqueuedSessions, hasLength(1));
      final session = sync.enqueuedSessions.single;
      expect(session.gameType, GameType.oddOneOut);
      expect(session.difficultyLevel, 1);
      expect(sync.enqueuedActions.single, hasLength(2));
      final ids =
          sync.enqueuedActions.single.map((a) => a.id).toSet();
      // Unique even for taps landing in the same millisecond.
      expect(ids, hasLength(2));
      final action = sync.enqueuedActions.single.firstWhere(
          (a) => a.actionData['selected_item_id'] == 'dhol');
      expect(action.actionType, 'select_odd_item');
      expect(action.isCorrect, isNull); // informational, server scores later
      expect(action.id, startsWith('act_'));
      expect(
        action.timestamp.isBefore(DateTime.now().add(
            const Duration(seconds: 1))),
        isTrue,
      );
      expect(find.text('Game completed'), findsOneWidget);
      expect(find.text('Pending sync'), findsWidgets);
      expect(
        find.text('Offline: result will sync when you reconnect.'),
        findsOneWidget,
      );
    });

    testWidgets('no compatible cache shows connect-to-download state',
        (tester) async {
      final api = FakeApiService()..failStart = true;
      await _pumpScreen(tester, api: api, sync: FakeSync());
      expect(find.text('Connect to download to play'), findsOneWidget);
      expect(_tiles(), findsNothing);
      // Taxonomy/art is never synthesized offline.
      expect(find.text('Kaji Nemu'), findsNothing);
    });

    testWidgets('reconnect retry loads without duplicate audit',
        (tester) async {
      final api = FakeApiService()
        ..failStart = true
        ..boardJson = _boardJson();
      final sync = FakeSync();
      await _pumpScreen(tester, api: api, sync: sync);
      expect(find.text('Connect to download to play'), findsOneWidget);
      expect(sync.enqueuedSessions, isEmpty);
      // Reconnect: the retry only loads, it never queues.
      api.failStart = false;
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(find.text('3 items · 45s target'), findsOneWidget);
      expect(api.startCalls, 2);
      expect(sync.enqueuedSessions, isEmpty);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:eldercare_mobile/database/app_database.dart';
import 'package:eldercare_mobile/models/game_models.dart';
import 'package:eldercare_mobile/screens/match_it_screen.dart';
import 'package:eldercare_mobile/screens/odd_one_out_screen.dart';
import 'package:eldercare_mobile/screens/pack_picker_screen.dart';
import 'package:eldercare_mobile/screens/recall_screen.dart';
import 'package:eldercare_mobile/screens/routine_screen.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:eldercare_mobile/services/offline_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Request {
  _Request({required this.method, required this.uri, required this.body});

  final String method;
  final Uri uri;
  final String body;

  Map<String, dynamic> get json => body.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(body) as Map<String, dynamic>;
}

class _Reply {
  _Reply(this.status, this.body);

  final int status;
  final Object? body;
}

class _Transport {
  final List<_Request> requests = [];
  final Map<String, Map<String, dynamic>> sessions = {};
  final Set<String> appliedActionKeys = {};
  final Set<String> completionKeys = {};
  final Map<String, int> appliedActionCounts = {};
  Completer<void>? actionGate;
  int conflictResponses = 0;
  bool alwaysConflict = false;
  bool failGameBoards = false;
  int recommendedLevel = 2;
  double shadowProbability = 0.0;
  String explanation = 'Completed explanation.';
  int sessionCounter = 0;

  List<Map<String, dynamic>> get starts => requests
      .where((request) =>
          request.method == 'POST' &&
          request.uri.path.endsWith('/games/sessions'))
      .map((request) => request.json)
      .toList();

  List<_Request> get boards => requests
      .where((request) =>
          request.method == 'GET' && request.uri.path.contains('/board'))
      .toList();

  List<Map<String, dynamic>> get actions => requests
      .where((request) =>
          request.method == 'POST' && request.uri.path.endsWith('/actions'))
      .map((request) => request.json)
      .toList();

  List<Map<String, dynamic>> get completions => requests
      .where((request) =>
          request.method == 'POST' && request.uri.path.endsWith('/complete'))
      .map((request) => request.json)
      .toList();

  Future<_Reply> _handle(_Request request) async {
    requests.add(request);
    final path = request.uri.path;
    if (request.method == 'GET' && path.endsWith('/level-config')) {
      return _Reply(200, {
        'config': {
          'match_it': {
            '1': {'pairs': 1, 'target_seconds': 90},
            '2': {'pairs': 4, 'target_seconds': 150},
            '3': {'pairs': 6, 'target_seconds': 240},
          },
          'routine_sequencing': {
            '1': {
              'steps': 3,
              'hints': true,
              'icons': true,
              'target_seconds': 45
            },
            '2': {
              'steps': 4,
              'hints': true,
              'icons': true,
              'target_seconds': 70
            },
            '3': {
              'steps': 6,
              'hints': false,
              'icons': true,
              'target_seconds': 120
            },
          },
          'number_recall': {
            '1': {
              'sequence_length': 1,
              'show_seconds_per_item': 1,
              'target_seconds': 60
            },
            '2': {
              'sequence_length': 4,
              'show_seconds_per_item': 2,
              'target_seconds': 90
            },
            '3': {
              'sequence_length': 6,
              'show_seconds_per_item': 2,
              'target_seconds': 150
            },
          },
          'odd_one_out': {
            '1': {'items': 3, 'target_seconds': 45},
            '2': {'items': 4, 'target_seconds': 70},
            '3': {'items': 6, 'target_seconds': 120},
          },
        },
      });
    }
    if (request.method == 'GET' && path.endsWith('/content-packs')) {
      return _Reply(200, [
        {
          'id': 'festivals_ner',
          'name': 'NER Festivals',
          'region': 'North East India',
          'description': 'Festival memory cards.',
          'item_count': 2,
        },
      ]);
    }
    if (request.method == 'POST' && path.endsWith('/games/sessions')) {
      final body = request.json;
      final id = 'session-${++sessionCounter}';
      sessions[id] = body;
      return _Reply(200, {
        'session_id': id,
        'started_at': '2026-09-25T10:00:00.000Z',
      });
    }
    if (request.method == 'GET' &&
        path.contains('/content-packs/') &&
        path.endsWith('/board')) {
      if (failGameBoards) return _Reply(500, {'detail': 'board unavailable'});
      final level =
          int.tryParse(request.uri.queryParameters['difficulty_level'] ?? '') ??
              1;
      return _Reply(200, _matchBoard(level));
    }
    if (request.method == 'GET' && path.endsWith('/games/routine/board')) {
      if (failGameBoards) return _Reply(500, {'detail': 'board unavailable'});
      final level =
          int.tryParse(request.uri.queryParameters['difficulty_level'] ?? '') ??
              1;
      return _Reply(200, _routineBoard(level));
    }
    if (request.method == 'GET' && path.endsWith('/games/recall/board')) {
      final level =
          int.tryParse(request.uri.queryParameters['difficulty_level'] ?? '') ??
              1;
      return _Reply(200, {
        'game_type': 'number_recall',
        'difficulty_level': level,
        'sequence_length': 1,
        'show_seconds_per_item': 1,
        'sequence': [7],
      });
    }
    if (request.method == 'GET' && path.endsWith('/games/odd-one-out/board')) {
      return _Reply(200, {
        'game_type': 'odd_one_out',
        'difficulty_level': int.tryParse(
                request.uri.queryParameters['difficulty_level'] ?? '') ??
            1,
        'items': const [
          {'item_id': 'fruit_a', 'name': 'Fruit A'},
          {'item_id': 'fruit_b', 'name': 'Fruit B'},
          {'item_id': 'odd_item', 'name': 'Odd Item'},
        ],
        'item_count': 3,
        'target_seconds': 45,
        'group_label': 'Fruits',
        'answer_item_id': 'secret_answer_id',
        'explanation': 'Pre-play secret explanation.',
      });
    }
    if (request.method == 'POST' && path.endsWith('/actions')) {
      final gate = actionGate;
      if (gate != null) await gate.future;
      final body = request.json;
      final sessionId =
          request.uri.pathSegments[request.uri.pathSegments.length - 2];
      final key = body['idempotency_key'] as String? ??
          'missing:${requests.where((item) => item.uri.path.endsWith('/actions')).length}';
      final effectiveKey = '$sessionId:$key';
      final replay = !appliedActionKeys.add(effectiveKey);
      if (!replay) {
        appliedActionCounts[effectiveKey] = 1;
      }
      final selected = body['action_data'] is Map
          ? (body['action_data'] as Map)['selected_item_id']
          : null;
      final correct = selected == 'odd_item' ? true : body['is_correct'];
      return _Reply(200, {
        'status': 'recorded',
        'event': {
          'timestamp': '2026-09-25T10:00:01.000Z',
          'action_type': body['action_type'],
          'action_data': body['action_data'],
          'is_correct': correct,
          'response_time_ms': body['response_time_ms'],
        },
        'idempotent_replay': replay,
      });
    }
    if (request.method == 'POST' && path.endsWith('/complete')) {
      if (alwaysConflict || conflictResponses > 0) {
        if (!alwaysConflict) conflictResponses--;
        return _Reply(409, {
          'detail': 'expected actions are not durable: action-1',
        });
      }
      final body = request.json;
      final sessionId =
          request.uri.pathSegments[request.uri.pathSegments.length - 2];
      final key =
          body['idempotency_key'] as String? ?? 'missing-completion-key';
      final replay = !completionKeys.add('$sessionId:$key');
      final session = sessions[sessionId] ?? const <String, dynamic>{};
      final gameType = session['game_type'] as String? ?? 'match_it';
      final level = (session['difficulty_level'] as num?)?.toInt() ?? 1;
      return _Reply(200, {
        'session_id': sessionId,
        'game_type': gameType,
        'difficulty_level': level,
        'total_attempts': 1,
        'correct_count': 1,
        'incorrect_count': 0,
        'accuracy_pct': 100.0,
        'avg_response_time_ms': 500.0,
        'started_at': '2026-09-25T10:00:00.000Z',
        'completed_at': '2026-09-25T10:01:00.000Z',
        'explanation': gameType == 'odd_one_out' ? explanation : null,
        'idempotent_replay': replay,
        'recommended_level': recommendedLevel,
        'difficulty_reason': 'rule hold',
        'difficulty_source': 'rule_fallback',
        'rule_triggered': 'hold',
        'rule_version': 'rules-v1',
        'shadow_probability': shadowProbability,
        'shadow_model_version': 'shadow-v1',
        'shadow_reason': 'informational only',
      });
    }
    if (request.method == 'GET' && path.endsWith('/language/status')) {
      return _Reply(200, {'status': 'ok'});
    }
    return _Reply(404, {'detail': 'unhandled ${request.method} $path'});
  }

  Map<String, dynamic> _matchBoard(int level) => {
        'pack_id': 'festivals_ner',
        'pack_name': 'NER Festivals',
        'difficulty_level': level,
        'pair_count': 1,
        'total_cards': 2,
        'cards': const [
          {
            'card_id': 1,
            'item_id': 'apple',
            'name_en': 'Apple',
            'name_as': 'Apple',
            'image_url': '',
          },
          {
            'card_id': 2,
            'item_id': 'apple',
            'name_en': 'Apple',
            'name_as': 'Apple',
            'image_url': '',
          },
        ],
      };

  Map<String, dynamic> _routineBoard(int level) => {
        'difficulty_level': level,
        'step_count': 3,
        'has_hints': true,
        'has_icons': true,
        'shuffled_items': const [
          {
            'step_id': 'tea',
            'order': 3,
            'time': '07:00',
            'title_en': 'Morning Tea',
            'icon': 'local_cafe',
          },
          {
            'step_id': 'wake',
            'order': 1,
            'time': '06:30',
            'title_en': 'Wake up',
            'icon': 'wb_sunny',
          },
          {
            'step_id': 'brush',
            'order': 2,
            'time': '06:45',
            'title_en': 'Brush teeth',
            'icon': 'brush',
          },
        ],
        'correct_sequence': const ['wake', 'brush', 'tea'],
      };
}

class _HttpOverrides extends HttpOverrides {
  _HttpOverrides(this.transport);

  final _Transport transport;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _HttpClient(transport);
}

class _HttpClient extends Fake implements HttpClient {
  _HttpClient(this.transport);

  final _Transport transport;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _HttpRequest(transport, method, url);

  @override
  void close({bool force = false}) {}
}

class _HttpRequest extends Fake implements HttpClientRequest {
  _HttpRequest(this.transport, this.httpMethod, this.url);

  final _Transport transport;
  final String httpMethod;
  final Uri url;
  final StringBuffer _body = StringBuffer();
  final _Headers _headers = _Headers();

  @override
  HttpHeaders get headers => _headers;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 20;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  void write(Object? object) => _body.write(object);

  @override
  void add(List<int> data) => _body.write(utf8.decode(data));

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _body.write(utf8.decode(chunk));
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final reply = await transport._handle(_Request(
      method: httpMethod,
      uri: url,
      body: _body.toString(),
    ));
    return _HttpResponse(reply.status, reply.body);
  }
}

class _Headers extends Fake implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values
        .putIfAbsent(name.toLowerCase(), () => <String>[])
        .add(value.toString());
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  String? value(String name) {
    final values = _values[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.join(',');
  }

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];
}

class _HttpResponse extends Fake implements HttpClientResponse {
  _HttpResponse(this.status, Object? body)
      : _bytes = utf8.encode(body == null ? '' : jsonEncode(body));

  final int status;
  final List<int> _bytes;

  @override
  int get statusCode => status;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpHeaders get headers {
    final headers = _Headers();
    headers.set('content-type', 'application/json');
    return headers;
  }

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => status >= 400 ? 'ERROR' : 'OK';

  @override
  List<Cookie> get cookies => const [];

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(_bytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}

void _installTransport(_Transport transport) {
  HttpOverrides.global = _HttpOverrides(transport);
  addTearDown(() => HttpOverrides.global = null);
}

Future<void> _disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineSyncService.instance.stop();
  });

  testWidgets('Match It binds the fetched board to its server session',
      (tester) async {
    final transport = _Transport();
    _installTransport(transport);
    await tester.pumpWidget(const MaterialApp(
      home: MatchItScreen(
        patientId: 'patient-profile',
        packId: 'festivals_ner',
        packName: 'NER Festivals',
        difficultyLevel: 1,
      ),
    ));
    addTearDown(() => _disposeScreen(tester));
    await tester.pumpAndSettle();

    expect(transport.boards, hasLength(1));
    expect(
        transport.boards.single.uri.queryParameters['session_id'], 'session-1');
  });

  testWidgets('Match It waits for actions, reuses keys, and retries completion',
      (tester) async {
    final actionGate = Completer<void>();
    addTearDown(() {
      if (!actionGate.isCompleted) actionGate.complete();
    });
    final transport = _Transport()
      ..actionGate = actionGate
      ..conflictResponses = 1
      ..recommendedLevel = 1;
    _installTransport(transport);
    await tester.pumpWidget(const MaterialApp(
      home: MatchItScreen(
        patientId: 'patient-profile',
        packId: 'festivals_ner',
        packName: 'NER Festivals',
        difficultyLevel: 1,
      ),
    ));
    addTearDown(() => _disposeScreen(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Card 1'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Card 2'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(transport.completions, isEmpty);

    actionGate.complete();
    await tester.pumpAndSettle();

    expect(transport.actions, hasLength(4));
    final keys = transport.actions
        .map((body) => body['idempotency_key'] as String?)
        .toList();
    expect(keys.every((key) => key != null && key.isNotEmpty), isTrue);
    expect(keys.toSet(), hasLength(2));
    expect(keys.every((key) => key!.length <= 200), isTrue);
    expect(
      transport.actions.any((body) => body.containsKey('is_correct')),
      isFalse,
    );
    expect(
      transport.actions.any((body) =>
          body['action_data'] is Map &&
          (body['action_data'] as Map).containsKey('is_correct')),
      isFalse,
    );
    expect(transport.appliedActionCounts.values, everyElement(1));

    expect(transport.completions, hasLength(2));
    final expectedIds = transport.completions.first['expected_action_ids'];
    expect(expectedIds, keys.take(2).toList());
    final completionKey = transport.completions.first['idempotency_key'];
    expect(completionKey, isA<String>());
    expect(transport.completions.last['idempotency_key'], completionKey);
    expect(find.text('Game completed'), findsOneWidget);
  });

  test('the same action idempotency key is applied once', () async {
    final transport = _Transport();
    _installTransport(transport);
    final api = ApiService(baseUrl: 'http://integrity.test');
    const key = 'session-1:0:client-action-1';

    await api.recordGameAction(
      sessionId: 'session-1',
      actionType: 'flip_card',
      actionData: const {'card_id': 1},
      idempotencyKey: key,
    );
    await api.recordGameAction(
      sessionId: 'session-1',
      actionType: 'flip_card',
      actionData: const {'card_id': 1},
      idempotencyKey: key,
    );

    expect(transport.actions, hasLength(2));
    expect(transport.actions.map((body) => body['idempotency_key']),
        everyElement(key));
    expect(transport.appliedActionCounts, hasLength(1));
    expect(transport.appliedActionCounts.values.single, 1);
  });

  test('completion retries a 409 three times with one stable key', () async {
    final transport = _Transport()..alwaysConflict = true;
    _installTransport(transport);
    final api = ApiService(baseUrl: 'http://integrity.test');
    Object? failure;

    try {
      await api.completeGame(
        'session-1',
        idempotencyKey: 'game-complete:session-1',
      );
    } catch (error) {
      failure = error;
    }

    expect(failure, isA<ApiException>());
    expect(transport.completions, hasLength(3));
    expect(
      transport.completions.map((body) => body['idempotency_key']),
      everyElement('game-complete:session-1'),
    );
  });

  for (final fixture in const [
    (
      gameType: 'match_it',
      pathSuffix: '/games/content-packs/festivals_ner/board',
      actionType: 'flip_card',
      actionData: {'card_id': 1},
      contentPackId: 'festivals_ner',
      routineId: null,
    ),
    (
      gameType: 'routine_sequencing',
      pathSuffix: '/games/routine/board',
      actionType: 'place_step',
      actionData: {'position': 0, 'step_id': 'wake'},
      contentPackId: null,
      routineId: 'morning-routine',
    ),
    (
      gameType: 'number_recall',
      pathSuffix: '/games/recall/board',
      actionType: 'recall_tap',
      actionData: {'position': 0, 'digit': 7},
      contentPackId: null,
      routineId: null,
    ),
  ]) {
    test(
        'offline ${fixture.gameType} replay binds its server board before actions',
        () async {
      final transport = _Transport();
      _installTransport(transport);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final sync = OfflineSyncService(
        db: db,
        api: ApiService(baseUrl: 'http://integrity.test'),
      );
      await db.enqueueSyncItem(SyncQueueItem(
        id: 'queued-${fixture.gameType}',
        patientId: 'patient-profile',
        resourceType: 'game_session',
        operation: 'create',
        resourceId: 'offline-${fixture.gameType}',
        payload: {
          'game_type': fixture.gameType,
          'difficulty_level': 1,
          'patient_id': 'patient-profile',
          'content_pack_id': fixture.contentPackId,
          'routine_id': fixture.routineId,
          'started_at': '2026-09-25T10:00:00.000Z',
          'completed_at': '2026-09-25T10:01:00.000Z',
          'idempotency_key': 'queue-${fixture.gameType}',
          'actions': [
            GameAction(
              id: 'client-action-1',
              sessionId: 'offline-${fixture.gameType}',
              actionType: fixture.actionType,
              actionData: fixture.actionData,
              isCorrect: false,
              timestamp: DateTime.utc(2026, 9, 25, 10),
            ).toJson(),
          ],
        },
        createdAt: DateTime.utc(2026, 9, 25, 10, 2),
      ));

      expect(await sync.syncNow(), 1);
      expect(transport.boards, hasLength(1));
      expect(transport.boards.single.uri.path, endsWith(fixture.pathSuffix));
      expect(transport.boards.single.uri.queryParameters['session_id'],
          'session-1');
      expect(transport.actions, hasLength(1));
      expect(transport.actions.single.containsKey('is_correct'), isFalse);
      final completion = transport.completions.single;
      final actionKey = transport.actions.single['idempotency_key'];
      expect(actionKey, isA<String>());
      expect(completion['expected_action_ids'], [actionKey]);
    });
  }

  for (final shadowProbability in const [0.0, 1.0]) {
    testWidgets(
        'Recall uses only recommended_level when shadow probability is $shadowProbability',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final transport = _Transport()
        ..recommendedLevel = 3
        ..shadowProbability = shadowProbability;
      _installTransport(transport);
      await tester.pumpWidget(const MaterialApp(
        home: RecallScreen(patientId: 'patient-profile', initialDifficulty: 1),
      ));
      addTearDown(() => _disposeScreen(tester));
      await tester.pumpAndSettle();

      await tester.tap(find.text('START ▸'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('7'));
      await tester.pumpAndSettle();

      expect(find.text('Game completed'), findsOneWidget);
      await tester.tap(find.text('Play Again'));
      await tester.pumpAndSettle();

      expect(transport.starts, hasLength(2));
      expect(transport.starts.first['difficulty_level'], 1);
      expect(transport.starts.last['difficulty_level'], 3);
    });
  }

  testWidgets(
      'Odd One Out hides pre-play answer data and shows completion explanation',
      (tester) async {
    final transport = _Transport()
      ..recommendedLevel = 1
      ..explanation = 'Only the completion explanation is safe.';
    _installTransport(transport);
    await tester.pumpWidget(const MaterialApp(
      home: OddOneOutScreen(patientId: 'patient-profile', initialDifficulty: 1),
    ));
    addTearDown(() => _disposeScreen(tester));
    await tester.pumpAndSettle();
    await tester.tap(find.text('START ▸'));
    await tester.pump();

    expect(find.text('Pre-play secret explanation.'), findsNothing);
    expect(find.text('secret_answer_id'), findsNothing);

    await tester.tap(find.text('Odd Item'));
    await tester.pumpAndSettle();

    expect(find.text('Pre-play secret explanation.'), findsNothing);
    expect(
        find.text('Only the completion explanation is safe.'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('smriti_ooo_board_v2');
    expect(cached, isNotNull);
    expect(cached, isNot(contains('answer_item_id')));
    expect(cached, isNot(contains('explanation')));
  });

  testWidgets('Odd One Out invalidates the pre-secrecy board cache',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'smriti_ooo_board_v1': jsonEncode({
        '1': {
          'game_type': 'odd_one_out',
          'difficulty_level': 1,
          'items': [
            {'item_id': 'old_answer', 'name': 'Old leaked answer'},
          ],
          'item_count': 1,
          'target_seconds': 45,
          'group_label': 'Old group',
          'answer_item_id': 'old_answer',
          'explanation': 'Old leaked explanation.',
        },
      }),
    });
    final transport = _Transport();
    HttpOverrides.global = null;
    final failingTransport = _Transport();
    final original = transport;
    _installTransport(failingTransport);
    original.requests.clear();
    HttpOverrides.global = _HttpOverrides(_SessionFailTransport(transport));
    addTearDown(() => HttpOverrides.global = null);
    await tester.pumpWidget(const MaterialApp(
      home: OddOneOutScreen(patientId: 'patient-profile', initialDifficulty: 1),
    ));
    addTearDown(() => _disposeScreen(tester));
    await tester.pumpAndSettle();

    expect(find.text('Connect to download to play'), findsOneWidget);
    expect(find.text('Old leaked answer'), findsNothing);
    expect(find.text('Old leaked explanation.'), findsNothing);
  });

  testWidgets(
      'Match It threads patient profile and pack into session and queue',
      (tester) async {
    final transport = _Transport()..failGameBoards = true;
    _installTransport(transport);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final sync = OfflineSyncService(
      db: db,
      api: ApiService(baseUrl: 'http://integrity.test'),
    );
    await tester.pumpWidget(MaterialApp(
      home: PackPickerScreen(
        patientId: 'patient-profile',
        sync: sync,
      ),
    ));
    addTearDown(() => _disposeScreen(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NER Festivals'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Card 1'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Card 2'));
    await tester.pumpAndSettle();

    expect(transport.starts, hasLength(1));
    expect(transport.starts.single['patient_id'], 'patient-profile');
    expect(transport.starts.single['content_pack_id'], 'festivals_ner');
    final pending = await db.pendingSyncItems();
    final queued = pending.firstWhere(
      (item) => item.payload['game_type'] == 'match_it',
    );
    expect(queued.patientId, 'patient-profile');
    expect(queued.payload['patient_id'], 'patient-profile');
    expect(queued.payload['content_pack_id'], 'festivals_ner');
  });

  testWidgets('Routine threads patient profile and selected routine into queue',
      (tester) async {
    final transport = _Transport()..failGameBoards = true;
    _installTransport(transport);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final sync = OfflineSyncService(
      db: db,
      api: ApiService(baseUrl: 'http://integrity.test'),
    );
    await tester.pumpWidget(MaterialApp(
      home: RoutineScreen(
        patientId: 'patient-profile',
        difficultyLevel: 1,
        routineId: 'morning-routine',
        sync: sync,
      ),
    ));
    addTearDown(() => _disposeScreen(tester));
    await tester.pumpAndSettle();

    for (final label in const ['Wake up', 'Brush teeth', 'Morning Bihu Tea']) {
      final finder = find.text(label);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(transport.starts, hasLength(1));
    expect(transport.starts.single['patient_id'], 'patient-profile');
    expect(transport.starts.single['routine_id'], 'morning-routine');
    final pending = await db.pendingSyncItems();
    final queued = pending.firstWhere(
      (item) => item.payload['game_type'] == 'routine_sequencing',
    );
    expect(queued.patientId, 'patient-profile');
    expect(queued.payload['patient_id'], 'patient-profile');
    expect(queued.payload['routine_id'], 'morning-routine');
  });
}

class _SessionFailTransport extends _Transport {
  _SessionFailTransport(this.inner);

  final _Transport inner;

  @override
  Future<_Reply> _handle(_Request request) async {
    if (request.method == 'POST' &&
        request.uri.path.endsWith('/games/sessions')) {
      inner.requests.add(request);
      return _Reply(500, {'detail': 'offline'});
    }
    return super._handle(request);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:eldercare_mobile/database/app_database.dart';
import 'package:eldercare_mobile/models/game_models.dart';
import 'package:eldercare_mobile/models/shared_models.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:eldercare_mobile/services/auth_session.dart';
import 'package:eldercare_mobile/services/offline_sync_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.url,
    required this.body,
  });

  final String method;
  final Uri url;
  final String body;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

class _Transport {
  bool failFirstComplete = false;
  bool failSync = false;

  /// Server answers 422 for a sync item it cannot materialize.
  bool rejectSyncUnprocessable = false;

  final List<_CapturedRequest> requests = [];
  final Map<String, String> sessionsByKey = {};
  final Set<String> actionKeys = {};
  final Set<String> completedSessions = {};
  int _sessionCounter = 0;
  int completeCalls = 0;

  List<Map<String, dynamic>> get startBodies => requests
      .where((request) =>
          request.method == 'POST' &&
          request.url.path.endsWith('/games/sessions'))
      .map((request) => request.json)
      .toList();

  List<Map<String, dynamic>> get actionBodies => requests
      .where((request) =>
          request.method == 'POST' && request.url.path.endsWith('/actions'))
      .map((request) => request.json)
      .toList();

  _StubResponse handle(_CapturedRequest request) {
    final path = request.url.path;
    if (request.method == 'GET' && path.endsWith('/language/status')) {
      return _StubResponse.json(200, {'status': 'ok'});
    }
    if (request.method == 'POST' && path.endsWith('/auth/logout')) {
      return _StubResponse.json(200, {});
    }
    if (request.method == 'POST' && path.endsWith('/games/sessions')) {
      final body = request.json;
      final key = body['idempotency_key'] as String?;
      final existing = key == null ? null : sessionsByKey[key];
      final sessionId = existing ?? 'server-session-${++_sessionCounter}';
      if (existing == null && key != null) sessionsByKey[key] = sessionId;
      return _StubResponse.json(200, {
        'session_id': sessionId,
        'started_at': body['started_at'] ?? '2026-09-22T10:00:00.000Z',
      });
    }
    if (request.method == 'GET' && path.endsWith('/odd-one-out/board')) {
      return _StubResponse.json(200, {'board': 'fresh'});
    }
    if (request.method == 'GET' &&
        path.contains('/content-packs/') &&
        path.endsWith('/board')) {
      return _StubResponse.json(200, {
        'pack_id': 'festivals_ner',
        'pack_name': 'Festivals',
        'difficulty_level': 1,
        'pair_count': 1,
        'total_cards': 2,
        'cards': [
          {
            'card_id': 1,
            'item_id': 'bihu',
            'name_en': 'Bihu',
            'name_as': 'Bihu',
          },
          {
            'card_id': 2,
            'item_id': 'bihu',
            'name_en': 'Bihu',
            'name_as': 'Bihu',
          },
        ],
      });
    }
    if (request.method == 'POST' && path.endsWith('/actions')) {
      final body = request.json;
      final key = body['idempotency_key'] as String?;
      final sessionId = request.url.path
          .split('/')
          .elementAt(request.url.pathSegments.length - 2);
      final effectiveKey = key == null ? null : '$sessionId:$key';
      if (effectiveKey == null || actionKeys.add(effectiveKey)) {
        actionKeys.add('applied:$sessionId');
      }
      return _StubResponse.json(200, {
        'status': 'recorded',
        'event': {
          'timestamp': '2026-09-22T10:00:05.000Z',
          'action_type': body['action_type'],
          'action_data': body['action_data'],
          'is_correct': body['is_correct'],
          'response_time_ms': body['response_time_ms'],
        },
      });
    }
    if (request.method == 'POST' && path.endsWith('/complete')) {
      completeCalls++;
      final sessionId =
          request.url.pathSegments[request.url.pathSegments.length - 2];
      final body = request.body.isEmpty ? <String, dynamic>{} : request.json;
      completedSessions.add(sessionId);
      if (failFirstComplete && completeCalls == 1) {
        return _StubResponse.json(
            500, {'detail': 'response lost after commit'});
      }
      final response = _StubResponse.json(200, {
        'session_id': sessionId,
        'game_type': 'match_it',
        'difficulty_level': body['difficulty_level'] ?? 1,
        'total_attempts': 1,
        'correct_count': 1,
        'incorrect_count': 0,
        'accuracy_pct': 100.0,
        'avg_response_time_ms': 500.0,
        'started_at': body['started_at'] ?? '2026-09-22T10:00:00.000Z',
        'completed_at': body['completed_at'] ?? '2026-09-22T10:01:00.000Z',
      });
      return response;
    }
    if (request.method == 'POST' && path.endsWith('/sync')) {
      if (failSync) {
        return _StubResponse.json(500, {'detail': 'sync unavailable'});
      }
      if (rejectSyncUnprocessable) {
        return _StubResponse.json(422, {
          'detail': 'Unsupported sync resource_type/operation: '
              'offline_symptom/create',
        });
      }
      return _StubResponse.json(200, {
        'patient_id': 'patient-a',
        'synced': 1,
        'errors': <dynamic>[],
      });
    }
    return _StubResponse.json(404, {'detail': 'unhandled test path $path'});
  }
}

class _StubHttp extends HttpOverrides {
  _StubHttp(this.transport);

  final _Transport transport;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _StubClient(transport);
}

class _StubClient extends Fake implements HttpClient {
  _StubClient(this.transport);

  final _Transport transport;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _StubRequest(transport, method, url);

  @override
  void close({bool force = false}) {}
}

class _StubRequest extends Fake implements HttpClientRequest {
  _StubRequest(this.transport, this.httpMethod, this.url);

  final _Transport transport;
  final String httpMethod;
  final Uri url;
  final List<int> _body = <int>[];
  final _StubHeaders _headers = _StubHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 20;

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  void write(Object? obj) {
    if (obj is String) _body.addAll(utf8.encode(obj));
  }

  @override
  void add(List<int> data) => _body.addAll(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      _body.addAll(data);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final request = _CapturedRequest(
      method: httpMethod,
      url: url,
      body: utf8.decode(_body),
    );
    transport.requests.add(request);
    return transport.handle(request);
  }
}

class _StubHeaders extends Fake implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
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

class _StubResponse extends Fake implements HttpClientResponse {
  _StubResponse(this.status, this._body);

  factory _StubResponse.json(int status, Map<String, dynamic> body) =>
      _StubResponse(status, utf8.encode(jsonEncode(body)));

  final int status;
  final List<int> _body;

  @override
  int get statusCode => status;

  @override
  int get contentLength => _body.length;

  @override
  HttpHeaders get headers {
    final headers = _StubHeaders();
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
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.value(_body).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class _Fixture {
  _Fixture(this.db, this.api, this.sync, this.transport);

  final AppDatabase db;
  final ApiService api;
  final OfflineSyncService sync;
  final _Transport transport;
}

Future<_Fixture> _fixture(_Transport transport) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final api = ApiService(baseUrl: 'http://offline-sync.test');
  final sync = OfflineSyncService(db: db, api: api);
  await _setAccount(sync, 'user-a');
  return _Fixture(db, api, sync, transport);
}

Future<void> _setAccount(OfflineSyncService sync, String accountId) async {
  try {
    final result = (sync as dynamic).setActiveAccount(accountId);
    if (result is Future) await result;
  } on NoSuchMethodError {
    return;
  }
}

SyncQueueItem _gameItem({
  required String id,
  String accountId = 'user-a',
  String gameType = 'match_it',
  String patientId = 'patient-original',
  int difficulty = 2,
  String? contentPackId = 'festivals_ner',
  String? routineId,
  DateTime? startedAt,
  DateTime? completedAt,
  List<GameAction>? actions,
  String? idempotencyKey,
}) {
  final start = startedAt ?? DateTime.utc(2026, 9, 22, 10);
  final complete = completedAt ?? DateTime.utc(2026, 9, 22, 10, 1);
  final action = actions ??
      [
        GameAction(
          id: 'action-1',
          sessionId: 'offline-1',
          actionType: 'flip_card',
          actionData: {'card_id': 1},
          isCorrect: true,
          responseTimeMs: 500,
          timestamp: DateTime.utc(2026, 9, 22, 10, 0, 5),
        ),
      ];
  return SyncQueueItem(
    id: id,
    patientId: patientId,
    resourceType: 'game_session',
    operation: 'create',
    resourceId: 'offline-1',
    payload: {
      'account_id': accountId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      'game_type': gameType,
      'difficulty_level': difficulty,
      'patient_id': patientId,
      'content_pack_id': contentPackId,
      'routine_id': routineId,
      'started_at': start.toIso8601String(),
      'completed_at': complete.toIso8601String(),
      'actions': action.map((value) => value.toJson()).toList(),
    },
    createdAt: DateTime.utc(2026, 9, 22, 10, 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late _Transport transport;

  setUp(() {
    transport = _Transport();
    HttpOverrides.global = _StubHttp(transport);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  test('replaying one queued item twice uses one server session and action set',
      () async {
    final fixture = await _fixture(transport);
    transport.failFirstComplete = true;
    await fixture.db.enqueueSyncItem(
        _gameItem(id: 'game-item', idempotencyKey: 'client-key-1'));

    expect(await fixture.sync.syncNow(), 0);
    final pendingAfterTimeout = await fixture.db.pendingSyncItems();
    expect(pendingAfterTimeout, hasLength(1));
    expect(
        pendingAfterTimeout.single.payload['idempotency_key'], 'client-key-1');

    expect(await fixture.sync.syncNow(), 1);
    final starts = transport.startBodies;
    expect(starts, hasLength(2));
    expect(starts[0]['idempotency_key'], starts[1]['idempotency_key']);
    expect(transport.sessionsByKey.values.toSet(), hasLength(1));
    expect(transport.actionKeys.where((key) => key.startsWith('applied:')),
        hasLength(1));
    expect(await fixture.db.pendingSyncItems(), isEmpty);
  });

  test(
      'replay preserves the original patient, timestamps, pack, routine and difficulty',
      () async {
    final fixture = await _fixture(transport);
    final started = DateTime.utc(2026, 9, 21, 8, 30);
    final completed = DateTime.utc(2026, 9, 21, 8, 45);
    await fixture.db.enqueueSyncItem(_gameItem(
      id: 'metadata-item',
      accountId: 'user-a',
      patientId: 'patient-original',
      startedAt: started,
      completedAt: completed,
      contentPackId: 'festivals_ner',
      routineId: 'morning-routine',
      difficulty: 3,
    ));

    expect(await fixture.sync.syncNow(), 1);
    final body = transport.startBodies.single;
    expect(body['patient_id'], 'patient-original');
    expect(body['started_at'], started.toIso8601String());
    expect(body['completed_at'], completed.toIso8601String());
    expect(body['content_pack_id'], 'festivals_ner');
    expect(body['routine_id'], 'morning-routine');
    expect(body['difficulty_level'], 3);
  });

  test(
      'logout account replay skips another account but drains the same account',
      () async {
    final fixture = await _fixture(transport);
    await _setAccount(fixture.sync, 'user-b');
    await fixture.db
        .enqueueSyncItem(_gameItem(id: 'old-account', accountId: 'user-a'));
    await fixture.db
        .enqueueSyncItem(_gameItem(id: 'new-account', accountId: 'user-b'));

    expect(await fixture.sync.syncNow(), 1);
    expect(transport.startBodies, hasLength(1));
    expect(transport.startBodies.single['patient_id'], 'patient-original');
    final pending = await fixture.db.pendingSyncItems();
    expect(pending.map((item) => item.id), contains('old-account'));
    expect(pending.map((item) => item.id), isNot(contains('new-account')));
  });

  test('logout stops the sync timer and prevents later probes', () async {
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            pathProviderChannel, (_) async => Directory.systemTemp.path);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      OfflineSyncService.instance.stop();
    });
    SharedPreferences.setMockInitialValues({});
    await AuthSession.instance.restore();
    final service = OfflineSyncService.instance;
    service.stop();
    service.start(interval: const Duration(milliseconds: 15));
    await Future<void>.delayed(const Duration(milliseconds: 35));
    final beforeLogout = transport.requests.length;

    await AuthSession.instance.logout();
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final afterLogout = transport.requests.skip(beforeLogout).toList();
    expect(afterLogout, hasLength(1));
    expect(afterLogout.single.url.path, endsWith('/auth/logout'));
    service.stop();
  });

  test(
      'server failure keeps the item queued and exposes a visible failure state',
      () async {
    final fixture = await _fixture(transport);
    transport.failSync = true;
    await fixture.db.enqueueSyncItem(SyncQueueItem(
      id: 'unsupported-item',
      patientId: 'patient-original',
      resourceType: 'unsupported_resource',
      operation: 'create',
      resourceId: 'unsupported-resource',
      payload: {'account_id': 'user-a'},
      createdAt: DateTime.utc(2026, 9, 22, 10),
    ));
    await fixture.db.enqueueSyncItem(SyncQueueItem(
      id: 'failed-item',
      patientId: 'patient-original',
      resourceType: 'offline_symptom',
      operation: 'create',
      resourceId: '00000000-0000-4000-8000-000000000001',
      payload: {
        'account_id': 'user-a',
        'entered_by': 'user-a',
        'source': 'manual_patient',
        'severity': 2,
        'notes': 'queued note',
        'recorded_at': '2026-09-22T10:00:00.000Z',
      },
      createdAt: DateTime.utc(2026, 9, 22, 10, 1),
    ));

    expect(await fixture.sync.syncNow(), 0);
    final pending = await fixture.db.pendingSyncItems();
    expect(pending, hasLength(2));
    final unsupported =
        pending.firstWhere((item) => item.id == 'unsupported-item');
    expect(unsupported.lastError, contains('cannot be materialized'));
    final failed = pending.firstWhere((item) => item.id == 'failed-item');
    expect(failed.lastError, isNotNull);
    final visibleFailure = (fixture.sync as dynamic).lastFailure;
    expect(visibleFailure, isNotNull);
    expect('$visibleFailure', contains('sync'));
  });

  test('a 422 sync rejection is not falsely acknowledged', () async {
    final fixture = await _fixture(transport);
    transport.rejectSyncUnprocessable = true;
    await fixture.db.enqueueSyncItem(SyncQueueItem(
      id: 'rejected-item',
      patientId: 'patient-original',
      resourceType: 'offline_symptom',
      operation: 'create',
      resourceId: '00000000-0000-4000-8000-0000000000aa',
      payload: {
        'account_id': 'user-a',
        'entered_by': 'user-a',
        'notes': 'chest pain',
      },
      createdAt: DateTime.utc(2026, 9, 25, 9),
    ));

    // Nothing is reported as synced.
    expect(await fixture.sync.syncNow(), 0);

    // The item is still queued, unsynced, and carries a visible reason.
    final pending = await fixture.db.pendingSyncItems();
    final rejected = pending.firstWhere((item) => item.id == 'rejected-item');
    // A pending item is by definition unsynced; the failure must be visible.
    expect(rejected.lastError, isNotNull);
    expect('${rejected.lastError}'.toLowerCase(),
        anyOf(contains('422'), contains('unprocessable'), contains('resource_type')));
  });

  test('a legitimate offline game session still syncs end to end', () async {
    final fixture = await _fixture(transport);
    final session = GameSessionModel(
      id: 'offline-legitimate',
      patientId: 'patient-original',
      gameType: GameType.matchIt,
      difficultyLevel: 1,
      attempts: 1,
      correctCount: 1,
      incorrectCount: 0,
      avgResponseTimeMs: 500,
      startedAt: DateTime.utc(2026, 9, 22, 11),
      completedAt: DateTime.utc(2026, 9, 22, 11, 1),
    );
    await fixture.sync.enqueueGameSession(
      patientId: 'patient-original',
      session: session,
      contentPackId: 'festivals_ner',
      actions: [
        GameAction(
          id: 'legit-action',
          sessionId: 'offline-legitimate',
          actionType: 'flip_card',
          actionData: {'card_id': 1},
          isCorrect: true,
          responseTimeMs: 500,
          timestamp: DateTime.utc(2026, 9, 22, 11, 0, 5),
        ),
      ],
    );

    final queued = await fixture.db.pendingSyncItems();
    expect(queued.single.idempotencyKey, matches(_uuidV4));
    final synced = await fixture.sync.syncNow();
    final pending = await fixture.db.pendingSyncItems();
    expect(synced, 1);
    expect(pending, isEmpty);
    expect(transport.startBodies, hasLength(1));
    expect(transport.actionBodies, hasLength(1));
    expect(transport.completedSessions, hasLength(1));
  });
}

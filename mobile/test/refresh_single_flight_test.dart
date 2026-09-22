// Wave 5D — single-flight refresh: parallel 401s share one refresh; the
// rotated token is never re-used by a second racing refresh. Runs the REAL
// ApiService against a fake HTTP transport (HttpOverrides) — same pattern as
// schedule_delete_contract_test.dart. No live server, no new dependencies.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eldercare_mobile/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Handler = ({int status, Object? json}) Function(
    String method, Uri uri, String body);

class _FakeBackend extends HttpOverrides {
  _FakeBackend(this.handler);

  final _Handler handler;
  final List<({String method, Uri uri, String body})> requests = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeClient(this);
}

class _FakeClient extends Fake implements HttpClient {
  _FakeClient(this.backend);

  final _FakeBackend backend;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(backend, method, url);

  @override
  void close({bool force = false}) {}
}

class _FakeRequest extends Fake implements HttpClientRequest {
  _FakeRequest(this.backend, this.method, this.uri);

  final _FakeBackend backend;

  @override
  final String method;

  @override
  final Uri uri;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  final StringBuffer _body = StringBuffer();

  @override
  void write(Object? obj) => _body.write(obj);

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
    final body = _body.toString();
    backend.requests.add((method: method, uri: uri, body: body));
    final res = backend.handler(method, uri, body);
    return _FakeResponse(res.status, res.json);
  }
}

class _FakeHeaders extends Fake implements HttpHeaders {
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
    final v = _values[name.toLowerCase()];
    return v == null || v.isEmpty ? null : v.join(',');
  }

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, Object? jsonBody)
      : _bytes = utf8.encode(jsonBody == null ? '' : jsonEncode(jsonBody));

  @override
  final int statusCode;

  final List<int> _bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.value(_bytes).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  int get contentLength => _bytes.length;

  @override
  HttpHeaders get headers {
    final h = _FakeHeaders();
    h.set('content-type', 'application/json');
    return h;
  }

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';

  @override
  List<Cookie> get cookies => const [];

  @override
  List<RedirectInfo> get redirects => const [];
}

void main() {
  test('parallel 401s share one in-flight refresh', () async {
    var refreshCount = 0;
    // Odd data attempts per path return 401 (expired token); even attempts
    // (post-refresh retries) return 200.
    final attempts = <String, int>{};
    final backend = _FakeBackend((method, uri, body) {
      if (uri.path.endsWith('/auth/refresh')) {
        refreshCount++;
        return (
          status: 200,
          json: {
            'access_token': 'a$refreshCount',
            'refresh_token': 'r$refreshCount',
            'token_type': 'bearer'
          },
        );
      }
      final n = (attempts[uri.path] ?? 0) + 1;
      attempts[uri.path] = n;
      return n.isOdd
          ? (status: 401, json: {'detail': 'expired'})
          : (status: 200, json: {'ok': true});
    });
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    final api = ApiService(
      baseUrl: 'http://fake.invalid',
      authToken: 'expired',
      refreshToken: 'r0',
    );

    // Three concurrent requests all hit 401 and all need a refresh; the
    // shared future must coalesce them into ONE refresh call.
    await Future.wait([
      api.getJson('/api/v1/patients/me'),
      api.getJson('/api/v1/games/level-config'),
      api.getJson('/api/v1/dashboard/caregivers/x/patients'),
    ]);
    expect(refreshCount, 1,
        reason: 'parallel 401s must share a single in-flight refresh');
    expect(api.authToken, 'a1');
    expect(api.refreshToken, 'r1');
  });

  test('sequential 401s after a settled refresh refresh again', () async {
    var refreshCount = 0;
    final attempts = <String, int>{};
    final backend = _FakeBackend((method, uri, body) {
      if (uri.path.endsWith('/auth/refresh')) {
        refreshCount++;
        return (
          status: 200,
          json: {
            'access_token': 'a$refreshCount',
            'refresh_token': 'r$refreshCount',
            'token_type': 'bearer'
          },
        );
      }
      final n = (attempts[uri.path] ?? 0) + 1;
      attempts[uri.path] = n;
      return n.isOdd
          ? (status: 401, json: {'detail': 'expired'})
          : (status: 200, json: {'ok': true});
    });
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    final api = ApiService(
      baseUrl: 'http://fake.invalid',
      authToken: 'expired',
      refreshToken: 'r0',
    );

    await api.getJson('/api/v1/patients/me');
    expect(refreshCount, 1);
    // A later 401 (odd attempt again) refreshes once more.
    await api.getJson('/api/v1/patients/me');
    expect(refreshCount, 2,
        reason: 'a settled refresh must not block a later one');
  });

  test('failed refresh clears the in-flight slot', () async {
    var failRefreshes = true;
    final attempts = <String, int>{};
    final backend = _FakeBackend((method, uri, body) {
      if (uri.path.endsWith('/auth/refresh')) {
        if (failRefreshes) return (status: 401, json: {'detail': 'bad'});
        return (
          status: 200,
          json: {
            'access_token': 'ok',
            'refresh_token': 'ok2',
            'token_type': 'bearer'
          },
        );
      }
      final n = (attempts[uri.path] ?? 0) + 1;
      attempts[uri.path] = n;
      return n.isOdd
          ? (status: 401, json: {'detail': 'expired'})
          : (status: 200, json: {'ok': true});
    });
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    final api = ApiService(
      baseUrl: 'http://fake.invalid',
      authToken: 'expired',
      refreshToken: 'r0',
    );

    // Refresh failed -> the original request surfaces its 401 as an error.
    await expectLater(
      api.getJson('/api/v1/patients/me'),
      throwsA(isA<ApiException>()),
    );
    // The in-flight slot is cleared: a later odd attempt (now succeeding)
    // refreshes and retries instead of replaying a poisoned future.
    failRefreshes = false;
    await api.getJson('/api/v1/patients/me'); // even attempt: straight 200
    await api.getJson('/api/v1/patients/me'); // odd attempt: 401 -> refresh
    expect(api.authToken, 'ok');
  });
}

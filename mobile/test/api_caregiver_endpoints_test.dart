/// Task 1 (caregiver-dashboard-mobile-port): ApiService.uploadDocument +
/// submitRiskScreening contract tests. Fake-HTTP scaffold copied verbatim
/// from rag_upload_test.dart lines 19–167.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eldercare_mobile/screens/rag_upload_screen.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Handler = ({int status, Object? json}) Function(
    String method, Uri uri, String body);

class _FakeBackend extends HttpOverrides {
  _FakeBackend(this.handler);

  final _Handler handler;
  final List<({String method, Uri uri, Map<String, String> headers})>
      requests = [];

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
    final snap = <String, String>{};
    headers.forEach(
        (name, values) => snap[name.toLowerCase()] = values.join(','));
    backend.requests.add((method: method, uri: uri, headers: snap));
    final res = backend.handler(method, uri, _body.toString());
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
  group('uploadDocument', () {
    test('multipart POST to upload path with query+field patient_id, auth header', () async {
      final backend = _FakeBackend((method, uri, body) {
        expect(method, 'POST');
        expect(uri.path, '/api/v1/reports/documents/upload');
        expect(uri.queryParameters['patient_id'], 'p1');
        expect(body, contains('name="patient_id"'));
        expect(body, contains('name="file"'));
        expect(body, contains('name="doc_type"'));
        return (status: 200, json: {'document_id': 'd1'});
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')..authToken = 'tok-1';
      final data = await api.uploadDocument(
        patientId: 'p1',
        bytes: Uint8List.fromList(utf8.encode('hi')),
        filename: 'note.pdf',
      );
      expect(data['document_id'], 'd1');
    });

    test('403 consent detail surfaces via ApiException (no silence)', () async {
      final backend = _FakeBackend((method, uri, body) => (
        status: 403,
        json: {'detail': "Active consent required for scope 'health_data'"},
      ));
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')..authToken = 'tok-1';
      await expectLater(
        api.uploadDocument(patientId: 'p1', bytes: Uint8List.fromList([1]), filename: 'a.pdf'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', contains('health_data'))),
      );
    });

    test('401 then refresh then retry with new Authorization header', () async {
      var uploadHits = 0;
      final backend = _FakeBackend((method, uri, body) {
        if (uri.path.endsWith('/reports/documents/upload')) {
          uploadHits++;
          return uploadHits == 1
              ? (status: 401, json: {'detail': 'token expired'})
              : (status: 200, json: {'document_id': 'd2'});
        }
        if (uri.path.endsWith('/auth/refresh')) {
          return (
            status: 200,
            json: {'access_token': 'new', 'refresh_token': 'r2'},
          );
        }
        return (status: 404, json: {'detail': 'no'});
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')
        ..authToken = 'old'
        ..refreshToken = 'r1';
      final data = await api.uploadDocument(
        patientId: 'p1',
        bytes: Uint8List.fromList(utf8.encode('hi')),
        filename: 'note.pdf',
      );
      expect(data['document_id'], 'd2');
      expect(uploadHits, 2);
      expect(api.authToken, 'new');
      final uploadAuths = backend.requests
          .where((r) => r.uri.path.endsWith('/reports/documents/upload'))
          .map((r) => r.headers['authorization'])
          .toList();
      expect(uploadAuths, ['Bearer old', 'Bearer new'],
          reason: 'retry must carry the refreshed Authorization header');
    });
  });

  group('submitRiskScreening', () {
    test('POSTs payload to /patients/{id}/risk-screening and returns result', () async {
      final backend = _FakeBackend((method, uri, body) {
        expect(method, 'POST');
        expect(uri.path, '/api/v1/patients/p1/risk-screening');
        expect(jsonDecode(body), containsPair('Age', 72));
        return (status: 200, json: {'status': 'ok', 'risk_score': 41, 'tier': 'moderate_risk'});
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')..authToken = 'tok-1';
      final result = await api.submitRiskScreening(patientId: 'p1', payload: {'Age': 72});
      expect(result['tier'], 'moderate_risk');
    });

    test('401 then refresh then retry (single-flight path reused)', () async {
      var screeningHits = 0;
      final backend = _FakeBackend((method, uri, body) {
        if (uri.path.endsWith('/risk-screening')) {
          screeningHits++;
          // first hit: 401; after refresh: 200
          return screeningHits == 1
              ? (status: 401, json: {'detail': 'token expired'})
              : (status: 200, json: {'status': 'ok', 'risk_score': 10});
        }
        if (uri.path.endsWith('/auth/refresh')) {
          return (status: 200, json: {'access_token': 'new', 'refresh_token': 'r2'});
        }
        return (status: 404, json: {'detail': 'no'});
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')
        ..authToken = 'old'
        ..refreshToken = 'r1';
      final result = await api.submitRiskScreening(patientId: 'p1', payload: {'Age': 60});
      expect(result['status'], 'ok');
      expect(api.authToken, 'new');
    });

    test('empty 2xx body returns {} without throwing', () async {
      final backend = _FakeBackend((method, uri, body) => (
        status: 200,
        json: null, // encodes to empty body ('')
      ));
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      final api = ApiService(baseUrl: 'http://fake.invalid')..authToken = 'tok-1';
      final result = await api.submitRiskScreening(patientId: 'p1', payload: {'Age': 72});
      expect(result, <String, dynamic>{});
    });
  });

  group('RagUploadScreen live (non-sendForTest) path', () {
    testWidgets('401 → ApiService refresh → retry succeeds (no raw send)',
        (tester) async {
      var uploadHits = 0;
      var refreshHits = 0;
      final backend = _FakeBackend((method, uri, body) {
        if (uri.path.endsWith('/reports/documents/upload')) {
          uploadHits++;
          return uploadHits == 1
              ? (status: 401, json: {'detail': 'token expired'})
              : (status: 200, json: {'document_id': 'd2'});
        }
        if (uri.path.endsWith('/auth/refresh')) {
          refreshHits++;
          return (
            status: 200,
            json: {'access_token': 'new', 'refresh_token': 'r2'},
          );
        }
        return (status: 404, json: {'detail': 'no'});
      });
      HttpOverrides.global = backend;
      addTearDown(() => HttpOverrides.global = null);
      ApiService.instance.authToken = 'old';
      ApiService.instance.refreshToken = 'r1';
      addTearDown(() {
        ApiService.instance.authToken = null;
        ApiService.instance.refreshToken = null;
      });

      await tester.pumpWidget(MaterialApp(
        home: RagUploadScreen(
          patientId: 'p1',
          testBytes: Uint8List.fromList(utf8.encode('hi')),
          testFilename: 'note.pdf',
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UPLOAD ▸'));
      await tester.pumpAndSettle();

      expect(refreshHits, 1,
          reason: 'live upload path must go through ApiService refresh');
      expect(uploadHits, 2);
      expect(ApiService.instance.authToken, 'new');
      expect(find.text('Uploaded successfully (HTTP 200).'), findsOneWidget);
    });
  });
}

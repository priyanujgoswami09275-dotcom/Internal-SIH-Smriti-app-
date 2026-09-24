import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eldercare_mobile/screens/documents_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Handler = ({int status, Object? json}) Function(
    String method, Uri uri, String body);

class _FakeBackend extends HttpOverrides {
  _FakeBackend(this.handler);

  final _Handler handler;

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
  final twoDocs = {
    'documents': [
      {
        'document_id': 'd1',
        'title': 'Discharge summary',
        'file_name': 'discharge.txt',
        'doc_type': 'prescription',
        'embedding_status': 'completed',
        'created_at': '2026-09-24T10:00:00',
      },
      {
        'document_id': 'd2',
        'title': 'Care plan',
        'file_name': 'care.pdf',
        'doc_type': 'report',
        'embedding_status': 'pending',
        'created_at': '2026-09-23T09:00:00',
      },
    ],
    'count': 2,
  };

  testWidgets('lists documents with title, file name and status',
      (tester) async {
    final backend = _FakeBackend((method, uri, body) {
      if (uri.path == '/api/v1/reports/patients/p1/documents') {
        return (status: 200, json: twoDocs);
      }
      return (status: 404, json: {'detail': 'not found'});
    });
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    expect(find.text('Discharge summary'), findsOneWidget);
    expect(find.text('discharge.txt · 24 Sep 2026'), findsOneWidget);
    expect(find.text('prescription · completed'), findsOneWidget);
    expect(find.text('UPLOAD DOCUMENT'), findsOneWidget);
    expect(find.text('ASK ABOUT DOCUMENTS ▸'), findsOneWidget);
  });

  testWidgets('empty list shows the empty state, not an error', (tester) async {
    final backend = _FakeBackend((method, uri, body) =>
        (status: 200, json: {'documents': [], 'count': 0}));
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No documents yet'), findsOneWidget);
  });

  testWidgets('403 clinical tier renders the health-worker lock copy',
      (tester) async {
    var consentFired = false;
    final backend = _FakeBackend((method, uri, body) => (
          status: 403,
          json: {
            'detail': 'Clinical permission tier required for this resource'
          }
        ));
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(MaterialApp(
      home: DocumentsScreen(
        patientId: 'p1',
        onConsentMissing: () => consentFired = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Health worker only'), findsOneWidget);
    expect(consentFired, isFalse);
    expect(find.text('UPLOAD DOCUMENT'), findsNothing);
    expect(find.text('ASK ABOUT DOCUMENTS ▸'), findsNothing);
  });

  testWidgets('403 consent renders the consent copy and fires onConsentMissing',
      (tester) async {
    var consentFired = false;
    final backend = _FakeBackend((method, uri, body) => (
          status: 403,
          json: {'detail': "Active consent required for scope 'health_data'"}
        ));
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester.pumpWidget(MaterialApp(
      home: DocumentsScreen(
        patientId: 'p1',
        onConsentMissing: () => consentFired = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(consentFired, isTrue);
    expect(find.textContaining('health_data consent required'), findsOneWidget);
  });

  testWidgets('offline shows offline notice with retry', (tester) async {
    final backend = _FakeBackend((method, uri, body) =>
        throw const SocketException('Failed host lookup'));
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.text('RETRY ▸'), findsOneWidget);
  });

  testWidgets('retry reloads after a failed request and succeeds',
      (tester) async {
    var listRequests = 0;
    final backend = _FakeBackend((method, uri, body) {
      if (uri.path == '/api/v1/reports/patients/p1/documents') {
        listRequests++;
        if (listRequests == 1) {
          return (status: 500, json: {'detail': 'temporary failure'});
        }
        return (status: 200, json: twoDocs);
      }
      return (status: 404, json: {'detail': 'not found'});
    });
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    expect(listRequests, 1);
    expect(find.text('Could not load documents: temporary failure'),
        findsOneWidget);
    expect(find.text('RETRY ▸'), findsOneWidget);

    await tester.tap(find.text('RETRY ▸'));
    await tester.pumpAndSettle();

    expect(listRequests, 2);
    expect(find.text('Discharge summary'), findsOneWidget);
    expect(find.textContaining('Could not load documents'), findsNothing);
  });

  testWidgets('returning from upload reloads the document list',
      (tester) async {
    var listRequests = 0;
    final backend = _FakeBackend((method, uri, body) {
      if (uri.path == '/api/v1/reports/patients/p1/documents') {
        listRequests++;
        return (status: 200, json: twoDocs);
      }
      return (status: 404, json: {'detail': 'not found'});
    });
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();
    expect(listRequests, 1);

    await tester.tap(find.text('UPLOAD DOCUMENT'));
    await tester.pumpAndSettle();
    expect(
        find.text('Upload prescriptions, discharge summaries, or care plans.'),
        findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(listRequests, 2);
  });

  testWidgets('500 detail shows the server message and Retry', (tester) async {
    final backend = _FakeBackend((method, uri, body) => (
          status: 500,
          json: {'detail': 'server exploded'},
        ));
    HttpOverrides.global = backend;
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: DocumentsScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    expect(
        find.text('Could not load documents: server exploded'), findsOneWidget);
    expect(find.text('RETRY ▸'), findsOneWidget);
  });
}

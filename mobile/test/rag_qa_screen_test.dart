import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eldercare_mobile/screens/rag_qa_screen.dart';
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
  _FakeBackend answerBackend(String answer, List<Map<String, dynamic>> cites) =>
      _FakeBackend((method, uri, body) {
        if (uri.path == '/api/v1/reports/documents/answer') {
          return (
            status: 200,
            json: {
              'question': 'What medication?',
              'answer': answer,
              'synthesized': false,
              'citations': cites,
              'disclaimer':
                  'Not medical advice — consult the treating clinician.',
            }
          );
        }
        return (status: 404, json: {'detail': 'not found'});
      });

  testWidgets('answer renders with numbered citations and disclaimer',
      (tester) async {
    HttpOverrides.global = answerBackend('Donepezil 5 mg at bedtime [1].', [
      {
        'title': 'Discharge summary',
        'file_ref': 'discharge.txt',
        'similarity': 0.82,
      }
    ]);
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: RagQaScreen(patientId: 'p1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'What medication?');
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();

    expect(find.text('Donepezil 5 mg at bedtime [1].'), findsOneWidget);
    expect(
        find.text('[1] Discharge summary · similarity 0.82'), findsOneWidget);
    expect(find.text('Not medical advice — consult the treating clinician.'),
        findsOneWidget);
  });

  testWidgets('"no relevant records" is an answer, not an error',
      (tester) async {
    HttpOverrides.global = answerBackend(
        'No relevant records found for this patient to answer the question.',
        []);
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: RagQaScreen(patientId: 'p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'What medication?');
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();

    expect(
        find.text(
            'No relevant records found for this patient to answer the question.'),
        findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    expect(find.textContaining('Could not get an answer:'), findsNothing);
  });

  testWidgets('empty question is refused client-side', (tester) async {
    var called = false;
    HttpOverrides.global = _FakeBackend((method, uri, body) {
      called = true;
      return (status: 200, json: {'answer': 'x', 'citations': []});
    });
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: RagQaScreen(patientId: 'p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Type a question first'), findsOneWidget);
    expect(called, isFalse);
  });

  testWidgets('403 consent surfaces the consent copy', (tester) async {
    HttpOverrides.global = _FakeBackend((method, uri, body) => (
          status: 403,
          json: {'detail': "Active consent required for scope 'health_data'"}
        ));
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: RagQaScreen(patientId: 'p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'What medication?');
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining("scope 'health_data'"), findsOneWidget);
  });

  testWidgets('offline shows the offline copy', (tester) async {
    HttpOverrides.global = _FakeBackend((method, uri, body) =>
        throw const SocketException('Failed host lookup'));
    addTearDown(() => HttpOverrides.global = null);

    await tester
        .pumpWidget(const MaterialApp(home: RagQaScreen(patientId: 'p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'What medication?');
    await tester.tap(find.text('ASK ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
  });
}

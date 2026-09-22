/// Shared fakes for Wave 2B dashboard tests.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Case-insensitive header lookup (package:http preserves sender case).
String? headerOf(http.BaseRequest req, String name) {
  for (final e in req.headers.entries) {
    if (e.key.toLowerCase() == name.toLowerCase()) return e.value;
  }
  return null;
}

http.Response jsonRes(Object? data, int status) => http.Response(
      jsonEncode(data),
      status,
      headers: const {'Content-Type': 'application/json'},
    );

typedef FakeHandler = Future<http.Response> Function(
    http.BaseRequest req, String body);

/// Minimal injectable http client seam driver.
class FakeClient extends http.BaseClient {
  final FakeHandler handler;
  final List<http.BaseRequest> requests = [];

  FakeClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = await request.finalize().bytesToString();
    final res = await handler(request, body);
    return http.StreamedResponse(
      Stream.value(utf8.encode(res.body)),
      res.statusCode,
      headers: res.headers,
    );
  }
}

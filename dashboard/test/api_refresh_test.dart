// Wave 2B task 2.2: delete refresh-retry, server logout, single-flight refresh.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eldercare_dashboard/main.dart';

import 'test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Api.resetForTest();
  });

  tearDown(() {
    Api.resetForTest();
  });

  test('expired-token delete retries once after refresh', () async {
    Api.setTestSession(
        token: 'expired-access', refreshToken: 'valid-refresh', userId: 'cg1');
    Api.testClient = FakeClient((req, body) async {
      if (req.method == 'POST' && req.url.path.endsWith('/auth/refresh')) {
        return jsonRes(
            {'access_token': 'fresh-access', 'refresh_token': 'fresh-refresh'},
            200);
      }
      if (req.method == 'DELETE') {
        if (headerOf(req, 'authorization') == 'Bearer expired-access') {
          return jsonRes({'detail': 'expired'}, 401);
        }
        return jsonRes({'status': 'deleted'}, 200);
      }
      return jsonRes({'detail': 'not found'}, 404);
    });

    await Api.deleteSchedule('sched-1');

    final client = Api.testClient as FakeClient;
    final deletes =
        client.requests.where((r) => r.method == 'DELETE').toList();
    expect(deletes, hasLength(2));
    expect(
        client.requests
            .where((r) => r.url.path.endsWith('/auth/refresh'))
            .length,
        1);
    expect(headerOf(deletes.last, 'authorization'), 'Bearer fresh-access');
  });

  test('logout revokes server-side then clears local state', () async {
    Api.setTestSession(token: 'a', refreshToken: 'r', userId: 'u');
    Api.testClient = FakeClient((req, body) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/api/v1/auth/logout');
      return jsonRes({'status': 'logged_out'}, 200);
    });

    await Api.logout();

    final client = Api.testClient as FakeClient;
    expect(client.requests, hasLength(1));
    final logoutReq = client.requests.single;
    expect(headerOf(logoutReq, 'authorization'), 'Bearer a');
    expect(Api.hasSession, isFalse);
  });

  test('logout request carries the refresh token', () async {
    Api.setTestSession(token: 'a', refreshToken: 'r', userId: 'u');
    String? seenBody;
    Api.testClient = FakeClient((req, body) async {
      seenBody = body;
      return jsonRes({'status': 'logged_out'}, 200);
    });

    await Api.logout();

    expect(jsonDecode(seenBody!)['refresh_token'], 'r');
    expect(Api.hasSession, isFalse);
  });

  test('logout clears local state even when the server errors', () async {
    Api.setTestSession(token: 'a', refreshToken: 'r', userId: 'u');
    Api.testClient = FakeClient(
        (req, body) async => jsonRes({'detail': 'boom'}, 500));

    await Api.logout();

    expect(Api.hasSession, isFalse);
  });

  test('concurrent 401s share one in-flight refresh', () async {
    Api.setTestSession(token: 'old', refreshToken: 'r', userId: 'u');
    var refreshCalls = 0;
    Api.testClient = FakeClient((req, body) async {
      if (req.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        await Future.delayed(const Duration(milliseconds: 50));
        return jsonRes(
            {'access_token': 'new', 'refresh_token': 'r2'}, 200);
      }
      if (headerOf(req, 'authorization') == 'Bearer old') {
        return jsonRes({'detail': 'expired'}, 401);
      }
      return jsonRes({'id': 'u'}, 200);
    });

    final results = await Future.wait(
        [Api.validateSession(), Api.validateSession(), Api.validateSession()]);

    expect(results, [true, true, true]);
    expect(refreshCalls, 1);
    expect(Api.testClient, isA<http.BaseClient>());
  });
}

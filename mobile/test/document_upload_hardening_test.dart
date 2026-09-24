import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eldercare_mobile/screens/rag_upload_screen.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:eldercare_mobile/services/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    throw const SocketException('Connection refused');
  }

  @override
  void close({bool force = false}) {}
}

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

void main() {
  Future<void> seedRole(String role) async {
    SharedPreferences.setMockInitialValues({
      'auth.access': 'test-access',
      'auth.refresh': 'test-refresh',
      'auth.user': jsonEncode({
        'id': 'u1',
        'phone': '+910000000001',
        'role': role,
        'preferred_language': 'english',
      }),
    });
    await AuthSession.instance.restore();
  }

  group('formatDocumentUploadError', () {
    test('network error → offline copy', () {
      expect(
        formatDocumentUploadError(
            ApiException('Network error: SocketException')),
        "You're offline — try again when connected.",
      );
    });

    test('401 → session expired', () {
      expect(
        formatDocumentUploadError(ApiException('nope', statusCode: 401)),
        'Session expired — sign in again.',
      );
    });

    test('413 → size copy', () {
      expect(
        formatDocumentUploadError(
            ApiException('File exceeds the 10 MB limit.', statusCode: 413)),
        contains('10 MB'),
      );
    });

    test('429 → rate-limit copy', () {
      expect(
        formatDocumentUploadError(ApiException('slow down', statusCode: 429)),
        'Rate limit reached — wait a minute and try again.',
      );
    });

    test('403 tier → health-worker copy, no consent claim', () {
      final msg = formatDocumentUploadError(ApiException(
        'Clinical permission tier required for this resource',
        statusCode: 403,
      ));
      expect(msg, contains("can't add health documents"));
      expect(msg, isNot(contains('health_data consent required')));
    });

    test('403 consent keeps the port-locked consent copy', () {
      final msg = formatDocumentUploadError(ApiException(
        "Active consent required for scope 'health_data'",
        statusCode: 403,
      ));
      expect(msg, contains("scope 'health_data'"));
      expect(msg, contains('Upload failed'));
    });

    test('400 → server detail passthrough', () {
      expect(
        formatDocumentUploadError(ApiException(
            "Unsupported file type '.png'. Upload a PDF or text file.",
            statusCode: 400)),
        contains('Unsupported file type'),
      );
    });
  });

  testWidgets('offline live upload shows offline copy and never queues',
      (tester) async {
    final original = ApiService.instance.baseUrl;
    final originalOverrides = HttpOverrides.current;
    HttpOverrides.global = _OfflineHttpOverrides();
    addTearDown(() {
      HttpOverrides.global = originalOverrides;
      expect(ApiService.instance.baseUrl, original);
    });

    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        testBytes: Uint8List.fromList(utf8.encode('hi')),
        testFilename: 'note.txt',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('UPLOAD ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('sendForTest 429 shows the rate-limit copy', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        testBytes: Uint8List.fromList(utf8.encode('hi')),
        testFilename: 'note.txt',
        sendForTest: (req) async => http.Response(
          jsonEncode({'detail': 'rate limit'}),
          429,
          headers: const {'Content-Type': 'application/json'},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UPLOAD ▸'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rate limit reached'), findsOneWidget);
  });

  testWidgets('sendForTest 403 tier shows health-worker copy without consent wording',
      (tester) async {
    var consentFired = false;
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        testBytes: Uint8List.fromList(utf8.encode('hi')),
        testFilename: 'note.txt',
        onConsentMissing: () => consentFired = true,
        sendForTest: (req) async => http.Response(
          jsonEncode({
            'detail': 'Clinical permission tier required for this resource',
          }),
          403,
          headers: const {'Content-Type': 'application/json'},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UPLOAD ▸'));
    await tester.pumpAndSettle();

    expect(find.textContaining("can't add health documents"), findsOneWidget);
    expect(find.textContaining('consent required'), findsNothing);
    expect(consentFired, isFalse);
  });

  for (final role in const ['asha_worker', 'clinician', 'admin']) {
    testWidgets('$role can upload a PDF and a .txt through the same path',
        (tester) async {
      await seedRole(role);
      final sent = <String>[];
      for (final (name, bytes) in [
        ('note.pdf', Uint8List.fromList(utf8.encode('%PDF-1.7 test'))),
        ('note.txt', Uint8List.fromList(utf8.encode('Donepezil 5 mg'))),
      ]) {
        await tester.pumpWidget(MaterialApp(
          home: RagUploadScreen(
            patientId: 'p1',
            testBytes: bytes,
            testFilename: name,
            sendForTest: (req) async {
              sent.add(req.files.single.filename!);
              return http.Response(
                  jsonEncode({'document_id': 'd1', 'chars_extracted': 12}),
                  200);
            },
          ),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('UPLOAD ▸'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Uploaded successfully'), findsOneWidget);
      }
      expect(sent, ['note.pdf', 'note.txt']);
    });
  }
}

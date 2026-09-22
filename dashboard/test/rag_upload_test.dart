// Wave 2C task 2.4-dashboard: RAG upload wired end-to-end.
// TDD: Api.uploadDocument sends auth header + file part + fields;
// widget surfaces success/failure with server detail; no curl dialog.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eldercare_dashboard/main.dart';
import 'package:eldercare_dashboard/widgets/rag_upload_widget.dart';

import 'test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Api.resetForTest();
  });
  tearDown(() => Api.resetForTest());

  test('uploadDocument sends auth header + file part + fields', () async {
    Api.setTestSession(
        token: 'tok-abc', refreshToken: 'ref-1', userId: 'cg1');
    http.BaseRequest? seen;
    Api.testClient = FakeClient((req, body) async {
      seen = req;
      return jsonRes({'document_id': 'd1', 'message': 'ok'}, 200);
    });

    await Api.uploadDocument(
      patientId: 'p1',
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'care-plan.pdf',
      docType: 'prescription',
      title: 'Care Plan',
    );

    expect(seen, isNotNull);
    expect(seen!.url.path, '/api/v1/reports/documents/upload');
    expect(headerOf(seen!, 'authorization'), 'Bearer tok-abc');
    final mp = seen as http.MultipartRequest;
    expect(mp.fields['patient_id'], 'p1');
    expect(mp.fields['doc_type'], 'prescription');
    expect(mp.fields['title'], 'Care Plan');
    expect(mp.files, hasLength(1));
    expect(mp.files.single.field, 'file');
    expect(mp.files.single.filename, 'care-plan.pdf');
  });

  testWidgets('widget surfaces upload success', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RagUploadWidget(
          patientId: 'p1',
          pickFn: () async =>
              (bytes: Uint8List.fromList([1, 2, 3]), filename: 'a.pdf'),
          uploadFn: ({
            required String patientId,
            required Uint8List bytes,
            required String filename,
            String docType = 'prescription',
            String? title,
          }) async =>
              {'document_id': 'd1'},
        ),
      ),
    ));

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    // Inline result + snackbar both carry the success text.
    expect(find.textContaining('Uploaded'), findsWidgets);
    expect(find.textContaining('curl'), findsNothing);
  });

  testWidgets('widget surfaces server failure detail', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RagUploadWidget(
          patientId: 'p1',
          pickFn: () async =>
              (bytes: Uint8List.fromList([1, 2, 3]), filename: 'a.pdf'),
          uploadFn: ({
            required String patientId,
            required Uint8List bytes,
            required String filename,
            String docType = 'prescription',
            String? title,
          }) async =>
              throw Exception('clinical tier required'),
        ),
      ),
    ));

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    // Inline result + snackbar both carry the server detail.
    expect(find.textContaining('clinical tier required'), findsWidgets);
  });

  testWidgets('non-web without picker seam shows web-only notice',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: RagUploadWidget(patientId: 'p1')),
    ));

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(find.textContaining('web dashboard only'), findsOneWidget);
  });
}

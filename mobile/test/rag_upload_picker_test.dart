/// Task 9: file_picker RAG upload behind the pickForTest seam.
/// TDD red: seam + pick→bytes→upload wiring do not exist yet
/// (_pickFile is a placeholder that only sets a hint message).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:eldercare_mobile/screens/rag_upload_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

base class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile(this.name, this.reportedSize, {this.onRead});

  @override
  final String name;

  final int? reportedSize;
  final void Function()? onRead;

  @override
  Uri get uri => Uri.file('/tmp/$name');

  @override
  Never get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => reportedSize;

  @override
  Future<int?> length() async => reportedSize;

  @override
  Future<Uint8List> readAsBytes() async {
    onRead?.call();
    return Uint8List.fromList(utf8.encode('small contents'));
  }

  @override
  Stream<Uint8List> readAsByteStream() => const Stream.empty();
}

void main() {
  group('task 9 pickForTest seam', () {
    testWidgets(
        'pick → filename display → Upload sends picked file part + success',
        (tester) async {
      http.MultipartRequest? captured;
      await tester.pumpWidget(MaterialApp(
        home: RagUploadScreen(
          patientId: 'p1',
          pickForTest: () async => (
            bytes: Uint8List.fromList(utf8.encode('hello')),
            filename: 'note.pdf',
          ),
          sendForTest: (req) async {
            captured = req;
            return http.Response('', 200);
          },
        ),
      ));
      await tester.pumpAndSettle();

      // No file yet: display line default + Upload disabled (no testBytes).
      expect(find.text('No file selected.'), findsOneWidget);
      final uploadBtn = find.widgetWithText(FilledButton, 'UPLOAD ▸');
      expect(uploadBtn, findsOneWidget);
      expect(tester.widget<FilledButton>(uploadBtn).onPressed, isNull);

      await tester.tap(find.text('SELECT FILE'));
      await tester.pumpAndSettle();

      // Picked filename now displays; Upload enabled via real label.
      expect(find.text('note.pdf'), findsOneWidget);
      expect(find.text('No file selected.'), findsNothing);
      expect(tester.widget<FilledButton>(uploadBtn).onPressed, isNotNull);

      await tester.tap(uploadBtn);
      await tester.pumpAndSettle();

      // Captured multipart carries the picked file (buildRagUploadRequest
      // field name 'file') with the picked bytes.
      expect(captured, isNotNull);
      expect(captured!.files, hasLength(1));
      expect(captured!.files.single.field, 'file');
      expect(captured!.files.single.filename, 'note.pdf');
      expect(captured!.files.single.length, utf8.encode('hello').length);
      expect(find.text('Uploaded successfully (HTTP 200).'), findsOneWidget);
    });

    testWidgets('cancel (null pick) leaves no file, Upload stays disabled',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: RagUploadScreen(
          patientId: 'p1',
          pickForTest: () async => null,
          sendForTest: (req) async => http.Response('', 200),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No file selected.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'UPLOAD ▸'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('SELECT FILE'));
      await tester.pumpAndSettle();

      // Cancel = no state change, no crash, no result message.
      expect(find.text('No file selected.'), findsOneWidget);
      expect(find.textContaining('Upload'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'UPLOAD ▸'))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('successfully'), findsNothing);
      expect(find.textContaining('Please select'), findsNothing);
      expect(find.textContaining('Error'), findsNothing);
    });
  });

  testWidgets('pick of a rejected type shows the type message, Upload stays off',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        pickForTest: () async => (
          bytes: Uint8List.fromList(utf8.encode('binary-ish')),
          filename: 'scan.png',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SELECT FILE'));
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't supported"), findsOneWidget);
    expect(find.text('No file selected.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'UPLOAD ▸')).onPressed,
      isNull,
    );
  });

  testWidgets('pick over 10 MB is rejected before any request', (tester) async {
    var hitBackend = false;
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        pickForTest: () async => (
          bytes: Uint8List(10 * 1024 * 1024 + 1),
          filename: 'big.txt',
        ),
        sendForTest: (req) async {
          hitBackend = true;
          return http.Response('', 200);
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SELECT FILE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('10 MB'), findsOneWidget);
    expect(hitBackend, isFalse);
  });

  testWidgets('invalid test bytes are rejected by upload before sender',
      (tester) async {
    var hitBackend = false;
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        testBytes: Uint8List.fromList(utf8.encode('binary-ish')),
        testFilename: 'scan.png',
        sendForTest: (req) async {
          hitBackend = true;
          return http.Response('', 200);
        },
      ),
    ));
    await tester.pumpAndSettle();

    final uploadBtn = find.widgetWithText(FilledButton, 'UPLOAD ▸');
    expect(tester.widget<FilledButton>(uploadBtn).onPressed, isNotNull);
    await tester.tap(uploadBtn);
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't supported"), findsOneWidget);
    expect(hitBackend, isFalse);
  });

  testWidgets('invalid pick leaves previous filename and bytes intact',
      (tester) async {
    var pickCount = 0;
    http.MultipartRequest? captured;
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        pickForTest: () async {
          pickCount++;
          if (pickCount == 1) {
            return (
              bytes: Uint8List.fromList(utf8.encode('valid contents')),
              filename: 'valid.txt',
            );
          }
          return (
            bytes: Uint8List.fromList(utf8.encode('replacement')),
            filename: 'invalid.png',
          );
        },
        sendForTest: (req) async {
          captured = req;
          return http.Response('', 200);
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SELECT FILE'));
    await tester.pumpAndSettle();
    expect(find.text('valid.txt'), findsOneWidget);

    await tester.tap(find.text('SELECT FILE'));
    await tester.pumpAndSettle();
    expect(find.text('valid.txt'), findsOneWidget);
    expect(find.text('invalid.png'), findsNothing);
    expect(find.textContaining("isn't supported"), findsOneWidget);

    final uploadBtn = find.widgetWithText(FilledButton, 'UPLOAD ▸');
    expect(tester.widget<FilledButton>(uploadBtn).onPressed, isNotNull);
    await tester.tap(uploadBtn);
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    final request = captured!;
    expect(request.files.single.filename, 'valid.txt');
    final sentBytes = await request.files.single.finalize().toBytes();
    expect(sentBytes, utf8.encode('valid contents'));
  });

  testWidgets('reported oversized platform file is rejected before read',
      (tester) async {
    var readCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        platformPickForTest: () async => _FakePlatformFile(
          'big.txt',
          10 * 1024 * 1024 + 1,
          onRead: () => readCalled = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SELECT FILE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('10 MB'), findsOneWidget);
    expect(readCalled, isFalse);
  });

  testWidgets('platform read failure is shown visibly', (tester) async {
    var readCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        platformPickForTest: () async => _FakePlatformFile(
          'note.txt',
          12,
          onRead: () {
            readCalled = true;
            throw StateError('read failed');
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SELECT FILE'));
    await tester.pumpAndSettle();

    expect(readCalled, isTrue);
    expect(find.textContaining('Could not read selected file'), findsOneWidget);
    expect(find.textContaining('read failed'), findsOneWidget);
  });

  testWidgets('picker failure is shown visibly', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RagUploadScreen(
        patientId: 'p1',
        platformPickForTest: () async => throw StateError('picker failed'),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SELECT FILE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not select file'), findsOneWidget);
    expect(find.textContaining('picker failed'), findsOneWidget);
  });
}

import 'package:eldercare_mobile/services/document_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateDocumentFile', () {
    for (final name in const ['note.pdf', 'notes.TXT', 'plan.md', 'log.text', 'rows.csv']) {
      test('accepts $name', () {
        expect(validateDocumentFile(filename: name, byteLength: 1024), isNull);
      });
    }

    for (final name in const ['scan.png', 'sheet.xlsx', 'note.doc', 'note.docx', 'noext']) {
      test('rejects $name with a type message', () {
        final msg = validateDocumentFile(filename: name, byteLength: 1024);
        expect(msg, isNotNull);
        expect(msg, contains("isn't supported"));
      });
    }

    test('rejects empty file', () {
      expect(validateDocumentFile(filename: 'a.txt', byteLength: 0),
          contains('empty'));
    });

    test('rejects over 10 MB', () {
      final msg = validateDocumentFile(
          filename: 'a.txt', byteLength: 10 * 1024 * 1024 + 1);
      expect(msg, contains('10 MB'));
    });

    test('accepts exactly 10 MB', () {
      expect(
          validateDocumentFile(
              filename: 'a.txt', byteLength: 10 * 1024 * 1024),
          isNull);
    });
  });
}

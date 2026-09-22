// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
/// Web implementation of the RAG upload file picker via an HTML file input.
/// No new dependency: uses `dart:html` only on web (conditional import).
library;

import 'dart:html' as html;

import 'dart:async';
import 'dart:typed_data';

Future<({Uint8List bytes, String filename})?> pickDocumentFile() {
  final completer = Completer<({Uint8List bytes, String filename})?>();
  final input = html.FileUploadInputElement()
    ..accept = '.pdf,.txt,.md,.doc,.docx';
  var settled = false;
  void settle(FutureOr<({Uint8List bytes, String filename})?> value) {
    if (!settled) {
      settled = true;
      completer.complete(value);
    }
  }

  void settleError(Object e) {
    if (!settled) {
      settled = true;
      completer.completeError(e);
    }
  }

  input.onChange.listen((_) async {
    try {
      final files = input.files;
      if (files == null || files.isEmpty) {
        settle(null);
        return;
      }
      final file = files.single;
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      final result = reader.result;
      if (result is ByteBuffer) {
        settle((bytes: Uint8List.view(result), filename: file.name));
      } else if (result is List<int>) {
        settle((bytes: Uint8List.fromList(result), filename: file.name));
      } else {
        settleError(StateError('Could not read ${file.name}'));
      }
    } catch (e) {
      settleError(e);
    }
  });
  input.onError.listen(settleError);
  // Cancel (dialog dismissed) fires no change event — resolve null when the
  // window regains focus without a completion.
  html.window.onFocus.first.then((_) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!settled) settle(null);
    });
  });
  input.click();
  return completer.future;
}

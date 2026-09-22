/// Non-web stub for the RAG upload file picker — always resolves null
/// (the widget shows the "web only" notice on these platforms).
library;

import 'dart:typed_data';

Future<({Uint8List bytes, String filename})?> pickDocumentFile() async => null;

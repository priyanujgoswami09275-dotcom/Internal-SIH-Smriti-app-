/// File cache for synthesized reminder speech.
///
/// Identical (text, language) pairs synthesize once: the audio bytes are
/// stored under a stable hash key in the temp directory and replayed from
/// disk afterwards. Every failure degrades to null so callers fall back
/// to text display — TTS must never break the reminder flow.
library;

import 'dart:io';
import 'dart:typed_data';

class TtsCache {
  final Future<Uint8List> Function(String text, String language) synthesize;

  TtsCache({required this.synthesize});

  /// Stable filename key for (text, language): FNV-1a hex (dependency-free
  /// and stable across runs, unlike hashCode). Masked to 63 bits so Dart's
  /// signed 64-bit ints never produce a '-' prefix.
  static const int _fnvPrime = 0x100000001b3;
  static const int _mask63 = 0x7FFFFFFFFFFFFFFF;

  static String cacheKey(String text, String language) {
    var hash = 0xcbf29ce484222325 & _mask63;
    final input = '$language|$text';
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * _fnvPrime) & _mask63;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  Future<File> _fileFor(String text, String language) async {
    return File(
        '${Directory.systemTemp.path}/smriti_tts_${cacheKey(text, language)}.wav');
  }

  /// Cached audio bytes, or null when unavailable (caller shows text).
  Future<Uint8List?> speechFor(String text, String language) async {
    if (text.trim().isEmpty) return null;
    try {
      final cached = await _fileFor(text, language);
      if (await cached.exists()) {
        final bytes = await cached.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
    } catch (_) {
      // Fall through to synthesis.
    }
    try {
      final bytes = await synthesize(text, language);
      if (bytes.isEmpty) return null;
      try {
        await (await _fileFor(text, language))
            .writeAsBytes(bytes, flush: true);
      } catch (_) {
        // Cache write failure must not lose the freshly synthesized audio.
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

import 'dart:io';
import 'dart:typed_data';

class TtsResult {
  const TtsResult({this.bytes, this.error});

  final Uint8List? bytes;
  final Object? error;

  bool get hasAudio => bytes != null && bytes!.isNotEmpty;
}

class TtsCache {
  final Future<Uint8List> Function(String text, String language) synthesize;

  TtsCache({required this.synthesize});

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
      '${Directory.systemTemp.path}/smriti_tts_${cacheKey(text, language)}.wav',
    );
  }

  Future<TtsResult> speechResult(String text, String language) async {
    if (text.trim().isEmpty) {
      return const TtsResult();
    }
    try {
      final cached = await _fileFor(text, language);
      if (await cached.exists()) {
        final bytes = await cached.readAsBytes();
        if (bytes.isNotEmpty) return TtsResult(bytes: bytes);
      }
    } catch (_) {}
    try {
      final bytes = await synthesize(text, language);
      if (bytes.isEmpty) {
        return TtsResult(error: StateError('TTS returned empty audio'));
      }
      try {
        await (await _fileFor(text, language)).writeAsBytes(bytes, flush: true);
      } catch (_) {}
      return TtsResult(bytes: bytes);
    } catch (error) {
      return TtsResult(error: error);
    }
  }

  Future<Uint8List?> speechFor(String text, String language) async =>
      (await speechResult(text, language)).bytes;
}

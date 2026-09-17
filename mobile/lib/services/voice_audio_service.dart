/// Device-side voice helpers for the companion screen.
///
/// Speech intelligence stays server-side (Sarvam/Bhashini/mock chain behind
/// POST /language/asr and /language/tts); the device only records mic audio
/// and plays reply audio. [SilenceDetector] is pure Dart so the auto-stop
/// rule is unit-testable without microphone or plugin mocks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Decides when a recording turn should end: sustained silence past
/// [silenceTimeout], or the [maxDuration] hard cap — whichever comes first.
/// Feed live amplitudes; returns true when recording should stop.
class SilenceDetector {
  final double silenceThresholdDb;
  final Duration silenceTimeout;
  final Duration maxDuration;

  DateTime _start = DateTime.now();
  DateTime? _silenceSince;

  SilenceDetector({
    this.silenceThresholdDb = -40.0,
    this.silenceTimeout = const Duration(milliseconds: 2500),
    this.maxDuration = const Duration(seconds: 30),
  });

  void reset([DateTime? now]) {
    _start = now ?? DateTime.now();
    _silenceSince = null;
  }

  bool feed(double amplitudeDb, [DateTime? now]) {
    final t = now ?? DateTime.now();
    if (t.difference(_start) >= maxDuration) return true;
    if (amplitudeDb < silenceThresholdDb) {
      _silenceSince ??= t;
      if (t.difference(_silenceSince!) >= silenceTimeout) return true;
    } else {
      _silenceSince = null;
    }
    return false;
  }
}

enum MicPermission { granted, denied, permanentlyDenied, unavailable }

/// Thin wrapper over the mic/record/player plugins. Every method degrades
/// to a safe value (false/null) on plugin failure so the UI can fall back
/// to text chat instead of crashing.
class VoiceAudioService {
  final AudioRecorder _recorder;
  final AudioPlayer _player;
  final SilenceDetector silenceDetector;

  VoiceAudioService({
    AudioRecorder? recorder,
    AudioPlayer? player,
    SilenceDetector? silenceDetector,
  })  : _recorder = recorder ?? AudioRecorder(),
        _player = player ?? AudioPlayer(),
        silenceDetector = silenceDetector ?? SilenceDetector();

  /// Live mic level in dBFS for the listening-pulse UI.
  Stream<double> get amplitudeStream => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 200))
      .map((a) => a.current);

  /// First-use mic prompt. Returns the outcome; the caller decides UI
  /// (snackbar, settings redirect, or hide-the-mic fallback).
  Future<MicPermission> ensureMicPermission() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted || status.isLimited) return MicPermission.granted;
      if (status.isPermanentlyDenied) return MicPermission.permanentlyDenied;
      return MicPermission.denied;
    } catch (_) {
      return MicPermission.unavailable;
    }
  }

  Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {}
  }

  /// Start 16kHz mono wav capture — the server ASR input contract
  /// (Bhashini expects wav). Returns false when capture cannot start.
  Future<bool> startRecording() async {
    try {
      if (await _recorder.isRecording()) return true;
      final path =
          '${Directory.systemTemp.path}/smriti_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      silenceDetector.reset();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stop capture and return base64 wav for POST /language/asr (temp file
  /// is deleted). Null when nothing usable was captured.
  Future<String?> stopRecording() async {
    try {
      final path = await _recorder.stop();
      if (path == null) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      await file.delete();
      if (bytes.isEmpty) return null;
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Abort a turn without returning audio (temp file is deleted).
  Future<void> cancelRecording() async {
    try {
      final path = await _recorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
  }

  /// Stop any in-flight reply before starting a new turn.
  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Fires when reply playback finishes naturally (screens reset their
  /// speaking indicator; failures stay silent).
  Stream<void> get onReplyComplete {
    try {
      return _player.onPlayerComplete;
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// Play TTS reply bytes. Failures are swallowed — the caller keeps the
  /// text bubble as the fallback, so playback never breaks the chat.
  Future<void> playReply(List<int> audioBytes) async {
    try {
      await _player.stop();
      await _player.play(BytesSource(Uint8List.fromList(audioBytes)));
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}

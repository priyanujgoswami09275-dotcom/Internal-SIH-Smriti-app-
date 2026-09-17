/// Voice Companion — warm, calm conversation with the elder in their language.
///
/// Text chat always works. When the mic is available, the elder can also
/// talk: audio is recorded on-device, transcribed server-side
/// (POST /language/asr), sent through the normal chat flow, and the reply
/// is spoken back (POST /language/tts). Every voice step degrades to text.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/voice_audio_service.dart';
import '../services/voice_languages.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';

class VoiceCompanionScreen extends StatefulWidget {
  final String patientId;

  const VoiceCompanionScreen({super.key, required this.patientId});

  @override
  State<VoiceCompanionScreen> createState() => _VoiceCompanionScreenState();
}

class _VoiceCompanionScreenState extends State<VoiceCompanionScreen> {
  final ApiService _api = ApiService.instance;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];

  String _selectedLanguage = 'assamese';
  bool _sending = false;
  bool _wasFallback = false;

  // Voice turn state. Recording/transcribing never block text chat —
  // the text field stays usable and every failure shows a note, not a crash.
  final VoiceAudioService _voice = VoiceAudioService();
  StreamSubscription<double>? _ampSub;
  Timer? _recordTimer;
  bool _recording = false;
  bool _transcribing = false;
  bool _ttsEnabled = true;
  double _voiceLevel = 0.0;
  int _recordSeconds = 0;

  /// Languages the active backend provider actually covers (from
  /// /language/status). Null while loading or when the call fails —
  /// all covered picker entries stay enabled as before (Garo excepted:
  /// no provider covers it — see VoiceLanguages.hardUnsupported).
  Set<String>? _providerLanguages;

  static const _greeting = 'নমস্কাৰ! মই আপোনাৰ লগত আছোঁ। আজি কেনে আছে?';

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      content: _greeting,
      isCompanion: true,
      timestamp: DateTime.now(),
    ));
    _loadProviderLanguages();
  }

  Future<void> _loadProviderLanguages() async {
    // The active provider may not cover every picker language (AI4Bharat
    // models exclude Khasi + Mizo). The backend reports its supported set;
    // uncovered languages show "not yet available" and are disabled rather
    // than erroring at send time.
    try {
      final data = await _api
          .getJson('${AppConfig.apiV1}/language/status');
      final langs = (data['supported_languages'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .toSet();
      if (mounted) setState(() => _providerLanguages = langs);
    } on Exception {
      // Offline or backend down — keep all languages enabled (mock covers all).
      if (mounted) setState(() => _providerLanguages = null);
    }
  }

  bool _languageAvailable(String code) =>
      VoiceLanguages.available(code, _providerLanguages);

  @override
  void dispose() {
    _ampSub?.cancel();
    _recordTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _voice.stopPlayback();
    _voice.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String rawMessage) async {
    final message = rawMessage.trim();
    if (message.isEmpty || _sending || _recording) return;
    _messageController.clear();

    final userMsg = _ChatMessage(content: message, isCompanion: false, timestamp: DateTime.now());
    setState(() {
      _messages.add(userMsg);
      _sending = true;
      _wasFallback = false;
    });
    _scrollToBottom();

    try {
      final result = await _api.companionTextChat(
        patientId: widget.patientId,
        message: message,
        language: _selectedLanguage,
        history: _messages
            .where((m) => !m.isCompanion || m.content != _greeting)
            .map((m) => {'role': m.isCompanion ? 'assistant' : 'user', 'content': m.content})
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          content: result.replyText,
          isCompanion: true,
          timestamp: DateTime.now(),
        ));
        _wasFallback = result.fallback;
        _sending = false;
      });
      _speakReply(result.replyText);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          content: 'I am here with you. Please try again.',
          isCompanion: true,
          timestamp: DateTime.now(),
          isFallback: true,
        ));
        _sending = false;
      });
      debugPrint('Companion chat failed: $e');
    }
    _scrollToBottom();
  }

  // =====================================================================
  // Voice turn: mic → server ASR → normal chat → server TTS playback.
  // =====================================================================

  Future<void> _onMicTap() async {
    if (_sending || _transcribing) return;
    if (_recording) {
      await _finishRecording();
      return;
    }
    // First-use permission prompt; text chat stays available regardless.
    final permission = await _voice.ensureMicPermission();
    if (!mounted) return;
    if (permission == MicPermission.permanentlyDenied) {
      _showVoiceNote(
        'Microphone is blocked. Enable it in Settings to talk.',
        actionLabel: 'Settings',
        action: _voice.openSettings,
      );
      return;
    }
    if (permission != MicPermission.granted) {
      _showVoiceNote('Microphone unavailable — you can type instead.');
      return;
    }
    await _voice.stopPlayback();
    final started = await _voice.startRecording();
    if (!mounted) return;
    if (!started) {
      _showVoiceNote('Could not start the microphone — you can type instead.');
      return;
    }
    setState(() {
      _recording = true;
      _voiceLevel = 0.0;
      _recordSeconds = 0;
    });
    _scrollToBottom();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recording) setState(() => _recordSeconds++);
    });
    _ampSub = _voice.amplitudeStream.listen((db) {
      if (!_recording || !mounted) return;
      setState(() => _voiceLevel = ((db + 60.0) / 60.0).clamp(0.0, 1.0));
      if (_voice.silenceDetector.feed(db)) {
        // Auto-stop on sustained silence (or the 30s hard cap).
        _finishRecording();
      }
    });
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    await _ampSub?.cancel();
    _ampSub = null;
    _recordTimer?.cancel();
    _recordTimer = null;
    setState(() {
      _recording = false;
      _transcribing = true;
      _voiceLevel = 0.0;
    });
    _scrollToBottom();
    try {
      final audioBase64 = await _voice.stopRecording();
      if (audioBase64 == null || audioBase64.isEmpty) {
        if (!mounted) return;
        setState(() => _transcribing = false);
        _showVoiceNote("Didn't catch that — try again or type instead.");
        return;
      }
      final text = await _api.transcribeAudio(
        audioBase64: audioBase64,
        language: _selectedLanguage,
      );
      if (!mounted) return;
      setState(() => _transcribing = false);
      if (text.trim().isEmpty) {
        _showVoiceNote("Didn't catch that — try again or type instead.");
        return;
      }
      await _send(text);
    } on Exception catch (e) {
      debugPrint('Voice turn failed: $e');
      if (!mounted) return;
      setState(() => _transcribing = false);
      _showVoiceNote('Voice is unavailable right now — you can type instead.');
    }
  }

  /// Speak the companion reply aloud. Best-effort: any failure keeps the
  /// text bubble as the fallback and never interrupts the chat.
  Future<void> _speakReply(String text) async {
    if (!_ttsEnabled || text.trim().isEmpty) return;
    try {
      final audio = await _api.synthesizeSpeech(
        text: text,
        language: _selectedLanguage,
      );
      if (audio.isEmpty) return;
      await _voice.playReply(audio);
    } catch (e) {
      debugPrint('TTS playback skipped: $e');
    }
  }

  void _showVoiceNote(
    String message, {
    String? actionLabel,
    VoidCallback? action,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: Monad.patientBody.copyWith(color: Monad.parchment),
        ),
        backgroundColor: Monad.offBlack,
        behavior: SnackBarBehavior.floating,
        action: (actionLabel != null && action != null)
            ? SnackBarAction(
                label: actionLabel,
                onPressed: action,
                textColor: Monad.tintGold,
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aai Companion'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: _ttsEnabled ? 'Mute voice replies' : 'Unmute voice replies',
            icon: Icon(
              _ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color: Monad.offBlack,
              size: 20,
            ),
            onPressed: () {
              if (_ttsEnabled) _voice.stopPlayback();
              setState(() => _ttsEnabled = !_ttsEnabled);
            },
          ),
          PopupMenuButton<String>(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language, color: Monad.offBlack, size: 20),
                const SizedBox(width: 4),
                Text(
                  VoiceLanguages.displayNames[_selectedLanguage] ??
                      _selectedLanguage,
                  style: Monad.monoCaption.copyWith(color: Monad.offBlack),
                ),
              ],
            ),
            onSelected: (v) => setState(() => _selectedLanguage = v),
            itemBuilder: (context) => VoiceLanguages.displayNames.entries
                .map((e) {
                  final available = _languageAvailable(e.key);
                  return PopupMenuItem(
                      value: available ? e.key : null,
                      enabled: available,
                      child: Row(
                        children: [
                          if (e.key == _selectedLanguage)
                            const Icon(Icons.check, size: 16, color: Monad.lakeBlue),
                          if (e.key != _selectedLanguage) const SizedBox(width: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              available
                                  ? e.value
                                  : '${e.value} — not yet available',
                              style: Monad.monoBody.copyWith(
                                color: available
                                    ? Monad.offBlack
                                    : Monad.smoke,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                })
                .toList(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Parchment canvas — no gradient washes on patient-facing chrome.
      body: SafeArea(
        child: Column(
          children: [
            if (_wasFallback)
              _offlineBanner(),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                itemCount: _messages.length +
                    (_sending || _transcribing || _recording ? 1 : 0),
                itemBuilder: (context, index) => index < _messages.length
                    ? _messageBubble(_messages[index])
                    : (_recording ? _listeningBubble() : _typingBubble()),
              ),
            ),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _offlineBanner() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: ShapeDecoration(
            color: Monad.tintGold,
            shape: const StadiumBorder(side: BorderSide(color: Monad.ash, width: 1)),
          ),
          child: Text(
            'OFFLINE MODE — RESPONSES SIMPLIFIED',
            style: Monad.monoBodySm.copyWith(color: Monad.offBlack),
          ),
        ),
      ),
    );
  }

  Widget _messageBubble(_ChatMessage msg) {
    final isUser = !msg.isCompanion;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _companionAvatar(),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? Monad.parchment : Monad.periwinkleMist,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: Border.all(color: Monad.ash, width: 1),
              ),
              child: Text(
                msg.content,
                style: Monad.patientBody.copyWith(
                  color: Monad.offBlack,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            _userAvatar(),
          ],
        ],
      ),
    );
  }

  /// Listening indicator: pulsing red dot driven by the live mic level,
  /// elapsed time, and a tap-to-stop hint for low-literacy users.
  Widget _listeningBubble() {
    final mm = (_recordSeconds ~/ 60).toString();
    final ss = (_recordSeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _companionAvatar(),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Monad.periwinkleMist,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: Monad.ash, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 12 + _voiceLevel * 10,
                    height: 12 + _voiceLevel * 10,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Listening… $mm:$ss — tap ■ to stop',
                      style: Monad.patientBody,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _companionAvatar(),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Monad.periwinkleMist,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(color: Monad.ash, width: 1),
              ),
              child: Text('…', style: Monad.patientBody),
            ),
          ),
        ],
      ),
    );
  }

  Widget _companionAvatar() {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Monad.periwinkleMist,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: Monad.ash, width: 1)),
      ),
      child: const Icon(Icons.favorite, color: Monad.offBlack, size: 18),
    );
  }

  Widget _userAvatar() {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: Monad.periwinkleMist,
        shape: BoxShape.circle,
        border: Border.all(color: Monad.ash, width: 1),
      ),
      child: const Icon(Icons.person, color: Monad.graphite, size: 18),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Monad.parchment,
        border: Border(top: BorderSide(color: Monad.ash, width: 1)),
      ),
      child: Row(
        children: [
          _micButton(),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 50,
              child: TextField(
                controller: _messageController,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                // Patient-facing input floor: 20px.
                style: Monad.patientBody,
                decoration: InputDecoration(
                  hintText: VoiceLanguages.inputHints[_selectedLanguage] ??
                      'Type a message…',
                  hintStyle: Monad.monoBody.copyWith(color: Monad.smoke),
                  filled: true,
                  fillColor: Monad.parchment,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Monad.radiusMin),
                    borderSide: const BorderSide(color: Monad.ash, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Monad.radiusMin),
                    borderSide: const BorderSide(color: Monad.ash, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Monad.radiusMin),
                    borderSide: const BorderSide(color: Monad.lakeBlue, width: 1),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          MonadPillButton(
            label: 'Send',
            variant: MonadPillVariant.primary,
            busy: _sending,
            onPressed: () => _send(_messageController.text),
          ),
        ],
      ),
    );
  }
  /// Mic button: idle mic → tap to talk; while recording it becomes a
  /// stop square that grows with the live voice level. Disabled (greyed)
  /// while a message is sending or transcribing. Never removes text input.
  Widget _micButton() {
    final busy = _sending || _transcribing;
    final glow = _recording ? _voiceLevel * 8 : 0.0;
    return GestureDetector(
      onTap: busy ? null : _onMicTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50 + glow,
        height: 50 + glow,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: busy
              ? Monad.ash
              : (_recording ? Monad.offBlack : Monad.periwinkleMist),
          border: Border.all(color: Monad.ash, width: 1),
        ),
        child: Icon(
          _recording ? Icons.stop : Icons.mic,
          color: _recording ? Monad.parchment : Monad.offBlack,
          size: 24,
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String content;
  final bool isCompanion;
  final DateTime timestamp;
  final bool isFallback;

  _ChatMessage({
    required this.content,
    required this.isCompanion,
    required this.timestamp,
    this.isFallback = false,
  });
}

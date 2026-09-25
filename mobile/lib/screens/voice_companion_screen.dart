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
import '../patient_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_session.dart';
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

  String _selectedLanguage = 'english';
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

  LanguageCapabilityStatus? _capabilities;
  bool _capabilityUnavailable = false;
  late String _greeting;

  bool get _asrAvailable =>
      _capabilities?.supports('asr', _selectedLanguage) ?? false;
  bool get _ttsAvailable =>
      _capabilities?.supports('tts', _selectedLanguage) ?? false;
  bool get _nmtAvailable =>
      _capabilities?.supports('nmt', _selectedLanguage) ?? false;

  @override
  void initState() {
    super.initState();
    _selectedLanguage =
        AuthSession.instance.user?.preferredLanguage ?? 'english';
    _greeting = _greetingForLanguage(_selectedLanguage);
    _messages.add(_ChatMessage(
      content: _greeting,
      isCompanion: true,
      timestamp: DateTime.now(),
    ));
    _loadProviderCapabilities();
  }

  String _greetingForLanguage(String language) =>
      PatientLocalizations.forLanguage(language, 'voice.greeting');

  Future<void> _loadProviderCapabilities() async {
    try {
      final data = await _api.getJson('${AppConfig.apiV1}/language/status');
      if (!mounted) return;
      setState(() {
        _capabilities = LanguageCapabilityStatus.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        _capabilityUnavailable = false;
      });
    } on Exception {
      if (mounted) {
        setState(() {
          _capabilities = null;
          _capabilityUnavailable = true;
        });
      }
    }
  }

  bool _textLanguageAvailable(String code) {
    if (VoiceLanguages.hardUnsupported.contains(code)) return false;
    final capabilities = _capabilities;
    if (capabilities == null || !capabilities.capabilitiesKnown) return true;
    return capabilities.asrLanguages.contains(code) ||
        capabilities.nmtLanguages.contains(code) ||
        capabilities.ttsLanguages.contains(code);
  }

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

  bool _replyUsesSelectedLanguage(String text) {
    if (text.trim().isEmpty) return true;
    switch (_selectedLanguage) {
      case 'assamese':
      case 'bengali':
        return RegExp(r'[\u0980-\u09FF]').hasMatch(text);
      case 'hindi':
        return RegExp(r'[\u0900-\u097F]').hasMatch(text);
      case 'english':
        return RegExp(r'[A-Za-z]').hasMatch(text);
      default:
        return !RegExp(r'[A-Za-z]').hasMatch(text);
    }
  }

  Future<void> _send(String rawMessage) async {
    final message = rawMessage.trim();
    if (message.isEmpty || _sending || _recording) return;
    final translationUnavailableText =
        context.tr('voice.translationUnavailable');

    final fallbackText = context.tr('voice.fallback');

    _messageController.clear();

    final userMsg = _ChatMessage(
      content: message,
      isCompanion: false,
      timestamp: DateTime.now(),
    );
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
            .map((m) => {
                  'role': m.isCompanion ? 'assistant' : 'user',
                  'content': m.content,
                })
            .toList(),
      );
      var replyText = result.replyText;
      String? translationNotice;
      if (_nmtAvailable && !_replyUsesSelectedLanguage(replyText)) {
        try {
          final translated = await _api.translateText(
            text: replyText,
            sourceLanguage: 'english',
            targetLanguage: _selectedLanguage,
          );
          if (translated.simulated || translated.text.trim().isEmpty) {
            if (!context.mounted) return;
            translationNotice = translationUnavailableText;
          } else {
            replyText = translated.text;
          }
        } on Exception {
          if (!context.mounted) return;
          translationNotice = translationUnavailableText;
        }
      }
      if (!context.mounted) return;
      final fallbackNotice = result.fallback ? fallbackText : translationNotice;
      setState(() {
        if (fallbackNotice != null) {
          _messages.add(_ChatMessage(
            content: fallbackNotice,
            isCompanion: true,
            timestamp: DateTime.now(),
            isFallback: true,
          ));
        }
        _messages.add(_ChatMessage(
          content: replyText,
          isCompanion: true,
          timestamp: DateTime.now(),
        ));
        _wasFallback = result.fallback;
        _sending = false;
      });
      await _speakReply(
        replyText,
        disclosure: result.fallback ? fallbackText : null,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          content: fallbackText,
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
    if (!_asrAvailable) {
      _showVoiceNote(context.tr('voice.asrUnavailable'));
      return;
    }
    if (_recording) {
      await _finishRecording();
      return;
    }
    // First-use permission prompt; text chat stays available regardless.
    final permission = await _voice.ensureMicPermission();
    if (!mounted) return;
    if (permission == MicPermission.permanentlyDenied) {
      _showVoiceNote(
        context.tr('voice.permission'),
        actionLabel: 'Settings',
        action: _voice.openSettings,
      );
      return;
    }
    if (permission != MicPermission.granted) {
      _showVoiceNote(context.tr('voice.asrUnavailable'));
      return;
    }
    await _voice.stopPlayback();
    final started = await _voice.startRecording();
    if (!mounted) return;
    if (!started) {
      _showVoiceNote(context.tr('voice.asrUnavailable'));
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
      final recognition = await _api.transcribeAudio(
        audioBase64: audioBase64,
        language: _selectedLanguage,
      );
      if (!mounted) return;
      setState(() => _transcribing = false);
      if (recognition.simulated || recognition.provider == 'mock') {
        _showVoiceNote(context.tr('voice.mockDetail'));
        return;
      }
      if (recognition.text.trim().isEmpty) {
        _showVoiceNote(context.tr('voice.asrUnavailable'));
        return;
      }
      await _send(recognition.text);
    } on Exception catch (e) {
      debugPrint('Voice turn failed: $e');
      if (!mounted) return;
      setState(() => _transcribing = false);
      _showVoiceNote(context.tr('voice.asrUnavailable'));
    }
  }

  /// Speak the companion reply aloud. Best-effort: any failure keeps the
  /// text bubble as the fallback and never interrupts the chat.
  Future<void> _speakReply(String text, {String? disclosure}) async {
    if (!_ttsEnabled || !_ttsAvailable || text.trim().isEmpty) return;
    try {
      final spokenText = disclosure == null ? text : '$disclosure $text';
      final result = await _api.synthesizeSpeechResult(
        text: spokenText,
        language: _selectedLanguage,
      );
      if (result.simulated ||
          result.provider == 'mock' ||
          result.bytes.isEmpty) {
        return;
      }
      await _voice.playReply(result.bytes);
    } catch (e) {
      debugPrint('TTS playback skipped: $e');
      if (mounted) _showVoiceNote(context.tr('voice.ttsUnavailable'));
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

  String _languageLabel(String code) {
    final name = VoiceLanguages.displayNames[code] ?? code;
    if (PatientLocalizations.isLocalized(code)) return name;
    return '$name — ${context.tr('voice.languageFallback')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('voice.title')),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: !_ttsAvailable
                ? context.tr('voice.ttsUnavailable')
                : (_ttsEnabled
                    ? context.tr('voice.mute')
                    : context.tr('voice.unmute')),
            icon: Icon(
              _ttsAvailable && _ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color: Monad.offBlack,
              size: 20,
            ),
            onPressed: _ttsAvailable
                ? () {
                    if (_ttsEnabled) _voice.stopPlayback();
                    setState(() => _ttsEnabled = !_ttsEnabled);
                  }
                : null,
          ),
          PopupMenuButton<String>(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language, color: Monad.offBlack, size: 20),
                const SizedBox(width: 4),
                Text(
                  _languageLabel(_selectedLanguage),
                  style: Monad.monoCaption.copyWith(color: Monad.offBlack),
                ),
              ],
            ),
            onSelected: (value) async {
              setState(() {
                _selectedLanguage = value;
                _greeting = _greetingForLanguage(value);
              });
              await AuthSession.instance.setPreferredLanguage(value);
            },
            itemBuilder: (context) =>
                VoiceLanguages.displayNames.entries.map((entry) {
              final available = _textLanguageAvailable(entry.key);
              return PopupMenuItem(
                value: available ? entry.key : null,
                enabled: available,
                child: Row(
                  children: [
                    if (entry.key == _selectedLanguage)
                      const Icon(Icons.check, size: 16, color: Monad.lakeBlue),
                    if (entry.key != _selectedLanguage)
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        available
                            ? _languageLabel(entry.key)
                            : '${entry.value} — ${context.tr('voice.notYetAvailable')}',
                        style: Monad.monoBody.copyWith(
                          color: available ? Monad.offBlack : Monad.smoke,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Parchment canvas — no gradient washes on patient-facing chrome.
      body: SafeArea(
        child: Column(
          children: [
            if (_capabilities?.hasMockProvider ?? false) _providerBanner(),
            if (_capabilityUnavailable)
              _capabilityNote(context.tr('voice.statusUnavailable')),
            if (!_ttsAvailable && _capabilities?.capabilitiesKnown == true)
              _capabilityNote(context.tr('voice.ttsUnavailable')),
            if (_wasFallback) _offlineBanner(),
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

  Widget _providerBanner() {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Monad.tintGold,
            borderRadius: BorderRadius.circular(Monad.radiusMin),
            border: Border.all(color: Monad.ash),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('voice.mock'), style: Monad.monoBody),
              const SizedBox(height: 4),
              Text(context.tr('voice.mockDetail'), style: Monad.monoBodySm),
            ],
          ),
        ),
      ),
    );
  }

  Widget _capabilityNote(String message) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(message, style: Monad.monoBodySm),
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
            shape: const StadiumBorder(
                side: BorderSide(color: Monad.ash, width: 1)),
          ),
          child: Text(
            context.tr('voice.offline'),
            style: Monad.monoBodySm.copyWith(color: Monad.offBlack),
          ),
        ),
      ),
    );
  }

  Widget _messageBubble(_ChatMessage msg) {
    final isUser = !msg.isCompanion;
    return Semantics(
      liveRegion: msg.isFallback,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      '${context.tr('voice.listening')} $mm:$ss — ${context.tr('voice.stop')}',
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
      width: 36,
      height: 36,
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
                  hintText: PatientLocalizations.isLocalized(_selectedLanguage)
                      ? (VoiceLanguages.inputHints[_selectedLanguage] ??
                          context.tr('voice.typeMessage'))
                      : context.tr('voice.typeMessage'),
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
                    borderSide:
                        const BorderSide(color: Monad.lakeBlue, width: 1),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          MonadPillButton(
            label: context.tr('voice.send'),
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
    final unavailable = !_asrAvailable;

    final glow = _recording ? _voiceLevel * 8 : 0.0;
    return Semantics(
      button: true,
      enabled: !busy && !unavailable,
      label: context.tr('voice.listening'),
      child: GestureDetector(
        onTap: busy || unavailable ? null : _onMicTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 50 + glow,
          height: 50 + glow,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: busy || unavailable
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

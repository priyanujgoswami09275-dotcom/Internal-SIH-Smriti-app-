/// Daily Reminders — gradient cards with cultural atmosphere.
///
/// Cards with a due (pending/escalated) event speak the reminder aloud via
/// the server TTS chain (cached per phrase): a speaker button replays it,
/// and the first due card auto-plays once per screen open. Text always
/// stays on screen — voice is additive, never required.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/shared_models.dart';
import '../services/api_service.dart';
import '../services/auth_session.dart';
import '../services/reminder_phrases.dart';
import '../services/reminder_scheduler.dart';
import '../services/reminder_service.dart';
import '../services/tts_cache.dart';
import '../services/voice_audio_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';

class RemindersScreen extends StatefulWidget {
  final String patientId;

  const RemindersScreen({super.key, required this.patientId});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final MobileReminderService _reminders = MobileReminderService();
  final ApiService _api = ApiService.instance;
  final VoiceAudioService _voice = VoiceAudioService();
  late final TtsCache _tts = TtsCache(
    synthesize: (text, language) =>
        _api.synthesizeSpeech(text: text, language: language),
  );
  StreamSubscription<void>? _ttsDoneSub;

  List<ReminderScheduleModel>? _schedules;
  Map<String, ReminderEventModel> _openEventBySchedule = {};
  bool _loading = true;
  String? _error;
  final Set<String> _justAcked = {};

  /// Card currently speaking (null when silent). Playback failures stay
  /// silent — the text on the card is the fallback.
  String? _speakingScheduleId;

  /// Due cards already auto-played this screen open (auto-play fires once
  /// per card so refreshes never replay audio uninvited).
  final Set<String> _autoPlayed = {};

  String get _voiceLanguage =>
      AuthSession.instance.user?.preferredLanguage ?? 'assamese';

  @override
  void initState() {
    super.initState();
    _ttsDoneSub = _voice.onReplyComplete.listen((_) {
      if (mounted) setState(() => _speakingScheduleId = null);
    });
    _load();
  }

  @override
  void dispose() {
    _ttsDoneSub?.cancel();
    _voice.stopPlayback();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schedules = await _reminders.getSchedules(widget.patientId);
      final events = await _reminders.getTodaysEvents(widget.patientId);
      for (final schedule in schedules) {
        ReminderScheduler.instance
            .scheduleForSchedule(schedule)
            .catchError((_) {});
      }
      final open = <String, ReminderEventModel>{};
      for (final e in events) {
        if (e.status == ReminderStatus.pending ||
            e.status == ReminderStatus.escalated) {
          final existing = open[e.scheduleId];
          if (existing == null || e.scheduledAt.isAfter(existing.scheduledAt)) {
            open[e.scheduleId] = e;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _schedules = schedules;
        _openEventBySchedule = open;
        _loading = false;
      });
      // Voice-first: speak the first due reminder once (never on refresh).
      for (final schedule in schedules) {
        if (_openEventBySchedule.containsKey(schedule.id) &&
            !_autoPlayed.contains(schedule.id)) {
          _autoPlayed.add(schedule.id);
          _speakSchedule(schedule);
          break;
        }
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load reminders. $e';
      });
    }
  }

  /// Speak the reminder for [schedule] (cached TTS, text stays as fallback).
  /// Tapping the active card's speaker stops playback instead.
  Future<void> _speakSchedule(ReminderScheduleModel schedule) async {
    if (_speakingScheduleId == schedule.id) {
      await _voice.stopPlayback();
      if (mounted) setState(() => _speakingScheduleId = null);
      return;
    }
    setState(() => _speakingScheduleId = schedule.id);
    final audio = await _tts.speechFor(
      reminderPhrase(schedule.reminderType, _voiceLanguage),
      _voiceLanguage,
    );
    if (!mounted) return;
    if (audio == null) {
      // TTS unavailable for this phrase — the card text is the fallback.
      setState(() => _speakingScheduleId = null);
      return;
    }
    await _voice.playReply(audio);
  }

  Future<void> _handleAcknowledge(ReminderScheduleModel schedule) async {
    final openEvent = _openEventBySchedule[schedule.id];
    if (openEvent == null) return;
    if (_speakingScheduleId == schedule.id) {
      await _voice.stopPlayback();
      _speakingScheduleId = null;
    }
    final reachedServer = await _reminders.acknowledgeReminder(
      patientId: widget.patientId,
      eventId: openEvent.id,
      method: 'button',
    );
    if (!mounted) return;
    setState(() {
      _justAcked.add(schedule.id);
      _openEventBySchedule.remove(schedule.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${schedule.reminderType.name.toUpperCase()} done — well done! '
          '${reachedServer ? '' : '(offline — will sync)'}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ---- Design helpers ----

  /// Reminder tint surface: fixed mapping, icon + label + tint together.
  /// medicine = lakeBlue, water = skyBlue, food = gold, exercise = mint.
  static Color _tintFor(ReminderType type) {
    switch (type) {
      case ReminderType.medicine:
        return Color.lerp(Monad.parchment, Monad.lakeBlue, 0.12)!;
      case ReminderType.water:
        return Monad.tintSky;
      case ReminderType.food:
        return Monad.tintGold;
      case ReminderType.exercise:
        return Monad.tintMint;
    }
  }

  static IconData _iconFor(ReminderType type) {
    switch (type) {
      case ReminderType.medicine:
        return Icons.medication;
      case ReminderType.water:
        return Icons.water_drop;
      case ReminderType.food:
        return Icons.restaurant;
      case ReminderType.exercise:
        return Icons.directions_walk;
    }
  }

  static String _assameseFor(ReminderType type) {
    switch (type) {
      case ReminderType.medicine:
        return 'ঔষধ';
      case ReminderType.water:
        return 'পানী';
      case ReminderType.food:
        return 'খাদ্য';
      case ReminderType.exercise:
        return 'চলাচল';
    }
  }

  static String _descriptionFor(ReminderType type) {
    switch (type) {
      case ReminderType.medicine:
        return 'Time to take your medicine';
      case ReminderType.water:
        return 'Stay hydrated — drink water';
      case ReminderType.food:
        return 'Remember your meals';
      case ReminderType.exercise:
        return 'Light movement helps your mind';
    }
  }

  Widget _buildSectionHeader(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Monad.subheading),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: Monad.monoBody),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(ReminderScheduleModel schedule) {
    final done = _justAcked.contains(schedule.id);
    final hasOpenEvent = _openEventBySchedule.containsKey(schedule.id);
    // Tinted illustration surface only; icon + label + tint together.
    final surface = done ? Monad.tintMint : _tintFor(schedule.reminderType);

    return Container(
      margin: const EdgeInsets.only(bottom: Monad.spacing16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(Monad.radiusCard),
        border: Border.all(color: Monad.ash, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Main row
          Padding(
            padding: const EdgeInsets.all(Monad.cardPadding),
            child: Row(
              children: [
                // Icon container
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Monad.parchment,
                    borderRadius: BorderRadius.circular(Monad.radiusMin),
                    border: Border.all(color: Monad.ash, width: 1),
                  ),
                  child: Icon(
                    done
                        ? Icons.check_rounded
                        : _iconFor(schedule.reminderType),
                    color: Monad.offBlack,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 18),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type pill + assamese (icon + label + tint together)
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: const ShapeDecoration(
                              color: Monad.parchment,
                              shape: StadiumBorder(
                                  side: BorderSide(color: Monad.ash, width: 1)),
                            ),
                            child: Text(
                              schedule.reminderType.name.toUpperCase(),
                              style: Monad.monoBodySm.copyWith(
                                  color: Monad.offBlack,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _assameseFor(schedule.reminderType),
                            style: Monad.monoCaption
                                .copyWith(color: Monad.offBlack),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        done
                            ? '✓ Done today'
                            : _descriptionFor(schedule.reminderType),
                        style: Monad.patientBody,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        done ? '' : schedule.cadence,
                        style: Monad.monoBody.copyWith(color: Monad.graphite),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Action row: speaker replays the spoken reminder (due cards),
          // then the acknowledge button. Text always stays as the fallback.
          if (!done)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    if (hasOpenEvent)
                      Container(
                        width: 48,
                        height: 48,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: Monad.parchment,
                          borderRadius: BorderRadius.circular(Monad.radiusMin),
                          border: Border.all(color: Monad.ash, width: 1),
                        ),
                        child: IconButton(
                          tooltip: _speakingScheduleId == schedule.id
                              ? 'Stop voice'
                              : 'Hear reminder',
                          icon: Icon(
                            _speakingScheduleId == schedule.id
                                ? Icons.stop
                                : Icons.volume_up,
                            color: Monad.offBlack,
                            size: 24,
                          ),
                          onPressed: () => _speakSchedule(schedule),
                        ),
                      ),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: !hasOpenEvent
                            ? null
                            : () => _handleAcknowledge(schedule),
                        icon: Icon(
                          hasOpenEvent ? Icons.check_circle : Icons.access_time,
                          size: 24,
                        ),
                        label: Text(
                          hasOpenEvent ? 'I Did This  কৰিলোঁ' : 'Not Due Now',
                          style: Monad.monoButtonLabel.copyWith(fontSize: 20),
                        ),
                        // Secondary (offBlack) pill — the screen keeps lakeBlue
                        // reserved; repeated row actions stay black per DESIGN.md.
                        style: Monad.blackPill().copyWith(
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.disabled)
                                ? Monad.parchment
                                : Monad.offBlack,
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.disabled)
                                ? Monad.smoke
                                : Monad.white,
                          ),
                          side: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.disabled)
                                ? const BorderSide(color: Monad.ash, width: 1)
                                : BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (done)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Monad.parchment,
                  borderRadius: BorderRadius.circular(Monad.radiusButton),
                  border: Border.all(color: Monad.ash, width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle,
                        color: Monad.offBlack, size: 24),
                    const SizedBox(width: 10),
                    Text('Well done! — ধন্যবাদ', style: Monad.patientBody),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Reminders'),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _messageView(Icons.cloud_off, _error!, retry: _load)
              : _schedules == null || _schedules!.isEmpty
                  ? _messageView(Icons.alarm_on,
                      'No reminders yet — your caregiver will set them up.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: Monad.lakeBlue,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        children: [
                          _buildSectionHeader(
                            'Your Day',
                            subtitle: 'Tap when you complete each one',
                          ),
                          ...(_schedules!.map((s) => _buildCard(s))),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
    );
  }

  Widget _messageView(IconData icon, String text, {VoidCallback? retry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Monad.parchment,
                borderRadius: BorderRadius.circular(Monad.radiusMin + 8),
                border: Border.all(color: Monad.ash, width: 1),
              ),
              child: Icon(icon, size: 40, color: Monad.smoke),
            ),
            const SizedBox(height: 20),
            Text(text, textAlign: TextAlign.center, style: Monad.patientBody),
            if (retry != null) ...[
              const SizedBox(height: 20),
              MonadPillButton(label: 'Try Again', onPressed: retry),
            ],
          ],
        ),
      ),
    );
  }
}

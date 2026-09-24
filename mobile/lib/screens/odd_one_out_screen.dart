/// Odd-One-Out — spot the item that does not belong with the group.
///
/// Flow mirrors the other games: server session + board when online, cached
/// board + queued session offline, per-tap telemetry through the shared
/// pipeline, adaptive-engine report at completion.
///
/// Scoring truth is always the server: the board response never contains
/// the answer, taps post `select_odd_item` and the verdict comes from the
/// action response, and completion surfaces the server's next level +
/// source/reason display-only (never computed locally). Offline play uses
/// only a previously cached board snapshot — taxonomy/art is never
/// synthesized; with no compatible cache the screen shows an explicit
/// connect-to-download state. Offline taps are informational (isCorrect
/// null) and labeled pending-sync until the server scores the replay.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../games/game_analytics_engine.dart';
import '../games/game_visuals.dart';
import '../games/level_config.dart';
import '../models/game_models.dart';
import '../models/shared_models.dart';
import '../services/api_service.dart';
import '../services/offline_sync_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';

/// Server board endpoint (brief contract, authoritative).
String get oddOneOutBoardPath => '${AppConfig.apiV1}/games/odd-one-out/board';

/// SharedPreferences key for cached board snapshots, per difficulty level:
/// `{ "<level>": <board json> }`.
const String oddOneOutCacheKey = 'smriti_ooo_board_v1';

class OddOneOutScreen extends StatefulWidget {
  final String patientId;
  final int initialDifficulty;

  /// Injectable seams (tests); default to the app singletons.
  final ApiService? api;
  final OfflineSyncService? sync;

  const OddOneOutScreen({
    super.key,
    required this.patientId,
    this.initialDifficulty = 1,
    this.api,
    this.sync,
  });

  @override
  State<OddOneOutScreen> createState() => _OddOneOutScreenState();
}

class _OddOneOutScreenState extends State<OddOneOutScreen> {
  late final ApiService _api = widget.api ?? ApiService.instance;
  late final OfflineSyncService _sync =
      widget.sync ?? OfflineSyncService.instance;
  final GameAnalyticsEngine _engine = GameAnalyticsEngine.instance;

  int _difficulty = 1;
  OddOneOutBoard? _board;
  String? _sessionId;
  bool _loading = true;
  bool _offline = false;
  bool _ready = true; // ready panel (level picker) before each run
  bool _noCache = false; // offline with no compatible cached board
  bool _completing = false;
  bool _actionInProgress = false;

  /// Server-resolved tile states (never derived locally).
  final Set<String> _wrongIds = {};
  String? _correctId;

  /// Informational picks (offline or verdict-less): shown selected.
  final Set<String> _selectedIds = {};

  /// Buffered actions for this session (drives the offline sync path).
  final List<GameAction> _bufferedActions = [];

  /// Per-screen action sequence: action ids embed it so two taps in the
  /// same millisecond can never collide.
  int _actionSeq = 0;

  DateTime? _turnStartedAt;
  DateTime? _lastTapAt;
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _difficulty = widget.initialDifficulty.clamp(1, 3);
    _prepare(autoStart: false);
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  /// Sync the difficulty map, then load a session + board for [_difficulty].
  /// With [autoStart] the round begins immediately (replays).
  Future<void> _prepare({required bool autoStart}) async {
    _elapsedTimer?.cancel();
    setState(() {
      _loading = true;
      _offline = false;
      _noCache = false;
      _completing = false;
      _actionInProgress = false;
      _board = null;
      _sessionId = null;
      _wrongIds.clear();
      _correctId = null;
      _selectedIds.clear();
      _bufferedActions.clear();
      _actionSeq = 0;
      _elapsedSeconds = 0;
    });
    // Sync the difficulty map first (cached offline); the server board
    // already agrees when online, the cached snapshot when offline.
    await LevelConfig.refresh(_api);
    _engine.applyLevels(LevelConfig.current);
    try {
      final sessionId = await _api.startGame(
        gameType: 'odd_one_out',
        difficultyLevel: _difficulty,
      );
      final raw = await _api.getJson(
        oddOneOutBoardPath,
        query: {
          'session_id': sessionId,
          'difficulty_level': '$_difficulty',
        },
      );
      final board =
          OddOneOutBoard.fromServerJson(Map<String, dynamic>.from(raw));
      await _saveBoardCache(_difficulty, Map<String, dynamic>.from(raw));
      if (!mounted) return;
      setState(() {
        _sessionId = sessionId;
        _board = board;
        _loading = false;
        _ready = !autoStart;
      });
      if (autoStart) _beginPlay();
    } on Exception {
      // Offline: play from the cached snapshot for this level, if any.
      // Taxonomy/art is never synthesized — no cache means an explicit
      // connect-to-download state.
      final cached = await _loadBoardCache(_difficulty);
      if (!mounted) return;
      if (cached == null) {
        setState(() {
          _loading = false;
          _noCache = true;
        });
        return;
      }
      setState(() {
        _offline = true;
        _sessionId = 'offline_${DateTime.now().millisecondsSinceEpoch}';
        _board = cached;
        _loading = false;
        _ready = !autoStart;
      });
      if (autoStart) _beginPlay();
    }
  }

  Future<void> _saveBoardCache(int level, Map<String, dynamic> raw) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> all = {};
      final existing = prefs.getString(oddOneOutCacheKey);
      if (existing != null) {
        all = Map<String, dynamic>.from(jsonDecode(existing) as Map);
      }
      all['$level'] = raw;
      await prefs.setString(oddOneOutCacheKey, jsonEncode(all));
    } catch (_) {}
  }

  Future<OddOneOutBoard?> _loadBoardCache(int level) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(oddOneOutCacheKey);
      if (existing == null) return null;
      final all = Map<String, dynamic>.from(jsonDecode(existing) as Map);
      final entry = all['$level'];
      if (entry == null) return null;
      final board =
          OddOneOutBoard.fromJson(Map<String, dynamic>.from(entry as Map));
      if (board.items.isEmpty) return null; // not a compatible snapshot
      return board;
    } catch (_) {
      return null;
    }
  }

  void _beginPlay() {
    if (_board == null || _sessionId == null) return;
    setState(() {
      _ready = false;
      _turnStartedAt = DateTime.now();
      _lastTapAt = null;
      _elapsedSeconds = 0;
    });
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  Future<void> _onItemTap(OddOneOutItem item) async {
    final board = _board;
    final sessionId = _sessionId;
    if (board == null || sessionId == null) return;
    if (_loading || _ready || _completing || _noCache || _actionInProgress) {
      return;
    }
    if (_correctId != null) return; // round already resolved
    if (_wrongIds.contains(item.itemId)) return;
    if (_selectedIds.contains(item.itemId)) return;

    final now = DateTime.now();
    final responseTimeMs =
        _lastTapAt != null ? now.difference(_lastTapAt!).inMilliseconds : 0;
    _lastTapAt = now;
    final actionIndex = _bufferedActions.length;
    final action = GameAction(
      id: _nextActionId(item.itemId, now),
      sessionId: sessionId,
      actionType: 'select_odd_item',
      actionData: {'selected_item_id': item.itemId},
      responseTimeMs: responseTimeMs,
      timestamp: now,
    );
    final idempotencyKey = ApiService.actionIdempotencyKey(
      sessionId: sessionId,
      actionIndex: actionIndex,
      actionId: action.id,
    );
    _bufferedActions.add(action);

    if (_offline) {
      setState(() => _selectedIds.add(item.itemId));
      return;
    }

    setState(() => _actionInProgress = true);
    bool? verdict;
    try {
      final data = await _api.postJson(
        '${AppConfig.apiV1}/games/sessions/$sessionId/actions',
        body: {
          'action_type': 'select_odd_item',
          'action_data': action.actionData,
          'response_time_ms': responseTimeMs,
          'idempotency_key': idempotencyKey,
        },
      );
      verdict = _verdictFrom(data);
    } on Exception {
      if (!mounted) return;
      setState(() {
        _actionInProgress = false;
        _offline = true;
        _selectedIds.add(item.itemId);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _actionInProgress = false);
    if (verdict == true) {
      setState(() => _correctId = item.itemId);
      GameVisuals.positiveFeedback();
      await _completeAndShowResults();
    } else if (verdict == false) {
      setState(() => _wrongIds.add(item.itemId));
      GameVisuals.selectionFeedback();
    } else {
      setState(() => _selectedIds.add(item.itemId));
    }
  }

  /// Unique action id: timestamp + per-screen sequence, so two taps in
  /// the same millisecond can never collide.
  String _nextActionId(String itemId, DateTime now) {
    _actionSeq++;
    return 'act_${now.millisecondsSinceEpoch}_${_actionSeq}_$itemId';
  }

  List<String> _expectedActionIds() => [
        for (var index = 0; index < _bufferedActions.length; index++)
          ApiService.actionIdempotencyKey(
            sessionId: _bufferedActions[index].sessionId,
            actionIndex: index,
            actionId: _bufferedActions[index].id,
          ),
      ];

  Future<void> _ensureActionsDurable() async {
    final expectedActionIds = _expectedActionIds();
    for (var index = 0; index < _bufferedActions.length; index++) {
      final action = _bufferedActions[index];
      await _api.postJson(
        '${AppConfig.apiV1}/games/sessions/${action.sessionId}/actions',
        body: {
          'action_type': action.actionType,
          'action_data': action.actionData,
          if (action.responseTimeMs != null)
            'response_time_ms': action.responseTimeMs,
          'idempotency_key': expectedActionIds[index],
        },
      );
    }
  }

  /// Server correctness, parsed defensively; null means informational.
  /// The real backend echo is {status, event{timestamp, action_type,
  /// action_data{...server verdict + error_category...}, is_correct,
  /// response_time_ms}}, so the event envelope wins over top-level keys.
  bool? _verdictFrom(dynamic data) {
    if (data is Map) {
      final event = data['event'];
      if (event is Map) {
        final eventVerdict = event['is_correct'];
        if (eventVerdict is bool) return eventVerdict;
        final eventData = event['action_data'];
        if (eventData is Map && eventData['is_correct'] is bool) {
          return eventData['is_correct'] as bool;
        }
      }
      final direct = data['is_correct'] ?? data['correct'];
      if (direct is bool) return direct;
      final result = data['result'];
      if (result is Map && result['is_correct'] is bool) {
        return result['is_correct'] as bool;
      }
    }
    return null;
  }

  Future<void> _completeAndShowResults() async {
    final board = _board;
    final sessionId = _sessionId;
    final startedAt = _turnStartedAt;
    if (board == null || sessionId == null || startedAt == null) return;
    if (_completing) return; // never complete (or queue) twice
    _completing = true;
    _elapsedTimer?.cancel();

    final attempts = _bufferedActions.length;
    final correctCount = _correctId != null ? 1 : 0;
    final incorrectCount = _wrongIds.length;
    final avgResponse = _bufferedActions.isEmpty
        ? 0.0
        : _bufferedActions
                .map((a) => a.responseTimeMs ?? 0)
                .reduce((a, b) => a + b) /
            _bufferedActions.length;

    // ---- Adaptive engine: structured performance report (local telemetry
    // only — the server's source/reason below is the displayed authority;
    // nothing here promotes the level) ----
    final session = CognitiveGameSession(
      sessionId: sessionId,
      patientId: widget.patientId,
      gameType: 'odd_one_out',
      difficultyLevel: board.difficultyLevel,
      timeTakenInSeconds: DateTime.now().difference(startedAt).inSeconds,
      totalAttempts: attempts,
      correctMoves: correctCount,
      incorrectMoves: incorrectCount,
      isCompleted: true,
      stuckDurationSeconds: 0,
      avgResponseTimeMs: avgResponse.round(),
    );
    final report = _engine.evaluate(session);
    debugPrint('Smriti report: ${report.toJson()}');
    // TODO(sync): queue report.toJson() to the caregiver dashboard API once
    // the reports endpoint lands; fields already match its trend charts.

    GameSessionSummary? summary;
    try {
      if (!_offline) {
        await _ensureActionsDurable();
        summary = await _api.completeGame(
          sessionId,
          idempotencyKey: ApiService.completionIdempotencyKey(sessionId),
          expectedActionIds: _expectedActionIds(),
        );
        _difficulty = GameAnalyticsEngine.authoritativeNextLevel(
          currentLevel: _difficulty,
          recommendedLevel: summary.recommendedLevel,
        );
        _bufferedActions.clear(); // server holds the authoritative record
      } else {
        throw ApiException('offline session');
      }
    } on Exception catch (e) {
      debugPrint('Could not complete session online: $e');
      await _sync.enqueueGameSession(
        patientId: widget.patientId,
        session: GameSessionModel(
          id: sessionId,
          patientId: widget.patientId,
          gameType: GameType.oddOneOut,
          difficultyLevel: _difficulty,
          attempts: attempts,
          correctCount: correctCount,
          incorrectCount: incorrectCount,
          avgResponseTimeMs: avgResponse,
          startedAt: startedAt,
          completedAt: DateTime.now(),
        ),
        actions: List<GameAction>.from(_bufferedActions),
      );
    }

    if (!mounted) return;
    final resolved = summary;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Monad.parchment,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Monad.radiusCard),
            side: const BorderSide(color: Monad.ash)),
        title: const Text('Game completed', style: Monad.subheading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _correctId != null ? 'Correct!' : 'Round finished.',
              style: Monad.patientBody,
            ),
            if (board.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(board.explanation, style: Monad.monoBodySm),
            ],
            const SizedBox(height: 8),
            _resultRow('Attempts', '$attempts'),
            // Server continuation labels appear only when the summary
            // carries them (the patient endpoint returns summary fields
            // only) — never fabricated, never computed locally.
            if (resolved != null) ...[
              if (resolved.nextDifficultyLevel != null)
                _resultRow(
                    'Next level', 'Level ${resolved.nextDifficultyLevel}'),
              if (resolved.source != null)
                _resultRow('Source', resolved.source!),
              if (resolved.reason != null)
                _resultRow('Reason', resolved.reason!),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'Pending sync',
                style: Monad.monoBodySm.copyWith(color: Monad.crimson),
              ),
              const SizedBox(height: 4),
              Text(
                'Offline: result will sync when you reconnect.',
                style: Monad.monoBodySm.copyWith(color: Monad.crimson),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _restart();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Monad.monoBodySm),
          Text(value, style: Monad.monoLabel.copyWith(color: Monad.offBlack)),
        ],
      ),
    );
  }

  void _restart() {
    _elapsedTimer?.cancel();
    _prepare(autoStart: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Odd One Out'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _noCache
                ? _downloadState()
                : _ready
                    ? _readyPanel()
                    : _playPanel(),
      ),
    );
  }

  /// Pre-start panel: level picker + Start (mirrors Recall).
  Widget _readyPanel() {
    final items = LevelConfig.current.oddOneOutItems(_difficulty);
    final target =
        LevelConfig.current.targetSeconds('odd_one_out', _difficulty);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Spot the odd one out', style: Monad.subheading),
        const SizedBox(height: 8),
        Text(
          'Look at the items, then tap the one that does not belong.',
          style: Monad.patientBody,
        ),
        const SizedBox(height: 12),
        Text('$items items · ${target}s target', style: Monad.monoBody),
        if (_offline) ...[
          const SizedBox(height: 8),
          Text(
            'Pending sync',
            style: Monad.monoBodySm.copyWith(color: Monad.crimson),
          ),
        ],
        const SizedBox(height: 20),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
                value: 1,
                label: Text('Easy'),
                icon: Icon(Icons.sentiment_satisfied)),
            ButtonSegment(
                value: 2,
                label: Text('Medium'),
                icon: Icon(Icons.sentiment_neutral)),
            ButtonSegment(
                value: 3, label: Text('Hard'), icon: Icon(Icons.psychology)),
          ],
          selected: {_difficulty},
          onSelectionChanged: (s) {
            setState(() => _difficulty = s.first);
            _prepare(autoStart: false);
          },
        ),
        const SizedBox(height: 24),
        MonadPillButton(
          label: 'Start',
          variant: MonadPillVariant.primary,
          onPressed: _beginPlay,
        ),
      ],
    );
  }

  /// Offline with no compatible cached board: explicit connect state.
  /// Taxonomy/art is never synthesized.
  Widget _downloadState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Monad.smoke),
            const SizedBox(height: 12),
            const Text(
              'Connect to download to play',
              textAlign: TextAlign.center,
              style: Monad.monoBodyLg,
            ),
            const SizedBox(height: 8),
            const Text(
              'Your last board for this level will appear here.',
              textAlign: TextAlign.center,
              style: Monad.monoBodySm,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _prepare(autoStart: false),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playPanel() {
    final board = _board;
    if (board == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Server's level (display-only): the board is scoring truth.
              Text('Level ${board.difficultyLevel}', style: Monad.monoBody),
              Text(
                  'Time $_elapsedSeconds'
                  's of ${board.targetSeconds}s',
                  style: Monad.monoLabel),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('Which one does not belong?', style: Monad.monoBody),
        if (board.groupLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(board.groupLabel, style: Monad.subheading),
          ),
        if (_offline)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Pending sync',
              style: Monad.monoBodySm.copyWith(color: Monad.crimson),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: board.items.length <= 4 ? 2 : 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // Fixed row height (never aspect-driven): every tile stays
              // visible on narrow phones and wide test surfaces alike.
              mainAxisExtent: 150,
            ),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: board.items.length,
            itemBuilder: (context, index) => _tile(board.items[index]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: MonadPillButton(
            label: 'Finish',
            variant: MonadPillVariant.secondary,
            onPressed: _completeAndShowResults,
          ),
        ),
      ],
    );
  }

  /// Item tile via GameVisuals.face (no new art): state is conveyed by
  /// border + glyph + label, never color alone. Targets stay >= 48dp.
  Widget _tile(OddOneOutItem item) {
    final correct = _correctId == item.itemId;
    final wrong = _wrongIds.contains(item.itemId);
    final selected = _selectedIds.contains(item.itemId);
    return Semantics(
      button: true,
      label: item.name,
      child: GestureDetector(
        onTap: (correct || wrong || selected) ? null : () => _onItemTap(item),
        child: Container(
          key: ValueKey('ooo_tile_${item.itemId}'),
          constraints: const BoxConstraints(minHeight: 72, minWidth: 72),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: correct
                ? Monad.tintMint
                : wrong
                    ? Monad.tintCoral
                    : Monad.parchment,
            borderRadius: BorderRadius.circular(Monad.radiusMin),
            border: Border.all(
              color: correct
                  ? Monad.ash
                  : wrong
                      ? Monad.ash
                      : selected
                          ? Monad.lakeBlue
                          : Monad.ash,
              width: (correct || wrong || selected) ? 3 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (correct)
                const Icon(Icons.check_circle, color: Monad.offBlack, size: 24)
              else if (wrong)
                const Icon(Icons.close, color: Monad.offBlack, size: 24),
              GameVisuals.face(
                imageKey: item.itemId,
                label: item.name,
                iconSize: 48,
              ),
              const SizedBox(height: 4),
              Text(
                item.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Monad.patientBody.copyWith(color: Monad.offBlack),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

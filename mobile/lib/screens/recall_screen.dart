/// Number Recall — memorize a digit sequence, repeat it in order.
///
/// Flow mirrors the other games: server session + board when online, local
/// board + queued session offline, per-tap telemetry through the shared
/// pipeline, adaptive-engine report at completion. Digits are
/// language-neutral, so the game needs no content packs or artwork.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../games/game_analytics_engine.dart';
import '../games/level_config.dart';
import '../models/game_models.dart';
import '../models/shared_models.dart';
import '../services/api_service.dart';
import '../services/auth_session.dart';
import '../services/offline_sync_service.dart';
import '../services/recall_service.dart';
import '../theme/monad_theme.dart';
import '../widgets/monad/monad_pill_button.dart';

class RecallScreen extends StatefulWidget {
  final String patientId;
  final int initialDifficulty;

  const RecallScreen({
    super.key,
    required this.patientId,
    this.initialDifficulty = 1,
  });

  @override
  State<RecallScreen> createState() => _RecallScreenState();
}

class _RecallScreenState extends State<RecallScreen> {
  final ApiService _api = ApiService.instance;
  final RecallService _logic = RecallService();
  final GameAnalyticsEngine _engine = GameAnalyticsEngine.instance;

  int _difficulty = 1;
  RecallBoard? _board;
  RecallGameState? _game;
  String? _sessionId;
  bool _loading = true;
  bool _offline = false;
  bool _ready = true; // ready panel (level picker) before each first run
  int _memorizeIndex = -1;
  Timer? _memorizeTimer;

  /// Buffered actions for this session (drives the offline sync path).
  final List<GameAction> _bufferedActions = [];

  @override
  void initState() {
    super.initState();
    _difficulty = widget.initialDifficulty.clamp(1, 3);
    _prepare(autoStart: false);
  }

  @override
  void dispose() {
    _memorizeTimer?.cancel();
    super.dispose();
  }

  /// Sync the difficulty map, then load a session + board for [_difficulty].
  /// With [autoStart] the memorization phase begins immediately (replays).
  Future<void> _prepare({required bool autoStart}) async {
    setState(() {
      _loading = true;
      _offline = false;
      _board = null;
      _game = null;
      _memorizeIndex = -1;
    });
    // Sync the difficulty map first (cached offline); the server board
    // already agrees when online, the local board when offline.
    await LevelConfig.refresh(_api);
    _engine.applyLevels(LevelConfig.current);
    try {
      final sessionId = await _api.startGame(
        gameType: 'number_recall',
        difficultyLevel: _difficulty,
      );
      final board = await _api.recallBoard(difficultyLevel: _difficulty);
      if (!mounted) return;
      setState(() {
        _sessionId = sessionId;
        _board = board;
        _game = _logic.initializeGame(sessionId, board);
        _loading = false;
        _ready = !autoStart;
      });
      if (autoStart) _beginMemorize();
    } on Exception {
      // Offline-first: local board, queue the session later.
      final board = _logic.localBoard(
        difficultyLevel: _difficulty,
        levels: LevelConfig.current,
      );
      final sessionId = 'offline_${DateTime.now().millisecondsSinceEpoch}';
      if (!mounted) return;
      setState(() {
        _offline = true;
        _sessionId = sessionId;
        _board = board;
        _game = _logic.initializeGame(sessionId, board);
        _loading = false;
        _ready = !autoStart;
      });
      if (autoStart) _beginMemorize();
    }
  }

  void _beginMemorize() {
    final game = _game;
    final sessionId = _sessionId;
    if (game == null || sessionId == null) return;
    setState(() {
      _ready = false;
      _memorizeIndex = 0;
    });
    // Memorization marker (metric-free: isCorrect null counts no attempt).
    _bufferAndSend(GameAction(
      id: 'show_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: sessionId,
      actionType: RecallActions.showSequence,
      actionData: {'sequence_length': game.board.sequence.length},
      timestamp: DateTime.now(),
    ));
    final step = Duration(
        seconds: game.board.showSecondsPerItem.clamp(1, 10).toInt());
    _memorizeTimer?.cancel();
    _memorizeTimer = Timer.periodic(step, (_) {
      if (!mounted) return;
      final current = _game;
      if (current == null) return;
      final next = _memorizeIndex + 1;
      if (next >= current.board.sequence.length) {
        _memorizeTimer?.cancel();
        setState(() {
          _game = _logic.beginRecall(current);
          _memorizeIndex = -1;
        });
      } else {
        setState(() => _memorizeIndex = next);
      }
    });
  }

  void _bufferAndSend(GameAction action) {
    _bufferedActions.add(action);
    if (_offline) return; // stays buffered; flushed via sync queue on complete
    // Fire-and-forget, mirroring the other games: accept per-tap undercount
    // on flaky networks; full replay only for queued offline sessions.
    unawaited(
      _api
          .recordGameAction(
            sessionId: action.sessionId,
            actionType: action.actionType,
            actionData: action.actionData,
            isCorrect: action.isCorrect,
            responseTimeMs: action.responseTimeMs,
          )
          .catchError((_) => false),
    );
  }

  void _onDigitTap(int digit) {
    final game = _game;
    final sessionId = _sessionId;
    if (game == null || sessionId == null) return;
    final position = game.entered.length;
    final next = _logic.handleDigitTap(game, digit);
    if (next == null) return;
    setState(() => _game = next);
    final correct = next.positionCorrect[position];
    _bufferAndSend(GameAction(
      id: 'act_${DateTime.now().millisecondsSinceEpoch}_$position',
      sessionId: sessionId,
      actionType: RecallActions.recallTap,
      actionData: {
        'position': position,
        'digit': digit,
        'expected': game.board.sequence[position],
      },
      isCorrect: correct,
      responseTimeMs: next.responseTimesMs.last,
      timestamp: DateTime.now(),
    ));
    if (next.isComplete) _completeAndShowResults(next);
  }

  Future<void> _completeAndShowResults(RecallGameState finalState) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;

    // ---- Adaptive engine: build the structured performance report ----
    final session = CognitiveGameSession(
      sessionId: sessionId,
      patientId: AuthSession.instance.user?.id ?? 'demo_patient',
      gameType: 'number_recall',
      difficultyLevel: _difficulty,
      timeTakenInSeconds:
          DateTime.now().difference(finalState.gameStartedAt).inSeconds,
      totalAttempts: finalState.attempts,
      correctMoves: finalState.correctCount,
      incorrectMoves: finalState.incorrectCount,
      isCompleted: true,
      stuckDurationSeconds: 0,
      avgResponseTimeMs: finalState.avgResponseTimeMs.round(),
    );
    final report = _engine.evaluate(session);
    debugPrint('Smriti report: ${report.toJson()}');
    // TODO(sync): queue report.toJson() to the caregiver dashboard API once
    // the reports endpoint lands; fields already match its trend charts.

    GameSessionSummary? summary;
    try {
      if (!_offline) {
        summary = await _api.completeGame(sessionId);
        _bufferedActions.clear(); // server holds the authoritative record
      } else {
        throw ApiException('offline session');
      }
    } on Exception catch (e) {
      debugPrint('Could not complete session online: $e');
      await OfflineSyncService.instance.enqueueGameSession(
        patientId: AuthSession.instance.user?.id ?? '',
        session: GameSessionModel(
          id: sessionId,
          patientId: AuthSession.instance.user?.id ?? '',
          gameType: GameType.numberRecall,
          difficultyLevel: _difficulty,
          attempts: finalState.attempts,
          correctCount: finalState.correctCount,
          incorrectCount: finalState.incorrectCount,
          avgResponseTimeMs: finalState.avgResponseTimeMs,
          startedAt: finalState.gameStartedAt,
          completedAt: DateTime.now(),
        ),
        actions: List<GameAction>.from(_bufferedActions),
      );
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Monad.parchment,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Monad.radiusCard),
            side: const BorderSide(color: Monad.ash)),
        title: Text('Game completed', style: Monad.subheading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _resultRow('Accuracy',
                '${finalState.accuracyPct.toStringAsFixed(1)}%'),
            _resultRow('Digits correct',
                '${finalState.correctCount}/${finalState.board.sequence.length}'),
            _resultRow('Average response',
                '${finalState.avgResponseTimeMs.toStringAsFixed(0)} ms'),
            if (summary == null) ...[
              const SizedBox(height: 12),
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
    _memorizeTimer?.cancel();
    _bufferedActions.clear();
    _prepare(autoStart: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Number Recall'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _ready
                ? _readyPanel()
                : _gamePanel(),
      ),
    );
  }

  /// Pre-start panel: what to do + Easy/Medium/Hard picker + Start.
  Widget _readyPanel() {
    final length = LevelConfig.current.recallLength(_difficulty);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Remember the numbers', style: Monad.subheading),
        const SizedBox(height: 8),
        Text(
          'Watch $length numbers, then tap them back in the same order.',
          style: Monad.patientBody,
        ),
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
                value: 3,
                label: Text('Hard'),
                icon: Icon(Icons.psychology)),
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
          onPressed: _beginMemorize,
        ),
      ],
    );
  }

  Widget _gamePanel() {
    final game = _game;
    if (game == null) return const Center(child: CircularProgressIndicator());
    final memorizing = game.phase == RecallPhase.memorizing;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                memorizing ? 'Watch carefully…' : 'Your turn — repeat in order',
                style: Monad.monoBody,
              ),
              Text(
                '${game.entered.length}/${game.board.sequence.length}',
                style: Monad.monoLabel.copyWith(color: Monad.offBlack),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: memorizing ? _memorizeDisplay(game) : _recallDisplay(game),
          ),
        ),
        if (!memorizing) _digitPad(game),
        const SizedBox(height: 20),
      ],
    );
  }

  /// The digit currently shown (huge, language-neutral).
  Widget _memorizeDisplay(RecallGameState game) {
    final index = _memorizeIndex.clamp(0, game.board.sequence.length - 1);
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: Monad.periwinkleMist,
        borderRadius: BorderRadius.circular(Monad.radiusCard),
        border: Border.all(color: Monad.ash, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        '${game.board.sequence[index]}',
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
              color: Monad.offBlack,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  /// Digits entered so far (green = right position, red = wrong).
  Widget _recallDisplay(RecallGameState game) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      children: List.generate(game.board.sequence.length, (i) {
        final filled = i < game.entered.length;
        final right = filled && game.positionCorrect[i];
        return Container(
          width: 52,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: !filled
                ? Monad.parchment
                : (right ? Monad.tintMint : Monad.tintCoral),
            borderRadius: BorderRadius.circular(Monad.radiusMin),
            border: Border.all(color: Monad.ash, width: 1),
          ),
          child: Text(
            filled ? '${game.entered[i]}' : '·',
            style: Monad.patientBody.copyWith(
              fontSize: 28,
              color: Monad.offBlack,
            ),
          ),
        );
      }),
    );
  }

  /// 0–9 pad: patient-size targets (72px), one tap each.
  Widget _digitPad(RecallGameState game) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var d = 1; d <= 9; d++) _digitButton(d),
          const SizedBox.shrink(),
          _digitButton(0),
          const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _digitButton(int digit) {
    return GestureDetector(
      onTap: () => _onDigitTap(digit),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Monad.parchment,
          borderRadius: BorderRadius.circular(Monad.radiusMin),
          border: Border.all(color: Monad.ash, width: 1),
        ),
        child: Text(
          '$digit',
          style: Monad.patientBody.copyWith(
            fontSize: 32,
            color: Monad.offBlack,
          ),
        ),
      ),
    );
  }
}

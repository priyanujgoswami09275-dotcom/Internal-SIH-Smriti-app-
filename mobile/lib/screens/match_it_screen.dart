/// Match It — memory card-flip game backed by the backend content packs.
///
/// Flow: start session -> fetch board from server -> play locally ->
/// complete session (reports accuracy / response time to the backend).
///
/// Telemetry: every flip is buffered and POSTed fire-and-forget to
/// /games/sessions/{id}/actions; a 10s idle "stuck" event fires once per
/// episode while playing. On offline/failure the buffered actions ride the
/// existing sync queue via OfflineSyncService.
///
/// Accessibility: 4-column grid keeps touch targets >=60dp, large type,
/// semantic labels on every card, soft (silent) feedback hooks, and zero
/// punishment animation on wrong answers (cards simply flip back).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local_content_packs.dart';
import '../games/game_analytics_engine.dart';
import '../games/game_labels.dart';
import '../games/game_visuals.dart';
import '../games/level_config.dart';
import '../games/shadow_model_label.dart';
import '../models/game_models.dart';
import '../models/shared_models.dart';
import '../services/api_service.dart';
import '../services/auth_session.dart';
import '../services/match_it_service.dart';
import '../services/offline_sync_service.dart';
import '../theme/monad_theme.dart';

/// Monad palette for the memory cards (DESIGN.md tokens).
class _NERPalette {
  static const cardBack = Monad.parchment; // card resting on parchment
  static Color get matchedBg => Monad.tintMint; // ≤25% mint tint + icon + label
  static Color get matchedBorder => Monad.ash;
  static const faceBorder = Monad.lakeBlue; // flipped = the blue accent moment
  static const faceText = Monad.offBlack;
}

class MatchItScreen extends StatefulWidget {
  final String packId;
  final String packName;
  final int difficultyLevel;

  const MatchItScreen({
    super.key,
    required this.packId,
    required this.packName,
    required this.difficultyLevel,
  });

  @override
  State<MatchItScreen> createState() => _MatchItScreenState();
}

class _MatchItScreenState extends State<MatchItScreen> {
  final ApiService _api = ApiService.instance;
  final MatchItService _logic = MatchItService();
  final GameAnalyticsEngine _engine = GameAnalyticsEngine.instance;

  MatchItGameState? _game;
  String? _sessionId;
  String? _error;
  Timer? _flipReset;
  Timer? _stuckTimer;
  bool _offline = false;

  /// Set while the adaptive engine's subtle hint is showing.
  bool _hinting = false;
  int _longestStuckSeconds = 0;
  int _secondsSinceCorrect = 0;

  /// Buffered actions for this session (drives the offline sync path).
  final List<GameAction> _bufferedActions = [];

  @override
  void initState() {
    super.initState();
    _startGame();
  }

  @override
  void dispose() {
    _flipReset?.cancel();
    _stuckTimer?.cancel();
    super.dispose();
  }

  Future<void> _startGame() async {
    setState(() {
      _error = null;
      _offline = false;
    });
    // Sync the difficulty map first (cached offline); the server board
    // already agrees when online, the local pack when offline.
    await LevelConfig.refresh(_api);
    _engine.applyLevels(LevelConfig.current);
    try {
      final sessionId = await _api.startGame(
        gameType: 'match_it',
        difficultyLevel: widget.difficultyLevel,
        contentPackId: widget.packId,
      );
      final board = await _api.matchItBoard(
        packId: widget.packId,
        difficultyLevel: widget.difficultyLevel,
      );
      if (!mounted) return;
      setState(() {
        _sessionId = sessionId;
        _game = _logic.initializeGame(sessionId, board);
      });
      _armStuckTimer();
    } on Exception {
      // Offline-first: play from the local NER pack and queue the session later.
      final board = LocalContentPacks.board(
        widget.packId,
        widget.difficultyLevel,
        widget.packName,
        LevelConfig.current,
      );
      final sessionId = 'offline_${DateTime.now().millisecondsSinceEpoch}';
      if (!mounted) return;
      setState(() {
        _offline = true;
        _sessionId = sessionId;
        _game = _logic.initializeGame(sessionId, board);
      });
      _armStuckTimer();
    }
  }

  // ------------------------------------------------------------------
  // Telemetry
  // ------------------------------------------------------------------

  void _bufferAndSend(GameAction action) {
    _bufferedActions.add(action);
    if (_offline) return; // stays buffered; flushed via sync queue on complete
    // ponytail: fire-and-forget, accept per-move undercount on flaky networks;
    // full replay only when the session itself must be queued offline.
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

  void _armStuckTimer() {
    _stuckTimer?.cancel();
    final game = _game;
    if (game == null || game.state != MatchItState.playing) return;
    _stuckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = _game;
      if (current == null || current.state != MatchItState.playing) return;
      final sessionId = _sessionId;
      if (sessionId == null) return;
      _secondsSinceCorrect++;
      if (_secondsSinceCorrect > _longestStuckSeconds) {
        _longestStuckSeconds = _secondsSinceCorrect;
      }
      // Adaptive rule: >=15s stuck OR too many incorrect moves -> subtle hint.
      if (!_hinting &&
          _engine.shouldHintNow(
            secondsSinceLastCorrect: _secondsSinceCorrect,
            incorrectMoves: current.incorrectMatches,
            difficultyLevel: widget.difficultyLevel,
          )) {
        setState(() => _hinting = true);
        // One stuck telemetry event per idle episode; rearmed on next tap.
        _bufferAndSend(GameAction(
          id: 'stuck_${DateTime.now().millisecondsSinceEpoch}',
          sessionId: sessionId,
          actionType: 'stuck',
          actionData: {'stuck_duration_ms': _secondsSinceCorrect * 1000},
          timestamp: DateTime.now(),
        ));
      }
    });
  }

  void _clearHint() {
    if (_hinting) setState(() => _hinting = false);
  }

  // ------------------------------------------------------------------
  // Gameplay
  // ------------------------------------------------------------------

  void _onCardTap(MatchItCard card) {
    final game = _game;
    if (game == null || game.state != MatchItState.playing) return;
    _clearHint();
    _secondsSinceCorrect = 0;
    GameVisuals.selectionFeedback(); // soft haptic on every tap (neutral)

    final wasSecondFlip = game.flippedCards[0] != null;
    final previousCorrect = game.correctMatches;
    final next = _logic.handleCardTap(game, card.id);
    if (next == null) return;

    setState(() => _game = next);

    final sessionId = _sessionId;
    if (sessionId != null) {
      final resolved = wasSecondFlip; // second flip resolves the attempt
      final isCorrect = resolved ? next.correctMatches > previousCorrect : null;
      _bufferAndSend(GameAction(
        id: 'act_${DateTime.now().millisecondsSinceEpoch}_${card.id}',
        sessionId: sessionId,
        actionType: 'flip_card',
        actionData:
            _logic.getCardFlipActionData(card.id, card, resolved ? isCorrect : null),
        isCorrect: isCorrect,
        responseTimeMs: resolved ? next.responseTimesMs.last : null,
        timestamp: DateTime.now(),
      ));
    }
    if (next.correctMatches > previousCorrect) {
      GameVisuals.positiveFeedback(); // light haptic + soft tone on match
    }
    // Wrong answers: cards simply flip back — no punishment feedback.

    if (next.state == MatchItState.checking) {
      _stuckTimer?.cancel();
      _flipReset?.cancel();
      _flipReset = Timer(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        final reset = _logic.resetFlippedCards(_game!);
        setState(() => _game = reset);
        _armStuckTimer();
      });
    } else if (next.isComplete) {
      _stuckTimer?.cancel();
      _completeAndShowResults(next);
    } else {
      _armStuckTimer();
    }
  }

  Future<void> _completeAndShowResults(MatchItGameState finalState) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;

    // ---- Adaptive engine: build the structured performance report ----
    final session = CognitiveGameSession(
      sessionId: sessionId,
      patientId: AuthSession.instance.user?.id ?? 'demo_patient',
      gameType: 'match_it',
      difficultyLevel: widget.difficultyLevel,
      timeTakenInSeconds:
          DateTime.now().difference(finalState.gameStartedAt).inSeconds,
      totalAttempts: finalState.attempts,
      correctMoves: finalState.correctMatches,
      incorrectMoves: finalState.incorrectMatches,
      isCompleted: true,
      stuckDurationSeconds: _longestStuckSeconds,
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
          gameType: GameType.matchIt,
          difficultyLevel: widget.difficultyLevel,
          attempts: finalState.attempts,
          correctCount: finalState.correctMatches,
          incorrectCount: finalState.incorrectMatches,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Monad.radiusCard), side: const BorderSide(color: Monad.ash)),
        title: Text('Game completed', style: Monad.subheading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _resultRow('Accuracy', '${finalState.accuracyPct.toStringAsFixed(1)}%'),
            _resultRow('Pairs matched', '${finalState.matchedPairs}/${finalState.totalPairs}'),
            _resultRow('Average response', '${finalState.avgResponseTimeMs.toStringAsFixed(0)} ms'),
            if (shadowModelLabel(summary) != null) ...[
              const SizedBox(height: 8),
              Text(
                shadowModelLabel(summary)!,
                style: Monad.monoCaption.copyWith(color: Monad.indigo),
                textAlign: TextAlign.center,
              ),
            ],
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
    _flipReset?.cancel();
    _stuckTimer?.cancel();
    _bufferedActions.clear();
    setState(() {
      _game = null;
      _sessionId = null;
    });
    _startGame();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    return Scaffold(
      appBar: AppBar(
        title: Text('Match It: ${widget.packName}'),
        centerTitle: false,
        actions: [
          if (game != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${game.matchedPairs}/${game.totalPairs}',
                  style: Monad.monoLabel,
                ),
              ),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Monad.smoke),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Monad.monoBodyLg,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _startGame,
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            )
          : game == null
              ? Center(
                  child: Text(
                    GameLabels.of('en', 'common.loading'),
                    style: Monad.monoBodyLg,
                  ),
                )
              : Column(
                  children: [
                    // Persistent, unmissable home control on every screen.
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.home, size: 22),
                              label: Text(GameLabels.of('en', 'common.home')),
                              style: Monad.ghostPill(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        // Columns per spec grids: L1 2x2, L2 4x2, L3 4x3.
                        // 2 columns keeps L1 touch targets huge (>=120dp).
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: game.totalPairs <= 2 ? 2 : 4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: game.cards.length,
                        itemBuilder: (context, index) => _CardView(
                          card: game.cards[index],
                          hinting: _hinting &&
                              _isHintCard(game, game.cards[index]),
                          onTap: () => _onCardTap(game.cards[index]),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Subtle hint target: the un-flipped partner of any flipped card, or the
  /// first un-matched card when nothing is flipped (engine's "try this one").
  bool _isHintCard(MatchItGameState game, MatchItCard card) {
    if (card.isMatched || card.isFlipped) return false;
    final flippedId = game.flippedCards.whereType<String>().firstOrNull;
    if (flippedId == null) {
      // Nothing flipped: highlight one card of the first unmatched pair.
      return game.cards.indexOf(card) ==
          game.cards.indexWhere((c) => !c.isMatched && !c.isFlipped);
    }
    final flipped = game.cards.firstWhere((c) => c.id == flippedId);
    return card.pairId == flipped.pairId;
  }
}

class _CardView extends StatelessWidget {
  final MatchItCard card;
  final VoidCallback onTap;
  final bool hinting;

  const _CardView({
    required this.card,
    required this.onTap,
    this.hinting = false,
  });

  @override
  Widget build(BuildContext context) {
    final revealed = card.isFlipped || card.isMatched;
    // Stable per-pair tint so matching pairs share a hue family; state is
    // still conveyed by border + art + label, never color alone.
    final tint =
        Monad.faceTints[card.pairId.hashCode % Monad.faceTints.length];
    return Semantics(
      button: true,
      label: revealed
          ? card.labelEn
          : 'Card ${card.id}',
      child: GestureDetector(
        onTap: card.isMatched ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: card.isMatched
                ? _NERPalette.matchedBg
                : revealed
                    ? tint
                    : _NERPalette.cardBack,
            borderRadius: BorderRadius.circular(Monad.radiusCard),
            boxShadow: revealed || card.isMatched ? Monad.cardShadow : null,
            border: Border.all(
              // Card state is conveyed by border + content, never color
              // alone: back = ash hairline + motif icon, flipped = thick
              // blue, matched = mint + check glyph + label.
              color: hinting
                  ? Monad.gold
                  : card.isMatched
                      ? _NERPalette.matchedBorder
                      : revealed
                          ? _NERPalette.faceBorder
                          : Monad.ash,
              width: hinting ? 3 : (revealed || card.isMatched ? 2 : 1),
            ),
          ),
          child: Center(
            child: revealed
                ? Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (card.isMatched)
                          const Icon(Icons.check_circle,
                              color: Monad.offBlack, size: 24),
                        GameVisuals.face(
                          imageKey: card.imageKey,
                          label: card.labelEn,
                          iconSize: 48,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          card.labelLocal,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Monad.patientBody.copyWith(
                            color: _NERPalette.faceText,
                          ),
                        ),
                      ],
                    ),
                  )
                // Card back: neutral motif icon — state readable without color.
                : const Icon(Icons.self_improvement,
                    color: Monad.smoke, size: 40),
          ),
        ),
      ),
    );
  }
}

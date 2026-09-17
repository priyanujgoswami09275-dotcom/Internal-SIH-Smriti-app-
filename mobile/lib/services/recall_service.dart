/// Number Recall game logic and state management.
///
/// Memorize a digit sequence, then repeat it in order on a 0–9 pad.
/// Pure logic (no Flutter imports) mirroring match_it_service patterns.
library;

import 'dart:math';

import '../games/level_config.dart';
import '../models/game_models.dart';

/// Action types mirrored from backend recall_service.RECALL_ACTION_TYPES.
/// show_sequence ships with isCorrect null (never counts as an attempt);
/// each recall_tap is one scored attempt.
class RecallActions {
  static const String showSequence = 'show_sequence';
  static const String recallTap = 'recall_tap';
}

enum RecallPhase { memorizing, recalling, completed }

/// Immutable game state for one Number Recall turn.
class RecallGameState {
  final String sessionId;
  final RecallBoard board;
  final RecallPhase phase;
  final List<int> entered;
  final List<bool> positionCorrect;
  final List<int> responseTimesMs;
  final DateTime? lastTapAt;
  final DateTime gameStartedAt;

  const RecallGameState({
    required this.sessionId,
    required this.board,
    required this.phase,
    required this.entered,
    required this.positionCorrect,
    required this.responseTimesMs,
    required this.lastTapAt,
    required this.gameStartedAt,
  });

  int get attempts => entered.length;

  int get correctCount => positionCorrect.where((c) => c).length;

  int get incorrectCount => positionCorrect.where((c) => !c).length;

  bool get isComplete => phase == RecallPhase.completed;

  double get accuracyPct =>
      attempts > 0 ? (correctCount / attempts) * 100 : 0.0;

  double get avgResponseTimeMs => responseTimesMs.isEmpty
      ? 0.0
      : responseTimesMs.reduce((a, b) => a + b) / responseTimesMs.length;

  RecallGameState copyWith({
    RecallPhase? phase,
    List<int>? entered,
    List<bool>? positionCorrect,
    List<int>? responseTimesMs,
    DateTime? lastTapAt,
  }) {
    return RecallGameState(
      sessionId: sessionId,
      board: board,
      phase: phase ?? this.phase,
      entered: entered ?? this.entered,
      positionCorrect: positionCorrect ?? this.positionCorrect,
      responseTimesMs: responseTimesMs ?? this.responseTimesMs,
      lastTapAt: lastTapAt ?? this.lastTapAt,
      gameStartedAt: gameStartedAt,
    );
  }
}

/// Pure game logic for Number Recall.
class RecallService {
  final Random _random = Random();

  /// Local digit sequence (offline fallback). Length comes from
  /// [LevelConfig] (server-synced, bundled fallback); digits are unique
  /// within a sequence for fairness.
  List<int> generateSequence({
    required int difficultyLevel,
    LevelConfig? levels,
  }) {
    final length =
        (levels ?? LevelConfig.bundled).recallLength(difficultyLevel);
    final pool = List<int>.generate(10, (i) => i)..shuffle(_random);
    return pool.take(length).toList();
  }

  /// Local board (offline fallback) mirroring the server board shape.
  RecallBoard localBoard({
    required int difficultyLevel,
    LevelConfig? levels,
  }) {
    final cfg = levels ?? LevelConfig.bundled;
    final sequence = generateSequence(
      difficultyLevel: difficultyLevel,
      levels: cfg,
    );
    return RecallBoard(
      difficultyLevel: difficultyLevel,
      sequenceLength: sequence.length,
      showSecondsPerItem: cfg.recallShowSeconds(difficultyLevel),
      sequence: sequence,
      generatedAt: DateTime.now(),
    );
  }

  /// Initialize state from a board (server or local).
  RecallGameState initializeGame(String sessionId, RecallBoard board) {
    return RecallGameState(
      sessionId: sessionId,
      board: board,
      phase: RecallPhase.memorizing,
      entered: const [],
      positionCorrect: const [],
      responseTimesMs: const [],
      lastTapAt: null,
      gameStartedAt: DateTime.now(),
    );
  }

  /// Move to the recall phase after memorization finishes.
  RecallGameState beginRecall(RecallGameState current) {
    if (current.phase != RecallPhase.memorizing) return current;
    return current.copyWith(phase: RecallPhase.recalling);
  }

  /// Handle a pad tap — returns new state, or null when the tap is invalid
  /// (wrong phase, or the sequence is already complete).
  RecallGameState? handleDigitTap(
    RecallGameState current,
    int digit, {
    DateTime? now,
  }) {
    if (current.phase != RecallPhase.recalling) return null;
    if (current.entered.length >= current.board.sequence.length) return null;

    final at = now ?? DateTime.now();
    final position = current.entered.length;
    final correct = digit == current.board.sequence[position];
    final responseTime = current.lastTapAt != null
        ? at.difference(current.lastTapAt!).inMilliseconds
        : 0;

    final entered = [...current.entered, digit];
    final done = entered.length >= current.board.sequence.length;
    return current.copyWith(
      phase: done ? RecallPhase.completed : RecallPhase.recalling,
      entered: entered,
      positionCorrect: [...current.positionCorrect, correct],
      responseTimesMs: [...current.responseTimesMs, responseTime],
      lastTapAt: at,
    );
  }
}

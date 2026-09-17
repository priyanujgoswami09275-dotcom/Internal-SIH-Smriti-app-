/// Routine Sequencing game logic and state management.
///
/// The player is shown shuffled daily-routine steps and must tap them in the
/// correct chronological order (wake up -> bathe -> eat -> medicine -> sleep).
library;

import 'dart:math';

import '../games/level_config.dart';
import '../models/game_models.dart';

/// Game state for Daily Routine Sequencing.
enum RoutineState { loading, playing, completed }

/// State for a single Routine Sequencing game session.
class RoutineGameState {
  final String sessionId;
  final RoutineBoard board;
  final RoutineState state;
  final List<RoutineStep> shuffledSteps;
  final int stepsPlaced;
  final int correctPlacements;
  final int errors;
  final List<int> placementOrder; // Which correct-position each placed step had
  final List<int> responseTimesMs; // Response time for each placement attempt
  final DateTime gameStartedAt;
  final DateTime? lastPlacementAt;
  final String? lastError;

  const RoutineGameState({
    required this.sessionId,
    required this.board,
    this.state = RoutineState.loading,
    required this.shuffledSteps,
    this.stepsPlaced = 0,
    this.correctPlacements = 0,
    this.errors = 0,
    this.placementOrder = const [],
    this.responseTimesMs = const [],
    required this.gameStartedAt,
    this.lastPlacementAt,
    this.lastError,
  });

  int get totalSteps => board.stepCount;

  bool get isComplete => stepsPlaced >= totalSteps;

  bool get canPlaceMore => stepsPlaced < totalSteps;

  double get accuracyPct =>
      totalSteps > 0 ? (correctPlacements / totalSteps) * 100 : 0.0;

  double get avgResponseTimeMs {
    if (responseTimesMs.isEmpty) return 0;
    final validTimes = responseTimesMs.where((t) => t > 0).toList();
    if (validTimes.isEmpty) return 0;
    return validTimes.reduce((a, b) => a + b) / validTimes.length;
  }

  bool get isPerfect => isComplete && correctPlacements == totalSteps;

  RoutineGameState copyWith({
    RoutineState? state,
    List<RoutineStep>? shuffledSteps,
    int? stepsPlaced,
    int? correctPlacements,
    int? errors,
    List<int>? placementOrder,
    List<int>? responseTimesMs,
    DateTime? lastPlacementAt,
    String? lastError,
  }) {
    return RoutineGameState(
      sessionId: sessionId,
      board: board,
      state: state ?? this.state,
      shuffledSteps: shuffledSteps ?? this.shuffledSteps,
      stepsPlaced: stepsPlaced ?? this.stepsPlaced,
      correctPlacements: correctPlacements ?? this.correctPlacements,
      errors: errors ?? this.errors,
      placementOrder: placementOrder ?? this.placementOrder,
      responseTimesMs: responseTimesMs ?? this.responseTimesMs,
      gameStartedAt: gameStartedAt,
      lastPlacementAt: lastPlacementAt ?? this.lastPlacementAt,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// Pure game logic for Routine Sequencing.
class RoutineService {
  final Random _random = Random();

  /// Build a local board from routine steps (offline fallback).
  /// Step count comes from [LevelConfig] (server-synced, bundled fallback).
  RoutineBoard generateBoard({
    required int difficultyLevel,
    required List<RoutineStep> steps,
    LevelConfig? levels,
  }) {
    final stepCount =
        (levels ?? LevelConfig.bundled).routineSteps(difficultyLevel);

    final pool = List<RoutineStep>.from(steps)..shuffle(_random);
    final chosen = pool.take(stepCount).toList()..shuffle(_random);
    final byTime = List<RoutineStep>.from(steps)
      ..sort((a, b) => a.time.compareTo(b.time));
    final correctSequence = chosen
        .map((s) => byTime.indexWhere((t) => t.stepId == s.stepId))
        .map((i) => byTime[i].stepId)
        .toList();

    return RoutineBoard(
      difficultyLevel: difficultyLevel,
      stepCount: chosen.length,
      hasHints: difficultyLevel == 1,
      hasIcons: difficultyLevel <= 2,
      shuffledItems: chosen,
      correctSequence: correctSequence,
    );
  }

  RoutineGameState initializeGame(String sessionId, RoutineBoard board) {
    return RoutineGameState(
      sessionId: sessionId,
      board: board,
      state: RoutineState.playing,
      shuffledSteps: board.shuffledItems,
      gameStartedAt: DateTime.now(),
    );
  }

  /// Tap a step: places it at the next slot. Correct only when it matches the
  /// expected step for the current position.
  RoutineGameState? handleStepPlacement(
    RoutineGameState state,
    RoutineStep step,
  ) {
    if (state.state != RoutineState.playing) return null;
    if (!state.canPlaceMore) return null;

    final now = DateTime.now();
    final responseTimeMs = now
        .difference(state.lastPlacementAt ?? state.gameStartedAt)
        .inMilliseconds;

    final expectedId = state.board.correctSequence[state.stepsPlaced];
    final isCorrect = step.stepId == expectedId;

    final nextPlaced = state.stepsPlaced + 1;
    final nextCorrect = state.correctPlacements + (isCorrect ? 1 : 0);
    final nextErrors = state.errors + (isCorrect ? 0 : 1);

    final updatedSteps = state.shuffledSteps
        .map((s) => s.stepId == step.stepId ? s.copyWith(isSelected: true) : s)
        .toList();

    return state.copyWith(
      shuffledSteps: updatedSteps,
      stepsPlaced: nextPlaced,
      correctPlacements: nextCorrect,
      errors: nextErrors,
      placementOrder: [
        ...state.placementOrder,
        state.board.correctSequence.indexOf(step.stepId),
      ],
      responseTimesMs: [...state.responseTimesMs, responseTimeMs],
      lastPlacementAt: now,
      state: nextPlaced >= state.totalSteps
          ? RoutineState.completed
          : RoutineState.playing,
    );
  }

  /// Final result after completing the sequence.
  RoutineValidationResult getValidationResult(RoutineGameState state) {
    final errors = <RoutineError>[];
    for (var i = 0; i < state.board.correctSequence.length; i++) {
      final placed = i < state.placementOrder.length ? state.placementOrder[i] : null;
      if (placed == null || placed != i) {
        final expectedId = state.board.correctSequence[i];
        final submittedId = (placed != null && placed < state.board.correctSequence.length)
            ? state.board.correctSequence[placed]
            : null;
        errors.add(RoutineError(
          position: i,
          expected: expectedId,
          submitted: submittedId ?? '—',
        ));
      }
    }
    return RoutineValidationResult(
      isPerfect: state.isPerfect,
      accuracyPct: state.accuracyPct,
      correctCount: state.correctPlacements,
      totalCount: state.totalSteps,
      errors: errors,
    );
  }
}

/// Match It game logic and state management.

import 'dart:math';
import '../games/level_config.dart';
import '../models/game_models.dart';

/// Game state for Match It.
enum MatchItState {
  loading,
  playing,
  checking,
  completed,
  error,
}

/// State for a single Match It game session.
class MatchItGameState {
  final String sessionId;
  final MatchItBoard board;
  final MatchItState state;
  final List<MatchItCard> cards;
  final List<MatchItCard?> flippedCards; // Currently flipped (max 2)
  final int matchedPairs;
  final int totalPairs;
  final int attempts;
  final int correctMatches;
  final int incorrectMatches;
  final List<int?> responseTimesMs; // Response time for each match attempt
  final DateTime gameStartedAt;
  final DateTime? lastCardFlipAt;
  final String? lastError;

  const MatchItGameState({
    required this.sessionId,
    required this.board,
    this.state = MatchItState.loading,
    required this.cards,
    this.flippedCards = const [null, null],
    this.matchedPairs = 0,
    required this.totalPairs,
    this.attempts = 0,
    this.correctMatches = 0,
    this.incorrectMatches = 0,
    this.responseTimesMs = const [],
    required this.gameStartedAt,
    this.lastCardFlipAt,
    this.lastError,
  });

  MatchItGameState copyWith({
    String? sessionId,
    MatchItBoard? board,
    MatchItState? state,
    List<MatchItCard>? cards,
    List<MatchItCard?>? flippedCards,
    int? matchedPairs,
    int? totalPairs,
    int? attempts,
    int? correctMatches,
    int? incorrectMatches,
    List<int?>? responseTimesMs,
    DateTime? gameStartedAt,
    DateTime? lastCardFlipAt,
    String? lastError,
  }) {
    return MatchItGameState(
      sessionId: sessionId ?? this.sessionId,
      board: board ?? this.board,
      state: state ?? this.state,
      cards: cards ?? this.cards,
      flippedCards: flippedCards ?? this.flippedCards,
      matchedPairs: matchedPairs ?? this.matchedPairs,
      totalPairs: totalPairs ?? this.totalPairs,
      attempts: attempts ?? this.attempts,
      correctMatches: correctMatches ?? this.correctMatches,
      incorrectMatches: incorrectMatches ?? this.incorrectMatches,
      responseTimesMs: responseTimesMs ?? this.responseTimesMs,
      gameStartedAt: gameStartedAt ?? this.gameStartedAt,
      lastCardFlipAt: lastCardFlipAt ?? this.lastCardFlipAt,
      lastError: lastError ?? this.lastError,
    );
  }

  bool get isComplete => matchedPairs >= totalPairs;
  double get accuracyPct =>
      attempts > 0 ? (correctMatches / attempts) * 100 : 0.0;
  double get avgResponseTimeMs {
    if (responseTimesMs.isEmpty) return 0;
    final validTimes =
        responseTimesMs.where((t) => t != null && t > 0).toList();
    if (validTimes.isEmpty) return 0;
    return validTimes.map((t) => t!).reduce((a, b) => a + b) /
        validTimes.length;
  }
}

/// Service for Match It game logic.
class MatchItService {
  final Random _random = Random();

  /// Generate a shuffled board from content pack items.
  /// Pair count comes from [LevelConfig] (server-synced, bundled fallback).
  MatchItBoard generateBoard({
    required String packId,
    required String packName,
    required int difficultyLevel,
    required List<Map<String, String>> items,
    LevelConfig? levels,
  }) {
    final pairCount =
        (levels ?? LevelConfig.bundled).matchPairs(difficultyLevel);

    // Select random items for this game
    final shuffledItems = List<Map<String, String>>.from(items)
      ..shuffle(_random);
    final selectedItems = shuffledItems.take(pairCount).toList();

    // Create cards
    final cards = <MatchItCard>[];
    for (int i = 0; i < selectedItems.length; i++) {
      final item = selectedItems[i];
      final pairId = 'pair_${i}_${item['image_key']}';

      // Front and back of each pair
      cards.add(MatchItCard(
        id: '${pairId}_a',
        pairId: pairId,
        imageKey: item['image_key']!,
        labelEn: item['label_en']!,
        labelLocal: item['label_local'] ?? item['label_en']!,
      ));
      cards.add(MatchItCard(
        id: '${pairId}_b',
        pairId: pairId,
        imageKey: item['image_key']!,
        labelEn: item['label_en']!,
        labelLocal: item['label_local'] ?? item['label_en']!,
      ));
    }

    // Shuffle cards
    cards.shuffle(_random);

    return MatchItBoard(
      packId: packId,
      packName: packName,
      difficultyLevel: difficultyLevel,
      pairCount: pairCount,
      totalCards: cards.length,
      cards: cards,
      generatedAt: DateTime.now(),
    );
  }

  /// Initialize game state from a board.
  MatchItGameState initializeGame(String sessionId, MatchItBoard board) {
    return MatchItGameState(
      sessionId: sessionId,
      board: board,
      state: MatchItState.playing,
      cards: board.cards,
      totalPairs: board.pairCount,
      gameStartedAt: DateTime.now(),
    );
  }

  /// Handle a card tap - returns new state.
  MatchItGameState? handleCardTap(
      MatchItGameState currentState, String cardId) {
    if (currentState.state != MatchItState.playing) return null;
    if (currentState.isComplete) return null;

    // Find the card
    final cardIndex = currentState.cards.indexWhere((c) => c.id == cardId);
    if (cardIndex < 0) return null;

    final card = currentState.cards[cardIndex];
    if (card.isFlipped || card.isMatched)
      return null; // Already flipped or matched

    // Flip the card
    final now = DateTime.now();
    final updatedCards = List<MatchItCard>.from(currentState.cards);
    updatedCards[cardIndex] = card.copyWith(isFlipped: true);

    final flipped = <MatchItCard?>[card.copyWith(isFlipped: true), null];

    // Check if this is the second card
    if (currentState.flippedCards[0] != null) {
      // Two cards are now flipped - check for match
      final firstCard = updatedCards.firstWhere(
        (c) => c.id == currentState.flippedCards[0]!.id,
      );
      flipped[0] = firstCard;

      // Calculate response time
      final responseTime = currentState.lastCardFlipAt != null
          ? now.difference(currentState.lastCardFlipAt!).inMilliseconds
          : 0;

      final isMatch = firstCard.pairId == card.pairId;
      final newAttempts = currentState.attempts + 1;
      final responseTimes = [...currentState.responseTimesMs, responseTime];

      if (isMatch) {
        // Mark both as matched
        final idx1 = updatedCards.indexWhere((c) => c.id == firstCard.id);
        final idx2 = cardIndex;
        updatedCards[idx1] = firstCard.copyWith(isMatched: true);
        updatedCards[idx2] = updatedCards[idx2].copyWith(isMatched: true);

        final newMatchedPairs = currentState.matchedPairs + 1;
        final isComplete = newMatchedPairs >= currentState.totalPairs;

        return currentState.copyWith(
          cards: updatedCards,
          flippedCards: [null, null],
          matchedPairs: newMatchedPairs,
          attempts: newAttempts,
          correctMatches: currentState.correctMatches + 1,
          responseTimesMs: responseTimes,
          state: isComplete ? MatchItState.completed : MatchItState.playing,
          lastCardFlipAt: now,
        );
      } else {
        // No match - flip back after delay
        return currentState.copyWith(
          cards: updatedCards,
          flippedCards: flipped,
          attempts: newAttempts,
          incorrectMatches: currentState.incorrectMatches + 1,
          responseTimesMs: responseTimes,
          state: MatchItState.checking,
          lastCardFlipAt: now,
        );
      }
    } else {
      // First card of a new attempt
      return currentState.copyWith(
        cards: updatedCards,
        flippedCards: [card.copyWith(isFlipped: true), null],
        lastCardFlipAt: now,
      );
    }
  }

  /// Reset unmatched flipped cards (after delay).
  MatchItGameState resetFlippedCards(MatchItGameState currentState) {
    if (currentState.state != MatchItState.checking) return currentState;

    final updatedCards = currentState.cards.map((c) {
      if (c.isFlipped && !c.isMatched) {
        return c.copyWith(isFlipped: false);
      }
      return c;
    }).toList();

    return currentState.copyWith(
      cards: updatedCards,
      flippedCards: [null, null],
      state: MatchItState.playing,
    );
  }

  /// Get action data for logging.
  Map<String, dynamic> getCardFlipActionData(String cardId, MatchItCard card) {
    return {
      'card_id': cardId,
      'pair_id': card.pairId,
      'image_key': card.imageKey,
    };
  }

  /// Generate completion metrics for logging.
  Map<String, dynamic> getCompletionMetrics(MatchItGameState state) {
    return {
      'total_pairs': state.totalPairs,
      'matched_pairs': state.matchedPairs,
      'attempts': state.attempts,
      'correct_matches': state.correctMatches,
      'incorrect_matches': state.incorrectMatches,
      'accuracy_pct': state.accuracyPct,
      'avg_response_time_ms': state.avgResponseTimeMs,
      'game_duration_ms':
          DateTime.now().difference(state.gameStartedAt).inMilliseconds,
    };
  }
}

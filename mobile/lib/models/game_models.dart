/// A single card in the Match It memory game.
class MatchItCard {
  final String id;
  final String pairId;
  final String imageKey;
  final String labelEn;
  final String labelLocal;
  final bool isFlipped;
  final bool isMatched;

  const MatchItCard({
    required this.id,
    required this.pairId,
    required this.imageKey,
    required this.labelEn,
    required this.labelLocal,
    this.isFlipped = false,
    this.isMatched = false,
  });

  MatchItCard copyWith({
    String? id,
    String? pairId,
    String? imageKey,
    String? labelEn,
    String? labelLocal,
    bool? isFlipped,
    bool? isMatched,
  }) {
    return MatchItCard(
      id: id ?? this.id,
      pairId: pairId ?? this.pairId,
      imageKey: imageKey ?? this.imageKey,
      labelEn: labelEn ?? this.labelEn,
      labelLocal: labelLocal ?? this.labelLocal,
      isFlipped: isFlipped ?? this.isFlipped,
      isMatched: isMatched ?? this.isMatched,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pair_id': pairId,
        'image_key': imageKey,
        'label_en': labelEn,
        'label_local': labelLocal,
        'is_flipped': isFlipped,
        'is_matched': isMatched,
      };

  factory MatchItCard.fromJson(Map<String, dynamic> json) => MatchItCard(
        id: json['id'],
        pairId: json['pair_id'],
        imageKey: json['image_key'],
        labelEn: json['label_en'],
        labelLocal: json['label_local'] ?? json['label_en'],
        isFlipped: json['is_flipped'] ?? false,
        isMatched: json['is_matched'] ?? false,
      );
}

/// Normalize a server card to a registry key: prefer item_id, else the
/// image filename stem, else the English name.
String _artKeyFor(String itemId, String? imageUrl, String nameEn) {
  if (itemId.isNotEmpty) return itemId;
  if (imageUrl != null && imageUrl.isNotEmpty) {
    final stem = imageUrl.split('/').last.split('.').first;
    if (stem.isNotEmpty) return stem;
  }
  return nameEn;
}

/// Represents a generated Match It board configuration.
class MatchItBoard {
  final String packId;
  final String packName;
  final int difficultyLevel;
  final int pairCount;
  final int totalCards;
  final List<MatchItCard> cards;
  final DateTime generatedAt;

  const MatchItBoard({
    required this.packId,
    required this.packName,
    required this.difficultyLevel,
    required this.pairCount,
    required this.totalCards,
    required this.cards,
    required this.generatedAt,
  });

  factory MatchItBoard.fromJson(Map<String, dynamic> json) {
    final cardsList =
        (json['cards'] as List).map((c) => MatchItCard.fromJson(c)).toList();
    return MatchItBoard(
      packId: json['pack_id'] as String,
      packName: json['pack_name'] as String,
      difficultyLevel: json['difficulty_level'] as int? ?? 1,
      pairCount: json['pair_count'] as int? ?? (cardsList.length ~/ 2),
      totalCards: json['total_cards'] as int? ?? cardsList.length,
      cards: cardsList,
      generatedAt: DateTime.now(),
    );
  }

  /// Parse a board from the backend content-packs/{id}/board endpoint whose
  /// cards carry `card_id`/`item_id`/`name_en`/`name_as`/`image_url`.
  factory MatchItBoard.fromServerJson(Map<String, dynamic> json) {
    final cards = <MatchItCard>[];
    final rawCards = (json['cards'] as List? ?? const []);
    for (final raw in rawCards) {
      final c = ServerMatchItCard.fromJson(raw as Map<String, dynamic>);
      cards.add(MatchItCard(
        id: '${c.cardId}',
        pairId: c.itemId,
        // Server sends item_id + full asset path; the art/icon registries
        // are keyed by bare item id — normalize here so every caller (art,
        // icons, pair tinting) resolves. Fixes online boards rendering the
        // help-outline fallback while offline boards showed real art.
        imageKey: _artKeyFor(c.itemId, c.imageUrl, c.nameEn),
        labelEn: c.nameEn,
        labelLocal: c.nameAs.isEmpty ? c.nameEn : c.nameAs,
      ));
    }
    return MatchItBoard(
      packId: json['pack_id'] as String? ?? '',
      packName: json['pack_name'] as String? ?? 'Match It',
      difficultyLevel: json['difficulty_level'] as int? ?? 1,
      pairCount: json['pair_count'] as int? ?? (cards.length ~/ 2),
      totalCards: json['total_cards'] as int? ?? cards.length,
      cards: cards,
      generatedAt: DateTime.now(),
    );
  }
}

/// A step in the daily routine sequencing game.
class RoutineStep {
  final String stepId;
  final int order;
  final String time;
  final String titleEn;
  final String? titleAs;
  final String? titleBn;
  final String? titleHi;
  final String? icon;
  final String? hint;

  const RoutineStep({
    required this.stepId,
    required this.order,
    required this.time,
    required this.titleEn,
    this.titleAs,
    this.titleBn,
    this.titleHi,
    this.icon,
    this.hint,
    this.isSelected = false,
  });

  final bool isSelected;

  RoutineStep copyWith({bool? isSelected}) {
    return RoutineStep(
      stepId: stepId,
      order: order,
      time: time,
      titleEn: titleEn,
      titleAs: titleAs,
      titleBn: titleBn,
      titleHi: titleHi,
      icon: icon,
      hint: hint,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  /// Get localized title based on language preference.
  String getTitle(String languageCode) {
    switch (languageCode) {
      case 'assamese':
        return titleAs ?? titleEn;
      case 'bengali':
        return titleBn ?? titleEn;
      case 'hindi':
        return titleHi ?? titleEn;
      default:
        return titleEn;
    }
  }

  factory RoutineStep.fromJson(Map<String, dynamic> json) => RoutineStep(
        stepId: json['step_id'],
        order: json['order'],
        time: json['time'],
        titleEn: json['title_en'],
        titleAs: json['title_as'],
        titleBn: json['title_bn'],
        titleHi: json['title_hi'],
        icon: json['icon'],
        hint: json['hint'],
      );

  Map<String, dynamic> toJson() => {
        'step_id': stepId,
        'order': order,
        'time': time,
        'title_en': titleEn,
        'title_as': titleAs,
        'title_bn': titleBn,
        'title_hi': titleHi,
        'icon': icon,
        'hint': hint,
      };
}

/// A single card generated by the backend Match It board endpoint.
class ServerMatchItCard {
  final int cardId;
  final String itemId;
  final String nameEn;
  final String nameAs;
  final String? imageUrl;

  const ServerMatchItCard({
    required this.cardId,
    required this.itemId,
    required this.nameEn,
    required this.nameAs,
    this.imageUrl,
  });

  factory ServerMatchItCard.fromJson(Map<String, dynamic> json) =>
      ServerMatchItCard(
        cardId: json['card_id'] as int? ?? 0,
        itemId: json['item_id'] as String? ?? '',
        nameEn: json['name_en'] as String? ?? '',
        nameAs: json['name_as'] as String? ?? json['name_en'] as String? ?? '',
        imageUrl: json['image_url'] as String?,
      );
}

/// Represents a generated routine sequencing board configuration.
class RoutineBoard {
  final int difficultyLevel;
  final int stepCount;
  final bool hasHints;
  final bool hasIcons;
  final List<RoutineStep> shuffledItems;
  final List<String> correctSequence;

  const RoutineBoard({
    required this.difficultyLevel,
    required this.stepCount,
    required this.hasHints,
    required this.hasIcons,
    required this.shuffledItems,
    required this.correctSequence,
  });

  factory RoutineBoard.fromJson(Map<String, dynamic> json) {
    final shuffled = (json['shuffled_items'] as List)
        .map((s) => RoutineStep.fromJson(s))
        .toList();
    return RoutineBoard(
      difficultyLevel: json['difficulty_level'] as int? ?? 1,
      stepCount: json['step_count'] as int? ?? shuffled.length,
      hasHints: json['has_hints'] as bool? ?? false,
      hasIcons: json['has_icons'] as bool? ?? false,
      shuffledItems: shuffled,
      correctSequence: List<String>.from(json['correct_sequence'] as List),
    );
  }

  /// Parse a board from the backend routine/board endpoint. Puzzle items use
  /// `approx_time` (no `time`/`order`), so they are adapted to [RoutineStep].
  factory RoutineBoard.fromServerJson(Map<String, dynamic> json) {
    final difficulty = json['difficulty_level'] as int? ?? 1;
    final rawItems = (json['shuffled_items'] as List? ?? const []);
    final steps = <RoutineStep>[];
    for (var i = 0; i < rawItems.length; i++) {
      final s = rawItems[i] as Map<String, dynamic>;
      steps.add(RoutineStep(
        stepId: s['step_id'] as String,
        order: i + 1,
        time: s['approx_time'] as String? ?? '',
        titleEn: s['title_en'] as String? ?? '',
        titleAs: s['title_as'] as String?,
        titleBn: s['title_bn'] as String?,
        titleHi: s['title_hi'] as String?,
        icon: s['icon'] as String?,
        hint: s['hint'] as String?,
      ));
    }
    return RoutineBoard(
      difficultyLevel: difficulty,
      stepCount: json['step_count'] as int? ?? steps.length,
      hasHints: json['has_hints'] as bool? ?? (difficulty == 1),
      hasIcons: json['has_icons'] as bool? ?? (difficulty <= 2),
      shuffledItems: steps,
      correctSequence: List<String>.from(json['correct_sequence'] as List),
    );
  }
}

/// Result of validating a routine sequence submission.
class RoutineValidationResult {
  final bool isPerfect;
  final double accuracyPct;
  final int correctCount;
  final int totalCount;
  final List<RoutineError> errors;

  const RoutineValidationResult({
    required this.isPerfect,
    required this.accuracyPct,
    required this.correctCount,
    required this.totalCount,
    required this.errors,
  });

  factory RoutineValidationResult.fromJson(Map<String, dynamic> json) {
    final errorsList =
        (json['errors'] as List).map((e) => RoutineError.fromJson(e)).toList();
    return RoutineValidationResult(
      isPerfect: json['is_perfect'],
      accuracyPct: (json['accuracy_pct'] as num).toDouble(),
      correctCount: json['correct_count'],
      totalCount: json['total_count'],
      errors: errorsList,
    );
  }
}

/// An error in the routine sequence submission.
class RoutineError {
  final int position;
  final String expected;
  final String submitted;

  const RoutineError({
    required this.position,
    required this.expected,
    required this.submitted,
  });

  factory RoutineError.fromJson(Map<String, dynamic> json) => RoutineError(
        position: json['position'],
        expected: json['expected'],
        submitted: json['submitted'],
      );
}

/// A game action/event for logging.
class GameAction {
  final String id;
  final String sessionId;
  final String actionType;
  final Map<String, dynamic> actionData;
  final bool? isCorrect;
  final int? responseTimeMs;
  final DateTime timestamp;
  final bool synced;

  const GameAction({
    required this.id,
    required this.sessionId,
    required this.actionType,
    required this.actionData,
    this.isCorrect,
    this.responseTimeMs,
    required this.timestamp,
    this.synced = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': sessionId,
        'action_type': actionType,
        'action_data': actionData,
        'is_correct': isCorrect,
        'response_time_ms': responseTimeMs,
        'timestamp': timestamp.toIso8601String(),
        'synced': synced,
      };

  factory GameAction.fromJson(Map<String, dynamic> json) => GameAction(
        id: json['id'] ?? json['id'],
        sessionId: json['session_id'] ?? json['sessionId'],
        actionType: json['action_type'] ?? json['actionType'],
        actionData: Map<String, dynamic>.from(
            json['action_data'] ?? json['actionData'] ?? {}),
        isCorrect: json['is_correct'] ?? json['isCorrect'],
        responseTimeMs: json['response_time_ms'] ?? json['responseTimeMs'],
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'])
            : DateTime.now(),
        synced: json['synced'] ?? false,
      );
}

/// Sync queue item for offline-first operations.
class SyncQueueItem {
  final String id;
  final String? patientId;
  final String? accountId;
  final String resourceType;
  final String operation;
  final String resourceId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? lastRetryAt;
  final String? lastError;

  const SyncQueueItem({
    required this.id,
    this.patientId,
    this.accountId,
    required this.resourceType,
    required this.operation,
    required this.resourceId,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.lastRetryAt,
    this.lastError,
  });

  String? get idempotencyKey {
    final value = payload['idempotency_key'];
    return value is String && value.isNotEmpty ? value : null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (patientId != null && patientId!.isNotEmpty) 'patient_id': patientId,
        if (accountId != null && accountId!.isNotEmpty) 'account_id': accountId,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
        'resource_type': resourceType,
        'operation': operation,
        'resource_id': resourceId,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'retry_count': retryCount,
        'last_retry_at': lastRetryAt?.toIso8601String(),
        'last_error': lastError,
      };

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) => SyncQueueItem(
        id: json['id'] as String,
        patientId: json['patient_id'] as String?,
        accountId: json['account_id'] as String?,
        resourceType: json['resource_type'] as String,
        operation: json['operation'] as String,
        resourceId: json['resource_id'] as String,
        payload: Map<String, dynamic>.from(json['payload'] ?? {}),
        createdAt: DateTime.parse(json['created_at'] as String),
        retryCount: json['retry_count'] as int? ?? 0,
        lastRetryAt: json['last_retry_at'] != null
            ? DateTime.parse(json['last_retry_at'] as String)
            : null,
        lastError: json['last_error'] as String?,
      );
}

/// Session summary returned after completing a game.
class GameSessionSummary {
  final String sessionId;
  final String gameType;
  final int difficultyLevel;
  final int totalAttempts;
  final int correctCount;
  final int incorrectCount;
  final double accuracyPct;
  final double avgResponseTimeMs;
  final DateTime startedAt;
  final DateTime completedAt;
  final int? recommendedLevel;
  final String difficultyReason;
  final String? difficultySource;
  final String? ruleTriggered;
  final String? ruleVersion;
  final double? shadowProbability;
  final String? shadowModelVersion;
  final String? shadowReason;
  final String? explanation;
  final bool idempotentReplay;

  int? get nextDifficultyLevel => recommendedLevel;
  String? get source => difficultySource;
  String? get reason => difficultyReason.isEmpty ? null : difficultyReason;

  GameSessionSummary({
    required this.sessionId,
    required this.gameType,
    required this.difficultyLevel,
    required this.totalAttempts,
    required this.correctCount,
    required this.incorrectCount,
    required this.accuracyPct,
    required this.avgResponseTimeMs,
    required this.startedAt,
    required this.completedAt,
    int? recommendedLevel,
    String difficultyReason = '',
    String? difficultySource,
    this.ruleTriggered,
    this.ruleVersion,
    this.shadowProbability,
    this.shadowModelVersion,
    this.shadowReason,
    this.explanation,
    this.idempotentReplay = false,
    int? nextDifficultyLevel,
    String? source,
    String? reason,
  })  : recommendedLevel = recommendedLevel ?? nextDifficultyLevel,
        difficultySource = difficultySource ?? source,
        difficultyReason =
            difficultyReason.isNotEmpty ? difficultyReason : (reason ?? '');

  factory GameSessionSummary.fromJson(Map<String, dynamic> json) {
    final recommended = (json['recommended_level'] as num?)?.toInt();
    return GameSessionSummary(
      sessionId: json['session_id'] as String,
      gameType: json['game_type'] as String,
      difficultyLevel: (json['difficulty_level'] as num).toInt(),
      totalAttempts: (json['total_attempts'] as num).toInt(),
      correctCount: (json['correct_count'] as num).toInt(),
      incorrectCount: (json['incorrect_count'] as num).toInt(),
      accuracyPct: (json['accuracy_pct'] as num).toDouble(),
      avgResponseTimeMs: (json['avg_response_time_ms'] as num).toDouble(),
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: DateTime.parse(json['completed_at'] as String),
      recommendedLevel: recommended?.clamp(1, 3),
      difficultyReason: json['difficulty_reason'] as String? ?? '',
      difficultySource: json['difficulty_source'] as String?,
      ruleTriggered: json['rule_triggered'] as String?,
      ruleVersion: json['rule_version'] as String?,
      shadowProbability: (json['shadow_probability'] as num?)?.toDouble(),
      shadowModelVersion: json['shadow_model_version'] as String?,
      shadowReason: json['shadow_reason'] as String?,
      explanation: json['explanation'] as String?,
      idempotentReplay: json['idempotent_replay'] as bool? ?? false,
    );
  }
}

/// A generated Number Recall board: digit sequence to memorize and repeat.
class RecallBoard {
  final int difficultyLevel;
  final int sequenceLength;
  final int showSecondsPerItem;
  final List<int> sequence;
  final DateTime generatedAt;

  const RecallBoard({
    required this.difficultyLevel,
    required this.sequenceLength,
    required this.showSecondsPerItem,
    required this.sequence,
    required this.generatedAt,
  });

  /// Parse a board from the backend recall/board endpoint.
  factory RecallBoard.fromServerJson(Map<String, dynamic> json) {
    final seq = (json['sequence'] as List? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    return RecallBoard(
      difficultyLevel: json['difficulty_level'] as int? ?? 1,
      sequenceLength: json['sequence_length'] as int? ?? seq.length,
      showSecondsPerItem: json['show_seconds_per_item'] as int? ?? 2,
      sequence: seq,
      generatedAt: DateTime.now(),
    );
  }
}

/// One tile on an Odd-One-Out board. Carries only the public item identity
/// (id + display name) — the answer stays server-side and is never modeled.
class OddOneOutItem {
  final String itemId;
  final String name;

  const OddOneOutItem({required this.itemId, required this.name});

  factory OddOneOutItem.fromJson(Map<String, dynamic> json) => OddOneOutItem(
        itemId: json['item_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'item_id': itemId, 'name': name};
}

/// An Odd-One-Out board: a set of items where all but one share the group.
///
/// Parsed from `GET /games/odd-one-out/board` (`game_type`,
/// `difficulty_level`, `items: [{item_id, name}]`, `item_count`,
/// `target_seconds`, `group_label`, `explanation`). The response never
/// contains the answer, and neither does this model: correctness always
/// comes from the server verdict, never from local inspection.
class OddOneOutBoard {
  final String gameType;
  final int difficultyLevel;
  final List<OddOneOutItem> items;
  final int itemCount;
  final int targetSeconds;
  final String groupLabel;
  final String explanation;
  final DateTime generatedAt;

  const OddOneOutBoard({
    required this.gameType,
    required this.difficultyLevel,
    required this.items,
    required this.itemCount,
    required this.targetSeconds,
    required this.generatedAt,
    this.groupLabel = '',
    this.explanation = '',
  });

  factory OddOneOutBoard.fromServerJson(Map<String, dynamic> json) {
    final items = ((json['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => OddOneOutItem.fromJson(Map<String, dynamic>.from(e))))
        .toList();
    return OddOneOutBoard(
      gameType: json['game_type'] as String? ?? 'odd_one_out',
      difficultyLevel: json['difficulty_level'] as int? ?? 1,
      items: items,
      itemCount: (json['item_count'] as num?)?.toInt() ?? items.length,
      targetSeconds: (json['target_seconds'] as num?)?.toInt() ?? 60,
      groupLabel: json['group_label'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      generatedAt: DateTime.now(),
    );
  }

  /// Snapshot form for the offline board cache (SharedPreferences).
  Map<String, dynamic> toJson() => {
        'game_type': gameType,
        'difficulty_level': difficultyLevel,
        'items': items.map((i) => i.toJson()).toList(),
        'item_count': itemCount,
        'target_seconds': targetSeconds,
        'group_label': groupLabel,
        'explanation': explanation,
      };

  factory OddOneOutBoard.fromJson(Map<String, dynamic> json) => OddOneOutBoard(
        gameType: json['game_type'] as String? ?? 'odd_one_out',
        difficultyLevel: json['difficulty_level'] as int? ?? 1,
        items: ((json['items'] as List? ?? const []).whereType<Map>().map(
                (e) => OddOneOutItem.fromJson(Map<String, dynamic>.from(e))))
            .toList(),
        itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
        targetSeconds: (json['target_seconds'] as num?)?.toInt() ?? 60,
        groupLabel: json['group_label'] as String? ?? '',
        explanation: json['explanation'] as String? ?? '',
        generatedAt: DateTime.now(),
      );
}

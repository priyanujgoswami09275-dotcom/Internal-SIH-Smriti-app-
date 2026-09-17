/// Inline adaptive-difficulty engine and telemetry for the cognitive games.
///
/// Captures per-session metrics tied to a patient ID, applies the dynamic
/// difficulty rules, and emits a structured [GamePerformanceReport] whose
/// fields map onto the caregiver dashboard's 14-day accuracy / response-time
/// trend charts and risk-flag display.
///
/// Pure Dart (no Flutter imports) so rules are unit-testable.
library;

import 'level_config.dart';

// =====================================================================
// Models
// =====================================================================

/// A single completed (or abandoned) game session's metrics.
  class CognitiveGameSession {
  final String sessionId;
  final String patientId;
  final String gameType; // 'match_it' | 'routine_sequencing'
  final int difficultyLevel; // 1 | 2 | 3
  final int timeTakenInSeconds;
  final int totalAttempts;
  final int correctMoves;
  final int incorrectMoves;
  final bool isCompleted;
  final int stuckDurationSeconds; // longest gap without a correct move
  final int avgResponseTimeMs;
  final DateTime playedAt;

  CognitiveGameSession({
    required this.sessionId,
    required this.patientId,
    required this.gameType,
    required this.difficultyLevel,
    required this.timeTakenInSeconds,
    required this.totalAttempts,
    required this.correctMoves,
    required this.incorrectMoves,
    required this.isCompleted,
    this.stuckDurationSeconds = 0,
    this.avgResponseTimeMs = 0,
    DateTime? playedAt,
  }) : playedAt = playedAt ?? DateTime(2000);

  double get accuracyPct =>
      totalAttempts > 0 ? (correctMoves / totalAttempts) * 100 : 0.0;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'patient_id': patientId,
        'game_type': gameType,
        'difficulty_level': difficultyLevel,
        'time_taken_s': timeTakenInSeconds,
        'total_attempts': totalAttempts,
        'correct_moves': correctMoves,
        'incorrect_moves': incorrectMoves,
        'is_completed': isCompleted,
        'stuck_duration_s': stuckDurationSeconds,
        'avg_response_time_ms': avgResponseTimeMs,
        'accuracy_pct': accuracyPct,
        'played_at': playedAt.toIso8601String(),
      };
}

/// Fixed-set recommendation tags (never free text) so the dashboard can
/// group and count them reliably.
enum ReportTag {
  maintainLevel,
  raiseLevel,
  lowerLevel,
  strongRecall,
  needsSupport,
  attentionLag,
  routineStable,
  quickResponse,
}

/// Structured report feeding the caregiver dashboard trends + risk flags.
class GamePerformanceReport {
  final String patientId;
  final String gameType;
  final int difficultyLevel;
  final double accuracyScore; // 0-100
  final double cognitiveSpeedScore; // 0-100 (100 = fastest band)
  final double attentionScore; // 0-100 (penalises stuck time)
  final int recommendedNextLevel;
  final List<ReportTag> tags;

  const GamePerformanceReport({
    required this.patientId,
    required this.gameType,
    required this.difficultyLevel,
    required this.accuracyScore,
    required this.cognitiveSpeedScore,
    required this.attentionScore,
    required this.recommendedNextLevel,
    required this.tags,
  });

  Map<String, dynamic> toJson() => {
        'patient_id': patientId,
        'game_type': gameType,
        'difficulty_level': difficultyLevel,
        'accuracy_score': accuracyScore.round(),
        'cognitive_speed_score': cognitiveSpeedScore.round(),
        'attention_score': attentionScore.round(),
        'recommended_next_level': recommendedNextLevel,
        'tags': tags.map((t) => t.name).toList(),
        // Dashboard trend-chart fields (14-day accuracy / response time).
        'accuracy_pct': accuracyScore,
        'avg_response_time_ms': _speedToResponseMs(),
      };

  int _speedToResponseMs() =>
      (6000 * (1 - (cognitiveSpeedScore / 100))).round().clamp(500, 12000);
}

// =====================================================================
// Engine
// =====================================================================

/// Rule-based adaptive difficulty + performance scoring.
///
/// State management: plain singleton service (matches the app's existing
/// setState + service-class pattern). Widgets hold the returned report;
/// nothing here needs a widget rebuild by itself.
class GameAnalyticsEngine {
  GameAnalyticsEngine._();
  static final GameAnalyticsEngine instance = GameAnalyticsEngine._();

  // ---- Rule thresholds ----
  // Source of truth for level moves: backend difficulty_engine.py
  // (3-session bump streak, 2-session drop streak, 85%/50% bands).
  // Dart mirrors the same numbers so in-app hints agree with the server;
  // the server remains authoritative (POST /games/difficulty/evaluate).
  static const int stuckHintSeconds = 15;
  static const double lowAccuracyPct = 50.0;
  static const double highAccuracyPct = 85.0;
  static const double slowCompletionFactor = 1.5;
  /// Agreement window matching the server's 3-consecutive-session bump rule:
  /// the in-app level suggestion moves only after 3 agreeing sessions.
  static const int sessionsBeforeChange = 3;

  /// Active level parameters (installed from the server map at game start
  /// via [applyLevels]; bundled canonical until then).
  LevelConfig _levels = LevelConfig.bundled;

  void applyLevels(LevelConfig levels) => _levels = levels;

  int _targetFor(String gameType, int difficultyLevel) =>
      _levels.targetSeconds(gameType, difficultyLevel);

  /// Incorrect-move ceilings before the in-session hint fires.
  static const Map<int, int> incorrectMovesHintThreshold = {
    1: 3,
    2: 4,
    3: 5,
  };

  // ---- Session history for the 3-session agreement rule ----
  final Map<String, List<int>> _lastAdjustments = {}; // patientId -> [-1|0|1]

  /// Evaluate the finished session and build the performance report.
  GamePerformanceReport evaluate(CognitiveGameSession s) {
    final accuracy = s.accuracyPct.clamp(0.0, 100.0);
    final target = _targetFor(s.gameType, s.difficultyLevel);
    final slow = !s.isCompleted || s.timeTakenInSeconds > target * slowCompletionFactor;

    // Cognitive speed: fraction of the level target not used (capped 0-100).
    final speed = (s.isCompleted
            ? (1 - (s.timeTakenInSeconds / target)) * 100
            : 0.0)
        .clamp(0.0, 100.0);

    // Attention: penalise stuck time; 15s stuck ≈ −20 points.
    final attention =
        (100 - (s.stuckDurationSeconds / stuckHintSeconds) * 20)
            .clamp(0.0, 100.0);

    final tags = <ReportTag>[];
    if (accuracy >= highAccuracyPct && !slow) {
      tags.add(ReportTag.strongRecall);
      tags.add(ReportTag.quickResponse);
    }
    if (accuracy < lowAccuracyPct) tags.add(ReportTag.needsSupport);
    if (s.stuckDurationSeconds >= stuckHintSeconds) {
      tags.add(ReportTag.attentionLag);
    }
    if (s.gameType == 'routine_sequencing' && s.isCompleted && accuracy >= 60) {
      tags.add(ReportTag.routineStable);
    }

    return GamePerformanceReport(
      patientId: s.patientId,
      gameType: s.gameType,
      difficultyLevel: s.difficultyLevel,
      accuracyScore: accuracy,
      cognitiveSpeedScore: speed,
      attentionScore: attention,
      recommendedNextLevel: recommendedLevel(s),
      tags: tags.isEmpty ? const [ReportTag.maintainLevel] : tags,
    );
  }

  /// Next level for the patient, applying the dynamic rules with the
  /// three-consecutive-sessions agreement requirement (server rule).
  int recommendedLevel(CognitiveGameSession s) {
    final verdict = _verdict(s);
    final history = _lastAdjustments.putIfAbsent(
        '${s.patientId}:${s.gameType}', () => <int>[]);
    history.add(verdict);
    if (history.length > sessionsBeforeChange) {
      history.removeAt(0);
    }
    // Agreeing verdicts must fill the window before the level moves.
    final agreed = history.length == sessionsBeforeChange &&
        history.every((v) => v == verdict) &&
        verdict != 0;
    if (!agreed) return s.difficultyLevel;
    return (s.difficultyLevel + verdict).clamp(1, 3);
  }

  /// Single-session verdict: +1 raise, -1 lower, 0 hold.
  int _verdict(CognitiveGameSession s) {
    final target = _targetFor(s.gameType, s.difficultyLevel);
    final slow = !s.isCompleted || s.timeTakenInSeconds > target * slowCompletionFactor;
    if (s.accuracyPct < lowAccuracyPct || slow) return -1;
    if (s.accuracyPct > highAccuracyPct &&
        s.isCompleted &&
        s.timeTakenInSeconds < target) {
      return 1;
    }
    return 0;
  }

  /// Whether the in-session hint should surface right now (call on tick).
  bool shouldHintNow({
    required int secondsSinceLastCorrect,
    required int incorrectMoves,
    required int difficultyLevel,
  }) =>
      secondsSinceLastCorrect >= stuckHintSeconds ||
      incorrectMoves >= (incorrectMovesHintThreshold[difficultyLevel] ?? 3);

  /// Reset history (used by tests / caregiver override).
  void reset() => _lastAdjustments.clear();
}

/// Human-readable label for a [ReportTag] when shown in the patient UI.
/// All caps per DESIGN.md tag pattern; renderer applies mono font.
String reportTagLabel(ReportTag t) {
  switch (t) {
    case ReportTag.maintainLevel: return 'KEEPING GOING';
    case ReportTag.raiseLevel:    return 'TRY HARDER';
    case ReportTag.lowerLevel:    return 'EASIER NEXT';
    case ReportTag.strongRecall:  return 'STRONG RECALL';
    case ReportTag.needsSupport:  return 'NEEDS SUPPORT';
    case ReportTag.attentionLag:  return 'TAKING TIME';
    case ReportTag.routineStable: return 'STEADY ROUTINE';
    case ReportTag.quickResponse: return 'QUICK THINKER';
  }
}

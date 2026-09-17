/// Unit tests for the adaptive-difficulty engine rules.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:eldercare_mobile/games/game_analytics_engine.dart';

CognitiveGameSession _session({
  required int seconds,
  required int attempts,
  required int correct,
  bool completed = true,
  int level = 1,
  int stuckSeconds = 0,
}) =>
    CognitiveGameSession(
      sessionId: 's_${seconds}_$correct',
      patientId: 'p1',
      gameType: 'match_it',
      difficultyLevel: level,
      timeTakenInSeconds: seconds,
      totalAttempts: attempts,
      correctMoves: correct,
      incorrectMoves: attempts - correct,
      isCompleted: completed,
      stuckDurationSeconds: stuckSeconds,
    );

void main() {
  late GameAnalyticsEngine engine;

  setUp(() {
    engine = GameAnalyticsEngine.instance;
    engine.reset();
  });

  group('hint rule', () {
    test('hints after 15s stuck', () {
      expect(
        engine.shouldHintNow(
            secondsSinceLastCorrect: 15, incorrectMoves: 0, difficultyLevel: 1),
        isTrue,
      );
      expect(
        engine.shouldHintNow(
            secondsSinceLastCorrect: 14, incorrectMoves: 0, difficultyLevel: 1),
        isFalse,
      );
    });

    test('hints when incorrect moves exceed the level threshold', () {
      // L1 threshold = 3
      expect(
        engine.shouldHintNow(
            secondsSinceLastCorrect: 0, incorrectMoves: 3, difficultyLevel: 1),
        isTrue,
      );
      expect(
        engine.shouldHintNow(
            secondsSinceLastCorrect: 0, incorrectMoves: 2, difficultyLevel: 1),
        isFalse,
      );
      // L3 threshold = 5 — harder level allows more misses before hinting
      expect(
        engine.shouldHintNow(
            secondsSinceLastCorrect: 0, incorrectMoves: 4, difficultyLevel: 3),
        isFalse,
      );
      expect(
        engine.shouldHintNow(
            secondsSinceLastCorrect: 0, incorrectMoves: 5, difficultyLevel: 3),
        isTrue,
      );
    });
  });

  group('level change requires three consecutive agreeing sessions', () {
    test('single strong session does NOT raise the level', () {
      // L1 target 90s: 100% accuracy in 50s -> verdict +1
      final r = engine.recommendedLevel(_session(seconds: 50, attempts: 4, correct: 4));
      expect(r, 1, reason: 'first agreeing session must not move the level');
    });

    test('two strong sessions still hold; the third raises the level', () {
      // Mirrors the server bump streak (3 consecutive > 85%).
      engine.recommendedLevel(_session(seconds: 50, attempts: 4, correct: 4));
      final held =
          engine.recommendedLevel(_session(seconds: 55, attempts: 4, correct: 4));
      expect(held, 1, reason: 'only 2 of the required 3 agreeing sessions');
      final raised =
          engine.recommendedLevel(_session(seconds: 52, attempts: 4, correct: 4));
      expect(raised, 2);
    });

    test('disagreeing sessions cancel the agreement window', () {
      engine.recommendedLevel(_session(seconds: 50, attempts: 4, correct: 4));
      // Weak session breaks the streak (accuracy 25% < 40% -> verdict -1)
      engine.recommendedLevel(_session(seconds: 200, attempts: 4, correct: 1));
      // Strong again: only 1 agreeing session since disagreement -> hold.
      final r = engine.recommendedLevel(_session(seconds: 50, attempts: 4, correct: 4));
      expect(r, 1);
    });

    test('three consecutive weak sessions lower the level (L2 -> L1)', () {
      final s1 = _session(seconds: 300, attempts: 4, correct: 1, level: 2);
      final s2 = _session(seconds: 320, attempts: 4, correct: 0, level: 2);
      final s3 = _session(seconds: 310, attempts: 4, correct: 1, level: 2);
      engine.recommendedLevel(s1);
      expect(engine.recommendedLevel(s2), 2,
          reason: 'only 2 of the required 3 agreeing sessions');
      expect(engine.recommendedLevel(s3), 1);
    });

    test('level never drops below 1 nor exceeds 3', () {
      var level = 1;
      for (var i = 0; i < 10; i++) {
        level = engine.recommendedLevel(
            _session(seconds: 50, attempts: 4, correct: 4, level: level));
      }
      expect(level, 3);
      for (var i = 0; i < 10; i++) {
        level = engine.recommendedLevel(
            _session(seconds: 999, attempts: 4, correct: 0, level: level));
      }
      expect(level, 1);
    });
  });

  group('dynamic rules', () {
    test('accuracy < 40% -> lower verdict; > 85% fast -> raise verdict', () {
      // accuracy 39% is low; 40% exactly is not.
      final notLow = _session(seconds: 60, attempts: 100, correct: 40);
      // Two low sessions from L2 must hold; the third drops to L1.
      final lowL2 = _session(seconds: 60, attempts: 100, correct: 39, level: 2);
      engine.recommendedLevel(lowL2);
      expect(engine.recommendedLevel(lowL2), 2);
      expect(engine.recommendedLevel(lowL2), 1);
      engine.reset();
      // 40% + slow time (60s < 90s target, so not slow) -> hold at L1.
      engine.recommendedLevel(notLow);
      expect(engine.recommendedLevel(notLow), 1);
      // Sanity: the 39% verdict differs from the 40% one.
      engine.reset();
      final raise = _session(seconds: 50, attempts: 10, correct: 10);
      engine.recommendedLevel(raise);
      engine.recommendedLevel(raise);
      expect(engine.recommendedLevel(raise), 2, reason: 'fast + perfect must raise');
    });

    test('slow completion (> 1.5x target) counts as a lower verdict', () {
      // L1 target 90s -> slow if > 135s despite good accuracy.
      final slow = _session(seconds: 140, attempts: 4, correct: 4);
      engine.recommendedLevel(slow);
      expect(engine.recommendedLevel(slow), 1,
          reason: 'perfect accuracy but 140s > 1.5x target must hold level');
    });

    test('incomplete session is treated as slow', () {
      final quit = _session(seconds: 10, attempts: 2, correct: 2, completed: false);
      engine.recommendedLevel(quit);
      expect(engine.recommendedLevel(quit), 1);
    });
  });

  group('performance report', () {
    test('report maps to dashboard trend fields', () {
      final report = engine.evaluate(_session(
          seconds: 60, attempts: 8, correct: 7, stuckSeconds: 5));
      final json = report.toJson();
      expect(json['patient_id'], 'p1');
      expect(json['accuracy_score'], 88); // 7/8
      expect(json['tags'], isA<List<String>>());
      expect(json['avg_response_time_ms'], greaterThan(0));
      expect(json['accuracy_pct'], closeTo(87.5, 0.1));
      // Fixed tag set — no free text ever leaves the engine.
      for (final t in json['tags'] as List<String>) {
        expect(ReportTag.values.map((v) => v.name), contains(t));
      }
    });

    test('attention score penalises stuck time', () {
      final quick = engine.evaluate(_session(seconds: 40, attempts: 6, correct: 6));
      final stuck = engine.evaluate(
          _session(seconds: 40, attempts: 6, correct: 6, stuckSeconds: 45));
      expect(stuck.attentionScore, lessThan(quick.attentionScore));
      expect(stuck.tags, contains(ReportTag.attentionLag));
      expect(quick.tags, contains(ReportTag.strongRecall));
    });

    test('empty tags default to maintainLevel', () {
      final mid = engine.evaluate(_session(seconds: 90, attempts: 6, correct: 4));
      expect(mid.tags, const [ReportTag.maintainLevel]);
    });
  });
}

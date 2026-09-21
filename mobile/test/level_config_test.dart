/// Unit tests for LevelConfig — the mobile mirror of game_level_config.
///
/// The bundled canonical grids must equal the backend seeds
/// (level_config_service.DEFAULT_LEVEL_CONFIG); the backend matrix test
/// pins the server side, these pin the mobile side, so the two agree.
library;

import 'package:eldercare_mobile/games/game_analytics_engine.dart';
import 'package:eldercare_mobile/games/level_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LevelConfig.bundled canonical grids', () {
    test('match_it pairs are 2/4/6', () {
      const levels = LevelConfig.bundled;
      expect(levels.matchPairs(1), 2);
      expect(levels.matchPairs(2), 4);
      expect(levels.matchPairs(3), 6);
    });

    test('routine steps are 3/4/6 with icons at every level', () {
      const levels = LevelConfig.bundled;
      expect(levels.routineSteps(1), 3);
      expect(levels.routineSteps(2), 4);
      expect(levels.routineSteps(3), 6);
      expect(levels.routineHints(1), isTrue);
      expect(levels.routineHints(2), isTrue);
      expect(levels.routineHints(3), isFalse);
      expect(levels.routineIcons(1), isTrue);
      expect(levels.routineIcons(2), isTrue);
      expect(levels.routineIcons(3), isTrue);
    });

    test('target seconds match the server seeds', () {      const levels = LevelConfig.bundled;
      expect(levels.targetSeconds('match_it', 1), 90);
      expect(levels.targetSeconds('match_it', 2), 150);
      expect(levels.targetSeconds('match_it', 3), 240);
      expect(levels.targetSeconds('routine_sequencing', 1), 45);
      expect(levels.targetSeconds('routine_sequencing', 2), 70);
      expect(levels.targetSeconds('routine_sequencing', 3), 120);
    });
  });

  group('LevelConfig number_recall grids', () {
    test('sequence lengths are 3/4/6 with 2s per item', () {
      const levels = LevelConfig.bundled;
      expect(levels.recallLength(1), 3);
      expect(levels.recallLength(2), 4);
      expect(levels.recallLength(3), 6);
      expect(levels.recallShowSeconds(1), 2);
      expect(levels.recallShowSeconds(3), 2);
      expect(levels.targetSeconds('number_recall', 1), 60);
      expect(levels.targetSeconds('number_recall', 2), 90);
      expect(levels.targetSeconds('number_recall', 3), 150);
    });
  });

  group('LevelConfig odd_one_out grids', () {
    test('item counts are 3/4/6 with 45/70/120s targets', () {
      const levels = LevelConfig.bundled;
      expect(levels.oddOneOutItems(1), 3);
      expect(levels.oddOneOutItems(2), 4);
      expect(levels.oddOneOutItems(3), 6);
      expect(levels.targetSeconds('odd_one_out', 1), 45);
      expect(levels.targetSeconds('odd_one_out', 2), 70);
      expect(levels.targetSeconds('odd_one_out', 3), 120);
    });

    test('server override changes item count and timing', () {
      final levels = LevelConfig.fromServerJson({
        'odd_one_out': {
          '1': {'items': 5, 'target_seconds': 90},
          '2': {'items': 4, 'target_seconds': 70},
          '3': {'items': 6, 'target_seconds': 120},
        },
      });
      expect(levels.oddOneOutItems(1), 5);
      expect(levels.targetSeconds('odd_one_out', 1), 90);
    });

    test('unknown level falls back to 3 items', () {
      expect(LevelConfig.bundled.oddOneOutItems(99), 3);
    });
  });

  group('LevelConfig.fromServerJson', () {
    test('server map round-trips with string level keys', () {
      const serverMap = {
        'match_it': {
          '1': {'pairs': 2, 'grid': '2x2', 'target_seconds': 90},
          '2': {'pairs': 5, 'grid': 'custom', 'target_seconds': 150},
          '3': {'pairs': 6, 'grid': '4x3', 'target_seconds': 240},
        },
        'routine_sequencing': {
          '1': {'steps': 3, 'hints': true, 'icons': true, 'target_seconds': 45},
          '2': {'steps': 4, 'hints': true, 'icons': true, 'target_seconds': 70},
          '3': {'steps': 6, 'hints': false, 'icons': true, 'target_seconds': 120},
        },
      };
      final levels = LevelConfig.fromServerJson(serverMap);
      // A server override (pairs 5) is honoured — the table drives.
      expect(levels.matchPairs(2), 5);
      expect(levels.matchPairs(1), 2);
      expect(levels.routineSteps(3), 6);
    });

    test('unknown game/level falls back to bundled, then safe defaults', () {
      const levels = LevelConfig.bundled;
      expect(levels.targetSeconds('unknown_game', 1), 60);
      expect(levels.matchPairs(99), 2);
      expect(levels.routineSteps(99), 3);
    });
  });

  group('engine reads installed levels', () {
    test('applyLevels changes the slow-completion target', () {
      final engine = GameAnalyticsEngine.instance;
      engine.reset();
      engine.applyLevels(LevelConfig.bundled);
      // Bundled L1 target 90s: 50s perfect session is fast (verdict +1).
      final fast = CognitiveGameSession(
        sessionId: 's1', patientId: 'p1', gameType: 'match_it',
        difficultyLevel: 1, timeTakenInSeconds: 50,
        totalAttempts: 4, correctMoves: 4, incorrectMoves: 0,
        isCompleted: true,
      );
      // Three agreeing fast sessions raise under the bundled target.
      engine.recommendedLevel(fast);
      engine.recommendedLevel(fast);
      expect(engine.recommendedLevel(fast), 2);
      engine.reset();
      // Install a 10s target: the same session is now slow (verdict -1).
      engine.applyLevels(const LevelConfig({
        'match_it': {
          1: {'pairs': 2, 'target_seconds': 10},
        },
      }));
      engine.recommendedLevel(fast);
      engine.recommendedLevel(fast);
      expect(engine.recommendedLevel(fast), 1);
      // Restore bundled for other tests (same-process singleton).
      engine.applyLevels(LevelConfig.bundled);
      engine.reset();
    });
  });
}

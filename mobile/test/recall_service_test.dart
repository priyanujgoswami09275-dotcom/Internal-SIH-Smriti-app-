/// Unit tests for Number Recall pure logic (no Flutter imports needed,
/// but run under flutter_test like the other game tests).
library;

import 'package:eldercare_mobile/games/level_config.dart';
import 'package:eldercare_mobile/models/game_models.dart';
import 'package:eldercare_mobile/services/recall_service.dart';
import 'package:flutter_test/flutter_test.dart';

RecallBoard _board(List<int> sequence) => RecallBoard(
      difficultyLevel: 1,
      sequenceLength: sequence.length,
      showSecondsPerItem: 2,
      sequence: sequence,
      generatedAt: DateTime.now(),
    );

void main() {
  final service = RecallService();

  group('RecallService.generateSequence', () {
    test('lengths follow the canonical config 3/4/6', () {
      expect(service.generateSequence(difficultyLevel: 1).length, 3);
      expect(service.generateSequence(difficultyLevel: 2).length, 4);
      expect(service.generateSequence(difficultyLevel: 3).length, 6);
    });

    test('digits are 0-9 and unique within a sequence', () {
      for (var i = 0; i < 20; i++) {
        final seq = service.generateSequence(difficultyLevel: 3);
        expect(seq.every((d) => d >= 0 && d <= 9), isTrue);
        expect(seq.toSet().length, seq.length);
      }
    });

    test('server override lengths are honoured', () {
      const custom = LevelConfig({
        'number_recall': {
          2: {'sequence_length': 5, 'show_seconds_per_item': 3},
        },
      });
      expect(
        service.generateSequence(difficultyLevel: 2, levels: custom).length,
        5,
      );
      expect(custom.recallShowSeconds(2), 3);
    });
  });

  group('RecallService gameplay', () {
    test('correct taps complete the turn with full accuracy', () {
      var state = service.initializeGame('s1', _board([4, 1, 7]));
      expect(state.phase, RecallPhase.memorizing);
      state = service.beginRecall(state);
      expect(state.phase, RecallPhase.recalling);

      state = service.handleDigitTap(state, 4)!;
      expect(state.isComplete, isFalse);
      state = service.handleDigitTap(state, 1)!;
      state = service.handleDigitTap(state, 7)!;
      expect(state.isComplete, isTrue);
      expect(state.attempts, 3);
      expect(state.correctCount, 3);
      expect(state.accuracyPct, 100.0);
    });

    test('wrong-position taps score per position', () {
      var state =
          service.beginRecall(service.initializeGame('s1', _board([4, 1, 7])));
      state = service.handleDigitTap(state, 4)!;
      state = service.handleDigitTap(state, 9)!;
      state = service.handleDigitTap(state, 7)!;
      expect(state.isComplete, isTrue);
      expect(state.correctCount, 2);
      expect(state.incorrectCount, 1);
      expect(state.positionCorrect, [true, false, true]);
    });

    test('taps are rejected outside the recall phase or when complete', () {
      final fresh = service.initializeGame('s1', _board([4, 1]));
      // Still memorizing: no taps accepted.
      expect(service.handleDigitTap(fresh, 4), isNull);
      var state = service.beginRecall(fresh);
      state = service.handleDigitTap(state, 4)!;
      state = service.handleDigitTap(state, 1)!;
      expect(state.isComplete, isTrue);
      // Complete: further taps rejected.
      expect(service.handleDigitTap(state, 4), isNull);
    });

    test('response times accumulate per tap', () {
      var state =
          service.beginRecall(service.initializeGame('s1', _board([4, 1])));
      final t0 = DateTime(2026, 9, 20, 10, 0, 0);
      state = service.handleDigitTap(state, 4, now: t0)!;
      state = service.handleDigitTap(
        state,
        1,
        now: t0.add(const Duration(milliseconds: 1500)),
      )!;
      expect(state.responseTimesMs, [0, 1500]);
      expect(state.avgResponseTimeMs, 750.0);
    });
  });
}

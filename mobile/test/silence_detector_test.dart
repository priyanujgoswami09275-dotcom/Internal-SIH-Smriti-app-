import 'package:eldercare_mobile/services/voice_audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SilenceDetector', () {
    test('continuous speech never stops before the hard cap', () {
      final detector = SilenceDetector();
      final start = DateTime(2026, 9, 17, 12, 0, 0);
      detector.reset(start);
      for (var i = 0; i < 100; i++) {
        final t = start.add(Duration(milliseconds: 200 * i));
        expect(detector.feed(-20.0, t), isFalse);
      }
    });

    test('sustained silence past the timeout stops the turn', () {
      final detector = SilenceDetector();
      final start = DateTime(2026, 9, 17, 12, 0, 0);
      detector.reset(start);
      // 1s of speech first.
      for (var i = 0; i < 5; i++) {
        expect(detector.feed(-20.0, start.add(Duration(milliseconds: 200 * i))), isFalse);
      }
      // Then silence: 2.5s timeout means stop at ~3.5s mark.
      var stopped = false;
      for (var i = 5; i < 30; i++) {
        stopped = detector.feed(-60.0, start.add(Duration(milliseconds: 200 * i)));
        if (stopped) break;
      }
      expect(stopped, isTrue);
    });

    test('brief silence followed by speech does not stop', () {
      final detector = SilenceDetector();
      final start = DateTime(2026, 9, 17, 12, 0, 0);
      detector.reset(start);
      var t = start;
      // 1s silence (below the 2.5s timeout), then speech resumes.
      for (var i = 0; i < 5; i++) {
        t = start.add(Duration(milliseconds: 200 * i));
        expect(detector.feed(-60.0, t), isFalse);
      }
      for (var i = 5; i < 20; i++) {
        t = start.add(Duration(milliseconds: 200 * i));
        expect(detector.feed(-20.0, t), isFalse);
      }
    });

    test('hard cap stops even during continuous speech', () {
      final detector = SilenceDetector(
        maxDuration: const Duration(seconds: 5),
      );
      final start = DateTime(2026, 9, 17, 12, 0, 0);
      detector.reset(start);
      expect(detector.feed(-20.0, start.add(const Duration(seconds: 4))), isFalse);
      expect(detector.feed(-20.0, start.add(const Duration(seconds: 5))), isTrue);
    });

    test('reset restarts the turn clock', () {
      final detector = SilenceDetector(
        maxDuration: const Duration(seconds: 5),
      );
      final start = DateTime(2026, 9, 17, 12, 0, 0);
      detector.reset(start);
      expect(detector.feed(-20.0, start.add(const Duration(seconds: 5))), isTrue);
      final restart = start.add(const Duration(seconds: 10));
      detector.reset(restart);
      expect(detector.feed(-20.0, restart.add(const Duration(seconds: 1))), isFalse);
    });
  });
}

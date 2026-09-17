/// Unit tests for VoiceLanguages — picker honesty rules.
///
/// Every picker entry must either work or be honestly gated: Garo always,
/// the rest via the active provider set. Canonical request key is
/// `manipuri` (backend alias `meitei` covers old clients).
library;

import 'package:eldercare_mobile/services/voice_languages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceLanguages', () {
    test('picker keeps ten entries with the manipuri canonical key', () {
      expect(VoiceLanguages.displayNames.length, 10);
      expect(VoiceLanguages.displayNames['manipuri'], 'Meitei (Manipuri)');
      expect(VoiceLanguages.displayNames.containsKey('meitei'), isFalse);
      expect(VoiceLanguages.inputHints['manipuri'], isNotNull);
    });

    test('garo is hard-gated even when the provider set is unknown', () {
      expect(VoiceLanguages.available('garo', null), isFalse);
      expect(
        VoiceLanguages.available('garo', {'garo', 'assamese'}),
        isFalse,
      );
    });

    test('unknown provider set enables everything but garo', () {
      for (final code in VoiceLanguages.displayNames.keys) {
        expect(
          VoiceLanguages.available(code, null),
          code == 'garo' ? isFalse : isTrue,
          reason: code,
        );
      }
    });

    test('known provider set gates uncovered languages', () {
      const sarvamLike = {
        'assamese', 'bengali', 'hindi', 'english',
        'manipuri', 'meitei', 'bodo', 'nepali',
      };
      expect(VoiceLanguages.available('manipuri', sarvamLike), isTrue);
      expect(VoiceLanguages.available('assamese', sarvamLike), isTrue);
      expect(VoiceLanguages.available('khasi', sarvamLike), isFalse);
      expect(VoiceLanguages.available('mizo', sarvamLike), isFalse);
      expect(VoiceLanguages.available('garo', sarvamLike), isFalse);
    });
  });
}

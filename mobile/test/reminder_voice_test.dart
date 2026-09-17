library;

import 'dart:typed_data';

import 'package:eldercare_mobile/models/shared_models.dart';
import 'package:eldercare_mobile/services/reminder_phrases.dart';
import 'package:eldercare_mobile/services/tts_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reminderPhrase', () {
    test('all types have non-empty phrases in core languages', () {
      for (final type in ReminderType.values) {
        for (final lang in ['assamese', 'bengali', 'hindi', 'english']) {
          final phrase = reminderPhrase(type, lang);
          expect(phrase.trim().isNotEmpty, isTrue,
              reason: '$type/$lang must have a phrase');
        }
      }
    });

    test('unknown language falls back to English', () {
      expect(reminderPhrase(ReminderType.medicine, 'klingon'),
          'Time to take your medicine');
      expect(reminderPhrase(ReminderType.water, ''),
          'Time to drink some water');
    });

    test('language matching is case-insensitive', () {
      expect(reminderPhrase(ReminderType.food, 'HINDI'),
          reminderPhrase(ReminderType.food, 'hindi'));
    });
  });

  group('TtsCache', () {
    test('cache keys are stable and distinct', () {
      final a = TtsCache.cacheKey('hello', 'assamese');
      expect(a, TtsCache.cacheKey('hello', 'assamese'));
      expect(a, isNot(TtsCache.cacheKey('hello', 'hindi')));
      expect(a, isNot(TtsCache.cacheKey('bye', 'assamese')));
      expect(a.length, 16);
    });

    test('identical text synthesizes once, then replays from disk', () async {
      var calls = 0;
      final cache = TtsCache(
        synthesize: (text, language) async {
          calls++;
          return Uint8List.fromList([1, 2, 3, 4]);
        },
      );
      // Unique text: the temp-dir cache survives reruns by design.
      final text = 'Once only ${DateTime.now().microsecondsSinceEpoch}';
      final first = await cache.speechFor(text, 'english');
      final second = await cache.speechFor(text, 'english');
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(calls, 1, reason: 'second call must hit the file cache');
    });

    test('different text or language re-synthesizes', () async {
      var calls = 0;
      final cache = TtsCache(
        synthesize: (text, language) async {
          calls++;
          return Uint8List.fromList([9]);
        },
      );
      await cache.speechFor('phrase-a-${DateTime.now().microsecondsSinceEpoch}', 'english');
      await cache.speechFor('phrase-b-${DateTime.now().microsecondsSinceEpoch}', 'english');
      expect(calls, 2);
    });

    test('synthesis failure and empty audio degrade to null', () async {
      final failing = TtsCache(
        synthesize: (text, language) async => throw Exception('tts down'),
      );
      expect(await failing.speechFor('x-${DateTime.now().microsecondsSinceEpoch}', 'en'), isNull);

      final empty = TtsCache(
        synthesize: (text, language) async => Uint8List(0),
      );
      expect(await empty.speechFor('y-${DateTime.now().microsecondsSinceEpoch}', 'en'), isNull);
      expect(await empty.speechFor('   ', 'en'), isNull);
    });
  });
}

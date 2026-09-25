import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eldercare_mobile/games/game_labels.dart';
import 'package:eldercare_mobile/main.dart';
import 'package:eldercare_mobile/patient_localizations.dart';
import 'package:eldercare_mobile/screens/history_screen.dart';
import 'package:eldercare_mobile/screens/match_it_screen.dart';
import 'package:eldercare_mobile/screens/odd_one_out_screen.dart';
import 'package:eldercare_mobile/screens/pack_picker_screen.dart';
import 'package:eldercare_mobile/screens/recall_screen.dart';
import 'package:eldercare_mobile/screens/reminders_screen.dart';
import 'package:eldercare_mobile/screens/routine_screen.dart';
import 'package:eldercare_mobile/screens/voice_companion_screen.dart';
import 'package:eldercare_mobile/services/auth_session.dart';
import 'package:eldercare_mobile/services/offline_sync_service.dart';
import 'package:eldercare_mobile/services/tts_cache.dart';
import 'package:eldercare_mobile/theme/monad_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordedRequest {
  _RecordedRequest(this.method, this.uri, this.body);

  final String method;
  final Uri uri;
  final String body;

  Map<String, dynamic> get json => body.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(body) as Map<String, dynamic>;
}

class _Reply {
  _Reply(this.status, this.body);

  final int status;
  final Object? body;
}

class _PatientBackend {
  _PatientBackend({
    this.profileStatus = 200,
    this.provider = 'sarvam',
    this.chatReply = 'Here is your reply.',
    this.chatFallback = false,
    this.translationReply = 'আপোনাৰ উত্তৰ',
    this.reminderPending = true,
  });

  int profileStatus;
  String provider;
  String chatReply;
  bool chatFallback;
  String translationReply;
  bool reminderPending;
  final List<_RecordedRequest> requests = [];
  int sessionCounter = 0;

  Set<String> get asrLanguages => provider == 'mock'
      ? {'assamese', 'bengali', 'hindi', 'english', 'mizo'}
      : {'assamese', 'bengali', 'hindi', 'english', 'mizo'};
  Set<String> get nmtLanguages => asrLanguages;
  Set<String> get ttsLanguages =>
      provider == 'mock' ? asrLanguages : {'bengali', 'hindi', 'english'};
  Set<String> get unionLanguages => {
        ...asrLanguages,
        ...nmtLanguages,
        ...ttsLanguages,
      };

  List<_RecordedRequest> requestsFor(String path) => requests
      .where((request) => request.uri.path == path)
      .toList(growable: false);

  Future<_Reply> handle(_RecordedRequest request) async {
    requests.add(request);
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/api/v1/patients/me') {
      if (profileStatus != 200) {
        return _Reply(profileStatus, {'detail': 'profile unavailable'});
      }
      return _Reply(200, {
        'id': 'patient-1',
        'user_id': 'user-1',
        'name': 'Test Patient',
        'cognitive_baseline': 'healthy',
        'region': 'Assam',
      });
    }
    if (request.method == 'GET' && path == '/api/v1/language/status') {
      return _Reply(200, {
        'provider': provider,
        'supported_languages': unionLanguages.toList(),
        'capabilities': {
          'asr': {
            'provider': provider,
            'languages': asrLanguages.toList(),
            'simulated': provider == 'mock',
          },
          'nmt': {
            'provider': provider,
            'languages': nmtLanguages.toList(),
            'simulated': provider == 'mock',
          },
          'tts': {
            'provider': provider,
            'languages': ttsLanguages.toList(),
            'simulated': provider == 'mock',
          },
        },
      });
    }
    if (request.method == 'GET' && path == '/api/v1/games/me/history') {
      return _Reply(200, [
        {
          'session_id': 'session-1',
          'game_type': 'match_it',
          'difficulty_level': 2,
          'score': 7,
          'total_attempts': 8,
          'accuracy_pct': 87.5,
          'avg_response_time_ms': 1250.0,
          'completed_at': '2026-09-25T10:30:00Z',
        }
      ]);
    }
    if (request.method == 'GET' &&
        path == '/api/v1/reminders/schedules/patient-1') {
      return _Reply(200, [
        {
          'id': 'schedule-1',
          'patient_id': 'patient-1',
          'reminder_type': 'medicine',
          'cadence': 'daily@08:00',
          'is_active': true,
          'created_at': '2026-09-01T00:00:00Z',
        }
      ]);
    }
    if (request.method == 'GET' &&
        path == '/api/v1/reminders/patients/patient-1/events') {
      return _Reply(200, [
        {
          'id': 'event-1',
          'schedule_id': 'schedule-1',
          'patient_id': 'patient-1',
          'scheduled_at': '2026-09-25T08:00:00Z',
          'status': reminderPending ? 'pending' : 'acknowledged',
          if (!reminderPending) 'acknowledged_at': '2026-09-25T08:05:00Z',
        }
      ]);
    }
    if (request.method == 'GET' && path == '/api/v1/games/content-packs') {
      return _Reply(200, [
        {
          'id': 'festivals_ner',
          'name': 'NER Festivals',
          'region': 'North East India',
          'description': 'Festival memory cards.',
          'item_count': 1,
        }
      ]);
    }
    if (request.method == 'GET' && path.endsWith('/level-config')) {
      return _Reply(200, {
        'config': {
          'match_it': {
            '1': {'pairs': 1, 'target_seconds': 90},
            '2': {'pairs': 4, 'target_seconds': 150},
            '3': {'pairs': 6, 'target_seconds': 240},
          },
          'routine_sequencing': {
            '1': {
              'steps': 1,
              'hints': true,
              'icons': true,
              'target_seconds': 45
            },
            '2': {
              'steps': 4,
              'hints': true,
              'icons': true,
              'target_seconds': 70
            },
            '3': {
              'steps': 6,
              'hints': false,
              'icons': true,
              'target_seconds': 120
            },
          },
          'number_recall': {
            '1': {
              'sequence_length': 1,
              'show_seconds_per_item': 1,
              'target_seconds': 60
            },
            '2': {
              'sequence_length': 4,
              'show_seconds_per_item': 2,
              'target_seconds': 90
            },
            '3': {
              'sequence_length': 6,
              'show_seconds_per_item': 2,
              'target_seconds': 150
            },
          },
          'odd_one_out': {
            '1': {'items': 1, 'target_seconds': 45},
            '2': {'items': 4, 'target_seconds': 70},
            '3': {'items': 6, 'target_seconds': 120},
          },
        }
      });
    }
    if (request.method == 'POST' && path == '/api/v1/games/sessions') {
      final id = 'session-${++sessionCounter}';
      return _Reply(200, {
        'session_id': id,
        'started_at': '2026-09-25T10:00:00Z',
      });
    }
    if (request.method == 'GET' &&
        path == '/api/v1/games/content-packs/festivals_ner/board') {
      return _Reply(200, {
        'pack_id': 'festivals_ner',
        'pack_name': 'NER Festivals',
        'difficulty_level': 1,
        'pair_count': 1,
        'total_cards': 2,
        'cards': [
          {
            'card_id': 1,
            'item_id': 'apple',
            'name_en': 'Apple',
            'name_as': 'আপেল',
            'image_url': '',
          },
          {
            'card_id': 2,
            'item_id': 'apple',
            'name_en': 'Apple',
            'name_as': 'আপেল',
            'image_url': '',
          },
        ],
      });
    }
    if (request.method == 'GET' && path == '/api/v1/games/routine/board') {
      return _Reply(200, {
        'difficulty_level': 1,
        'step_count': 1,
        'has_hints': true,
        'has_icons': true,
        'shuffled_items': [
          {
            'step_id': 'wake',
            'order': 1,
            'time': '06:30',
            'title_en': 'Wake up',
            'title_as': 'সোহপা',
            'icon': 'wb_sunny',
          }
        ],
        'correct_sequence': ['wake'],
      });
    }
    if (request.method == 'GET' && path == '/api/v1/games/recall/board') {
      return _Reply(200, {
        'game_type': 'number_recall',
        'difficulty_level': 1,
        'sequence_length': 1,
        'show_seconds_per_item': 1,
        'sequence': [7],
      });
    }
    if (request.method == 'GET' && path == '/api/v1/games/odd-one-out/board') {
      return _Reply(200, {
        'game_type': 'odd_one_out',
        'difficulty_level': 1,
        'items': [
          {'item_id': 'odd_item', 'name': 'Odd Item'},
        ],
        'item_count': 1,
        'target_seconds': 45,
        'group_label': 'Things',
      });
    }
    if (request.method == 'POST' && path.endsWith('/actions')) {
      return _Reply(200, {
        'status': 'recorded',
        'event': {
          'timestamp': '2026-09-25T10:00:01Z',
          'action_type': request.json['action_type'],
          'action_data': request.json['action_data'],
          'is_correct': true,
          'response_time_ms': request.json['response_time_ms'],
        },
        'idempotent_replay': false,
      });
    }
    if (request.method == 'POST' && path.endsWith('/complete')) {
      return _Reply(200, {
        'session_id': path.split('/').reversed.elementAt(1),
        'game_type': 'match_it',
        'difficulty_level': 1,
        'total_attempts': 1,
        'correct_count': 1,
        'incorrect_count': 0,
        'accuracy_pct': 100.0,
        'avg_response_time_ms': 500.0,
        'started_at': '2026-09-25T10:00:00Z',
        'completed_at': '2026-09-25T10:01:00Z',
        'idempotent_replay': false,
        'recommended_level': 1,
        'difficulty_reason': 'hold',
        'difficulty_source': 'rule_fallback',
      });
    }
    if (request.method == 'POST' && path == '/api/v1/companion/chat/text') {
      return _Reply(200, {
        'reply_text': chatReply,
        'patient_language': request.json['language'],
        'fallback': chatFallback,
        'reason': chatFallback ? 'no_api_key' : null,
      });
    }
    if (request.method == 'POST' && path == '/api/v1/language/translate') {
      return _Reply(200, {
        'original_text': request.json['text'],
        'translated_text': translationReply,
        'source_language': request.json['source_language'],
        'target_language': request.json['target_language'],
        'provider': provider,
        'simulated': provider == 'mock',
      });
    }
    if (request.method == 'POST' && path == '/api/v1/language/tts') {
      return _Reply(200, {
        'audio_base64': '',
        'target_language': request.json['target_language'],
        'provider': provider,
        'simulated': provider == 'mock',
      });
    }
    if (request.method == 'POST' && path == '/api/v1/language/asr') {
      return _Reply(200, {
        'recognized_text': 'I took my morning medicine and had a cup of tea.',
        'source_language': request.json['source_language'],
        'provider': 'mock',
        'simulated': true,
      });
    }
    return _Reply(404, {'detail': 'unhandled ${request.method} $path'});
  }
}

class _BackendOverrides extends HttpOverrides {
  _BackendOverrides(this.backend);

  final _PatientBackend backend;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(backend);
}

class _Client extends Fake implements HttpClient {
  _Client(this.backend);

  final _PatientBackend backend;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(backend, method, url);

  @override
  void close({bool force = false}) {}
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.backend, this.httpMethod, this.url);

  final _PatientBackend backend;
  final String httpMethod;
  final Uri url;
  final StringBuffer _body = StringBuffer();
  final _Headers _headers = _Headers();

  @override
  HttpHeaders get headers => _headers;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 20;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  void write(Object? object) => _body.write(object);

  @override
  void add(List<int> data) => _body.write(utf8.decode(data));

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _body.write(utf8.decode(chunk));
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final reply = await backend.handle(
      _RecordedRequest(httpMethod, url, _body.toString()),
    );
    return _Response(reply.status, reply.body);
  }
}

class _Headers extends Fake implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values
        .putIfAbsent(name.toLowerCase(), () => <String>[])
        .add(value.toString());
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  String? value(String name) => _values[name.toLowerCase()]?.join(',');

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];
}

class _Response extends Fake implements HttpClientResponse {
  _Response(this.status, Object? body)
      : _bytes = utf8.encode(body == null ? '' : jsonEncode(body));

  final int status;
  final List<int> _bytes;

  @override
  int get statusCode => status;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpHeaders get headers {
    final headers = _Headers();
    headers.set('content-type', 'application/json');
    return headers;
  }

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => status >= 400 ? 'ERROR' : 'OK';

  @override
  List<Cookie> get cookies => const [];

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(_bytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}

void _installBackend(_PatientBackend backend) {
  HttpOverrides.global = _BackendOverrides(backend);
  addTearDown(() => HttpOverrides.global = null);
}

Future<void> _seedUser(String language, {String id = 'user-1'}) async {
  SharedPreferences.setMockInitialValues({
    'auth.access': 'access',
    'auth.refresh': 'refresh',
    'auth.user': jsonEncode({
      'id': id,
      'phone': '+910000000001',
      'role': 'patient',
      'preferred_language': language,
    }),
  });
  await AuthSession.instance.restore();
  OfflineSyncService.instance.stop();
  addTearDown(OfflineSyncService.instance.stop);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  OfflineSyncService.instance.stop();
}

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ElderCareApp());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  addTearDown(() => _dispose(tester));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    HttpOverrides.global = null;
    OfflineSyncService.instance.stop();
  });

  group('P1 localization and persisted language', () {
    testWidgets('authenticated app starts from preferredLanguage locale',
        (tester) async {
      final backend = _PatientBackend();
      _installBackend(backend);
      await _seedUser('bengali');
      await _pumpApp(tester);

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale?.languageCode, 'bn');
    });

    testWidgets('voice language choice updates app locale and stored user',
        (tester) async {
      final backend = _PatientBackend();
      _installBackend(backend);
      await _seedUser('english');
      await _pumpApp(tester);
      await tester.pump(const Duration(seconds: 1));

      await tester.scrollUntilVisible(
        find.byIcon(Icons.record_voice_over),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byIcon(Icons.record_voice_over));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();
      await tester.tap(find.text('বাংলা').last);
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale?.languageCode, 'bn');
      final prefs = await SharedPreferences.getInstance();
      final user =
          jsonDecode(prefs.getString('auth.user')!) as Map<String, dynamic>;
      expect(user['preferred_language'], 'bengali');
    });

    for (final fixture in const [
      (
        language: 'assamese',
        text: 'আপোনাৰ স্বাস্থ্য কৰ্মীয়ে আপোনাৰ স্বাস্থ্য নথি যোগ কৰিব পাৰে।',
      ),
      (
        language: 'bengali',
        text: 'আপনার স্বাস্থ্যসেবী আপনার স্বাস্থ্য নথি যোগ করতে পারেন।',
      ),
      (
        language: 'hindi',
        text: 'आपका स्वास्थ्यकर्मी आपके स्वास्थ्य दस्तावेज़ जोड़ सकता है।',
      ),
      (
        language: 'english',
        text: 'Your health worker can add your health documents.',
      ),
    ]) {
      testWidgets('${fixture.language} localizes patient home chrome',
          (tester) async {
        expect(
          PatientLocalizations.forLanguage(
            fixture.language,
            'home.healthWorkerLine',
          ),
          fixture.text,
        );
        final backend = _PatientBackend();

        _installBackend(backend);
        await _seedUser(fixture.language);
        await tester.pumpWidget(
          MaterialApp(
            locale: PatientLocalizations.localeFor(fixture.language),
            supportedLocales: const [
              Locale('en'),
              Locale('as'),
              Locale('bn'),
              Locale('hi'),
            ],
            localizationsDelegates: const [
              ...GlobalMaterialLocalizations.delegates,
              PatientLocalizations.delegate,
            ],
            home: const PatientHome(patientId: 'patient-1'),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text(fixture.text), findsOneWidget);
      });
    }

    test('game chrome has four honest translations and English fallback', () {
      expect(GameLabels.of('assamese', 'matchit.title'), 'মিলাওক');
      expect(GameLabels.of('bengali', 'matchit.title'), 'মিলাওক');
      expect(GameLabels.of('hindi', 'matchit.title'), 'मिलाओ');
      expect(GameLabels.of('english', 'matchit.title'), 'Match It');
      expect(GameLabels.of('mizo', 'matchit.title'), 'Match It');
    });

    testWidgets('non-localized companion language is labelled English fallback',
        (tester) async {
      final backend = _PatientBackend();
      _installBackend(backend);
      await _seedUser('mizo');
      await tester.pumpWidget(
        const MaterialApp(home: VoiceCompanionScreen(patientId: 'patient-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();

      expect(find.textContaining('English fallback'), findsWidgets);
    });
  });

  group('P2 and P3 provider honesty', () {
    test('TtsCache exposes synthesis failures to the caller', () async {
      final cache = TtsCache(
        synthesize: (text, language) async => throw StateError('offline'),
      );

      final result = await cache.speechResult(
        'failure-${DateTime.now().microsecondsSinceEpoch}',
        'english',
      );

      expect(result.bytes, isNull);
      expect(result.error, isNotNull);
    });

    testWidgets('mock speech provider disables mic and spoken replies visibly',
        (tester) async {
      final backend = _PatientBackend(provider: 'mock');
      _installBackend(backend);
      await _seedUser('english');
      await tester.pumpWidget(
        const MaterialApp(home: VoiceCompanionScreen(patientId: 'patient-1')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Simulated: no speech provider configured'),
        findsOneWidget,
      );
      final mic = tester.widget<GestureDetector>(
        find
            .ancestor(
                of: find.byIcon(Icons.mic),
                matching: find.byType(GestureDetector))
            .first,
      );
      expect(mic.onTap, isNull);
      final spokenToggle = tester.widget<IconButton>(
        find
            .ancestor(
                of: find.byIcon(Icons.volume_off),
                matching: find.byType(IconButton))
            .first,
      );

      expect(spokenToggle.onPressed, isNull);
    });

    testWidgets(
        'missing TTS capability disables reminder speech without a request',
        (tester) async {
      final backend = _PatientBackend(provider: 'sarvam');
      _installBackend(backend);
      await _seedUser('assamese');
      await tester.pumpWidget(
        const MaterialApp(home: RemindersScreen(patientId: 'patient-1')),
      );
      await tester.pumpAndSettle();

      expect(backend.requestsFor('/api/v1/language/tts'), isEmpty);
      final speaker = tester.widgetList<IconButton>(find.byType(IconButton));
      expect(speaker.any((button) => button.onPressed == null), isTrue);
    });

    testWidgets('canned fallback disclosure is spoken with the reply',
        (tester) async {
      final backend = _PatientBackend(
        provider: 'sarvam',
        chatReply: 'আপু, আজি কেমন আছে?',
        chatFallback: true,
      );
      _installBackend(backend);
      await _seedUser('bengali');
      await tester.pumpWidget(
        const MaterialApp(home: VoiceCompanionScreen(patientId: 'patient-1')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'আজি মন দুখী');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      final speech = backend.requestsFor('/api/v1/language/tts');
      expect(speech, hasLength(1));
      final spokenText = speech.single.json['text'] as String;
      expect(spokenText, contains('আপু, আজি কেমন আছে?'));
      expect(spokenText, isNot('আপু, আজি কেমন আছে?'));
      expect(
        find.text(
            'Simulated companion reply — no live conversation provider is configured.'),
        findsOneWidget,
      );
    });
  });

  group('P4 reply translation', () {
    testWidgets('English reply for Assamese selection uses real NMT',
        (tester) async {
      final backend = _PatientBackend(
        provider: 'sarvam',
        chatReply: 'Here is your reply.',
        translationReply: 'আপোনাৰ উত্তৰ',
      );
      _installBackend(backend);
      await _seedUser('assamese');
      await tester.pumpWidget(
        const MaterialApp(home: VoiceCompanionScreen(patientId: 'patient-1')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'I need help');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      final translations = backend.requestsFor('/api/v1/language/translate');
      expect(translations, hasLength(1));
      expect(translations.single.json, {
        'text': 'Here is your reply.',
        'source_language': 'english',
        'target_language': 'assamese',
      });
      expect(find.text('আপোনাৰ উত্তৰ'), findsOneWidget);
    });
  });

  group('P5 profile resolution states', () {
    testWidgets('server failure shows retry instead of profile setup',
        (tester) async {
      final backend = _PatientBackend(profileStatus: 503);
      _installBackend(backend);
      await _seedUser('english');
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Could not load your profile'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);

      expect(find.text('Tell us your name to get started'), findsNothing);
      addTearDown(() => _dispose(tester));
    });

    testWidgets('expired session is distinct from missing profile',
        (tester) async {
      final backend = _PatientBackend(profileStatus: 401);
      _installBackend(backend);
      await _seedUser('english');
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Your session has expired'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);

      expect(find.text('Tell us your name to get started'), findsNothing);
      addTearDown(() => _dispose(tester));
    });

    testWidgets('404 still starts first-time profile setup', (tester) async {
      final backend = _PatientBackend(profileStatus: 404);
      _installBackend(backend);
      await _seedUser('english');
      await tester.pumpWidget(const MaterialApp(home: HomeShell()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Tell us your name to get started'), findsOneWidget);
      addTearDown(() => _dispose(tester));
    });
  });

  group('P6 patient history', () {
    testWidgets(
        'patient home opens recent owner history with score and accuracy',
        (tester) async {
      final backend = _PatientBackend();
      _installBackend(backend);
      await tester.pumpWidget(
        const MaterialApp(home: PatientHome(patientId: 'patient-1')),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Game History'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Game History'));
      await tester.pump();
      await tester.tap(find.text('Game History'));

      await tester.pumpAndSettle();

      expect(backend.requestsFor('/api/v1/games/me/history'), hasLength(1));
      expect(find.text('Game History'), findsOneWidget);
      expect(find.text('Memory Match'), findsOneWidget);
      expect(find.textContaining('Sep 25'), findsOneWidget);

      expect(find.text('Score: 7 / 8'), findsOneWidget);

      expect(find.text('Accuracy: 87.5%'), findsOneWidget);
    });
  });

  group('P7 contrast', () {
    test('patient secondary and status colors meet WCAG AA on parchment', () {
      expect(
          _contrast(Monad.smoke, Monad.parchment), greaterThanOrEqualTo(4.5));
      expect(
          _contrast(Monad.crimson, Monad.parchment), greaterThanOrEqualTo(4.5));
    });
  });

  group('P8 textScaleFactor 1.3 coverage locks', () {
    Future<void> pumpAtScale(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(home);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('patient home remains usable at 1.3 scale', (tester) async {
      await _seedUser('english');
      await pumpAtScale(
        tester,
        const MaterialApp(home: PatientHome(patientId: 'patient-1')),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Your health worker can add your health documents.'),
          findsOneWidget);
    });

    testWidgets('history screen remains usable at 1.3 scale', (tester) async {
      final backend = _PatientBackend();
      _installBackend(backend);
      await pumpAtScale(
        tester,
        const MaterialApp(home: HistoryScreen(patientId: 'patient-1')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Memory Match'), findsOneWidget);
    });

    testWidgets('reminders screen remains usable at 1.3 scale', (tester) async {
      final backend = _PatientBackend(reminderPending: false);
      _installBackend(backend);
      await _seedUser('english');
      await pumpAtScale(
        tester,
        const MaterialApp(home: RemindersScreen(patientId: 'patient-1')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Daily Reminders'), findsOneWidget);
    });

    testWidgets('voice screen remains usable at 1.3 scale', (tester) async {
      final backend = _PatientBackend(provider: 'mock');
      _installBackend(backend);
      await _seedUser('english');
      await pumpAtScale(
        tester,
        const MaterialApp(home: VoiceCompanionScreen(patientId: 'patient-1')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Simulated: no speech provider configured'),
          findsOneWidget);
    });

    testWidgets('pack picker remains usable at 1.3 scale', (tester) async {
      final backend = _PatientBackend();
      _installBackend(backend);
      await pumpAtScale(
        tester,
        const MaterialApp(home: PackPickerScreen(patientId: 'patient-1')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Choose a Game'), findsOneWidget);
    });

    testWidgets('Match It completion surface remains usable at 1.3 scale',
        (tester) async {
      final backend = _PatientBackend();
      _installBackend(backend);
      await _seedUser('english');
      await pumpAtScale(
        tester,
        const MaterialApp(
          home: MatchItScreen(
            patientId: 'patient-1',
            packId: 'festivals_ner',
            packName: 'NER Festivals',
            difficultyLevel: 1,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.bySemanticsLabel('Card 1'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Card 2'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Recall completion surface remains usable at 1.3 scale',
        (tester) async {
      final backend = _PatientBackend();
      _installBackend(backend);
      await _seedUser('english');
      await pumpAtScale(
        tester,
        const MaterialApp(
          home: RecallScreen(patientId: 'patient-1', initialDifficulty: 1),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(FilledButton));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('7').last);
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Odd One Out completion surface remains usable at 1.3 scale',
        (tester) async {
      final backend = _PatientBackend();
      _installBackend(backend);
      await _seedUser('english');
      await pumpAtScale(
        tester,
        const MaterialApp(
          home: OddOneOutScreen(
            patientId: 'patient-1',
            initialDifficulty: 1,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(FilledButton));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Odd Item'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('Routine completion surface remains usable at 1.3 scale',
        (tester) async {
      final backend = _PatientBackend();
      _installBackend(backend);
      await _seedUser('english');
      await pumpAtScale(
        tester,
        const MaterialApp(
          home: RoutineScreen(
            patientId: 'patient-1',
            difficultyLevel: 1,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Wake up'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('P9 mid-round navigation', () {
    final games = <String, Widget Function()>{
      'match_it': () => const MatchItScreen(
            patientId: 'patient-1',
            packId: 'festivals_ner',
            packName: 'NER Festivals',
            difficultyLevel: 1,
          ),
      'routine': () => const RoutineScreen(
            patientId: 'patient-1',
            difficultyLevel: 1,
          ),
      'recall': () => const RecallScreen(
            patientId: 'patient-1',
            initialDifficulty: 1,
          ),
      'odd_one_out': () => const OddOneOutScreen(
            patientId: 'patient-1',
            initialDifficulty: 1,
          ),
    };

    for (final entry in games.entries) {
      testWidgets(
          '${entry.key} asks before abandoning and starts no duplicate session',
          (tester) async {
        final backend = _PatientBackend();
        _installBackend(backend);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => entry.value()),
                  ),
                  child: const Text('OPEN GAME'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('OPEN GAME'));
        await tester.pumpAndSettle();
        expect(backend.sessionCounter, 1);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Leave game?'), findsOneWidget);
        expect(find.text('OPEN GAME'), findsNothing);

        await tester.tap(find.text('Keep playing'));
        await tester.pumpAndSettle();
        expect(find.text('OPEN GAME'), findsNothing);
        expect(backend.sessionCounter, 1);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leave game'));
        await tester.pumpAndSettle();
        expect(find.text('OPEN GAME'), findsOneWidget);
        expect(backend.sessionCounter, 1);
      });
    }
  });
}

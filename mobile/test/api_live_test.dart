/// Live client->server integration check through the real ApiService.
///
/// Skipped by default (needs a running backend); run with:
///   flutter test --dart-define=LIVE_API=true --dart-define=API_BASE_URL=http://localhost:8000
/// (the extra define matters: flutter test reports an Android platform,
/// so AppConfig would otherwise point at the emulator-only 10.0.2.2).
library;

import 'package:eldercare_mobile/models/shared_models.dart';
import 'package:eldercare_mobile/services/api_service.dart';
import 'package:eldercare_mobile/services/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = bool.fromEnvironment('LIVE_API');

/// Mirror the app's real auth flow: AuthSession wires tokens onto the
/// ApiService singleton (see auth_session.dart).
Future<UserModel> _loginAs(String phone) async {
  await AuthSession.instance.login(phone: phone, password: 'DemoPass123');
  return AuthSession.instance.user!;
}

void main() {
  SharedPreferences.setMockInitialValues({});
  group('live backend via ApiService', () {
    test('patient login routes to patient role', () async {
      final user = await _loginAs('919876543001');
      expect(user.role, Role.patient);
    });

    test('caregiver login routes to staff role', () async {
      final user = await _loginAs('919876543002');
      expect(user.role, isNot(Role.patient));
    });

    test('caregiver dashboard summary reflects real data', () async {
      final api = ApiService.instance;
      final user = await _loginAs('919876543002');
      final patients = await api.caregiverPatients(user.id);
      expect(patients, isNotEmpty);
      final summary = await api.patientSummary(
          patients.first['patient_id'] as String);
      expect(summary['patient_id'], isNotNull);
      expect(summary['view'], isIn(['basic', 'clinical']));
    });

    // The server is authoritative: the board is bound to the session before
    // any action, the client never claims correctness, and every verdict
    // below is computed by the server from its own board snapshot.
    test('games session round-trip persists', () async {
      final api = ApiService.instance;
      await _loginAs('919876543001');

      const difficulty = 2;
      final pack = (await api.listContentPacks())
          .firstWhere((contentPack) => contentPack.itemCount >= 4);
      final sessionId = await api.startGame(
        gameType: 'match_it',
        difficultyLevel: difficulty,
        contentPackId: pack.id,
      );
      expect(sessionId, isNotEmpty);

      // Binding the board is what makes scoring possible at all.
      final board = await api.matchItBoard(
        packId: pack.id,
        difficultyLevel: difficulty,
        sessionId: sessionId,
      );
      expect(board.cards, hasLength(board.pairCount * 2));

      final cardsByItem = <String, List<String>>{};
      for (final card in board.cards) {
        cardsByItem.putIfAbsent(card.pairId, () => <String>[]).add(card.id);
      }
      final items = cardsByItem.keys.toList()..sort();
      expect(items.length, greaterThanOrEqualTo(3));
      for (final item in items) {
        expect(cardsByItem[item], hasLength(2));
      }
      // Two cards of one item, then a deliberate mismatch between two others.
      final played = <String>[
        cardsByItem[items[0]]![0],
        cardsByItem[items[0]]![1],
        cardsByItem[items[1]]![0],
        cardsByItem[items[2]]![0],
      ];

      final actionKeys = <String>[];
      for (var index = 0; index < played.length; index++) {
        final key = ApiService.actionIdempotencyKey(
          sessionId: sessionId,
          actionIndex: index,
          actionId: played[index],
        );
        actionKeys.add(key);
        await api.recordGameAction(
          sessionId: sessionId,
          actionType: 'flip_card',
          actionData: {'card_id': played[index]},
          responseTimeMs: 900,
          idempotencyKey: key,
        );
      }

      // A retried action (same key) must not be scored or counted twice.
      await api.recordGameAction(
        sessionId: sessionId,
        actionType: 'flip_card',
        actionData: {'card_id': played.last},
        responseTimeMs: 900,
        idempotencyKey: actionKeys.last,
      );

      final summary = await api.completeGame(
        sessionId,
        idempotencyKey: ApiService.completionIdempotencyKey(sessionId),
        expectedActionIds: actionKeys,
      );

      // Scored by the server: one matched pair, one mismatch, 2 attempts.
      expect(summary.sessionId, sessionId);
      expect(summary.idempotentReplay, isFalse);
      expect(summary.totalAttempts, 2);
      expect(summary.correctCount, 1);
      expect(summary.incorrectCount, 1);
      expect(summary.accuracyPct, 50.0);
      expect(summary.avgResponseTimeMs, 900.0);
      expect(summary.recommendedLevel, isNotNull);
      expect(summary.recommendedLevel, inInclusiveRange(1, 3));

      // Persisted: readable back through the app's own history endpoint.
      final history = await api.patientGameHistory(limit: 20);
      final persisted =
          history.firstWhere((item) => item.sessionId == sessionId);
      expect(persisted.gameType, 'match_it');
      expect(persisted.totalAttempts, 2);
      expect(persisted.accuracyPct, 50.0);
    });

    test('companions chat returns a real reply', () async {
      final api = ApiService.instance;
      await _loginAs('919876543001');
      final patient = await api.myPatient();
      final reply = await api.companionTextChat(
        patientId: patient!.id,
        message: 'hello',
        language: 'english',
      );
      expect(reply.replyText, isNotEmpty);
    });
  }, skip: !_live ? 'needs LIVE_API=true and a running backend' : false);
}

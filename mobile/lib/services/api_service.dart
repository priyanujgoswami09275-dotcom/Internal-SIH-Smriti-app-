/// Typed API client for the Elder-Care backend (FastAPI under /api/v1).
///
/// Endpoint contract matches `backend/app/routes/*`:
///   - auth:      register, login, refresh, logout, me
///   - patients:  me (own profile)
///   - games:     sessions, complete, content packs, boards, routine board
///   - reminders: schedules, events acknowledge
///   - companion: chat/text (voice companion)
///   - speech:    asr + tts via the server provider chain (Sarvam/Bhashini/mock)
///   - dashboard: caregiver roster, patient summary, alert acknowledge
///
/// A low-level `get/post/put/delete` returning `http.Response` is also exposed
/// for endpoints not yet given a typed wrapper.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/game_models.dart';
import '../models/shared_models.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Token pair returned by the backend auth endpoints.
class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final String tokenType;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.tokenType = 'bearer',
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        tokenType: json['token_type'] as String? ?? 'bearer',
      );
}

class ApiService {
  final String baseUrl;
  String? authToken;
  String? refreshToken;

  ApiService({String? baseUrl, this.authToken, this.refreshToken})
      : baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  /// Singleton with the token wired by [AuthSession] after login.
  static final ApiService instance = ApiService();

  /// Fired when an authenticated request ends in 401 (refresh failed or
  /// missing). AuthSession wires this to drop back to the login screen so
  /// a dead session never strands the user. Guarded against reentrancy
  /// (logout itself calls the API).
  static Future<void> Function()? onUnauthorized;
  bool _inUnauthorizedHandler = false;

  /// Fired after a successful silent refresh so new tokens get persisted.
  /// Without this, a restart would replay a rotated (dead) refresh token.
  static void Function(String access, String refresh)? onTokensRefreshed;

  // =====================================================================
  // Low-level HTTP
  // =====================================================================

  Map<String, String> _headers({bool includeAuth = true}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (includeAuth && authToken != null) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    return uri;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool includeAuth = true,
  }) async {
    final uri = _uri(path, query);
    final headers = _headers(includeAuth: includeAuth);
    final encoded = body != null ? jsonEncode(body) : null;
    http.Response response;
    try {
      if (method == 'GET') {
        response = await http.get(uri, headers: headers);
      } else if (method == 'DELETE') {
        response = await http.delete(uri, headers: headers);
      } else if (method == 'PUT') {
        response = await http.put(uri, headers: headers, body: encoded);
      } else {
        response = await http.post(uri, headers: headers, body: encoded);
      }
    } on Exception catch (e) {
      developer.log('API request failed: $e', name: 'ApiService');
      throw ApiException('Network error: $e');
    }

    // One refresh attempt on 401, then retry the original request.
    if (response.statusCode == 401 && includeAuth && refreshToken != null) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _send(method, path, body: body, query: query, includeAuth: includeAuth);
      }
    }
    if (response.statusCode == 401 && includeAuth && !_inUnauthorizedHandler) {
      _inUnauthorizedHandler = true;
      try {
        await onUnauthorized?.call();
      } finally {
        _inUnauthorizedHandler = false;
      }
    }
    return response;
  }

  /// Shared in-flight refresh: parallel 401s await the same refresh instead of
  /// racing (the second refresh of a rotated token would fail and spuriously
  /// log the user out). Cleared when the refresh settles.
  Future<AuthTokens>? _refreshInFlight;

  Future<bool> _tryRefresh() async {
    final token = refreshToken;
    if (token == null) return false;
    try {
      _refreshInFlight ??= refresh(token);
      final tokens = await _refreshInFlight!;
      authToken = tokens.accessToken;
      refreshToken = tokens.refreshToken;
      onTokensRefreshed?.call(tokens.accessToken, tokens.refreshToken);
      return true;
    } catch (_) {
      return false;
    } finally {
      _refreshInFlight = null;
    }
  }

  /// Generic GET returning the decoded JSON body (or null on 2xx empty).
  Future<dynamic> getJson(
    String path, {
    Map<String, String>? query,
    bool includeAuth = true,
  }) async {
    final res = await _send('GET', path, query: query, includeAuth: includeAuth);
    return _decode(res);
  }

  /// Generic POST returning the decoded JSON body.
  Future<dynamic> postJson(
    String path, {
    Map<String, dynamic>? body,
    bool includeAuth = true,
  }) async {
    final res = await _send('POST', path, body: body, includeAuth: includeAuth);
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    String detail = 'HTTP ${res.statusCode}';
    try {
      final data = jsonDecode(res.body);
      if (data is Map && data['detail'] != null) {
        detail = data['detail'].toString();
      }
    } catch (_) {}
    throw ApiException(detail, statusCode: res.statusCode);
  }

  // =====================================================================
  // Auth
  // =====================================================================

  /// Register a new account; the backend register endpoint returns the user
  /// profile, so we immediately log in to obtain a token pair.
  Future<AuthTokens> register({
    required String phone,
    required String password,
    String? email,
    String role = 'patient',
    String preferredLanguage = 'english',
  }) async {
    await postJson(
      '${AppConfig.apiV1}/auth/register',
      body: {
        'phone': phone,
        'password': password,
        if (email != null) 'email': email,
        'role': role,
        'preferred_language': preferredLanguage,
      },
      includeAuth: false,
    );
    return login(phone: phone, password: password);
  }

  Future<AuthTokens> login({required String phone, required String password}) async {
    final data = await postJson(
      '${AppConfig.apiV1}/auth/login',
      body: {'phone': phone, 'password': password},
      includeAuth: false,
    );
    return AuthTokens.fromJson(data as Map<String, dynamic>);
  }

  Future<AuthTokens> refresh(String token) async {
    final data = await postJson(
      '${AppConfig.apiV1}/auth/refresh',
      body: {'refresh_token': token},
      includeAuth: false,
    );
    return AuthTokens.fromJson(data as Map<String, dynamic>);
  }

  Future<void> logout() async {
    await postJson('${AppConfig.apiV1}/auth/logout');
  }

  Future<UserModel> me() async {
    final data = await getJson('${AppConfig.apiV1}/auth/me');
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  // =====================================================================
  // Patients
  // =====================================================================

  Future<PatientModel?> myPatient() async {
    try {
      final data = await getJson('${AppConfig.apiV1}/patients/me');
      return PatientModel.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null; // no profile yet
      rethrow;
    }
  }

  Future<PatientModel> createMyPatient({
    required String name,
    String region = 'Assam',
    String district = 'Kamrup',
    String cognitiveBaseline = 'healthy',
  }) async {
    final data = await postJson(
      '${AppConfig.apiV1}/patients',
      body: {
        'name': name,
        'region': region,
        'district': district,
        'cognitive_baseline': cognitiveBaseline,
      },
    );
    return PatientModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> grantConsent({
    required String patientId,
    String scope = 'all',
    String consentType = 'patient_self',
  }) async {
    await postJson(
      '${AppConfig.apiV1}/compliance/consent',
      body: {
        'patient_id': patientId,
        'consent_type': consentType,
        'scope': scope,
      },
    );
  }

  // =====================================================================
  // Games
  // =====================================================================

  Future<String> startGame({
    required String gameType,
    required int difficultyLevel,
    String? contentPackId,
    String? routineId,
  }) async {
    final data = await postJson(
      '${AppConfig.apiV1}/games/sessions',
      body: {
        'game_type': gameType,
        'difficulty_level': difficultyLevel,
        if (contentPackId != null) 'content_pack_id': contentPackId,
        if (routineId != null) 'routine_id': routineId,
      },
    );
    final map = data as Map<String, dynamic>;
    if (map['session_id'] == null) throw ApiException('No session_id returned');
    return map['session_id'] as String;
  }

  Future<GameSessionSummary> completeGame(String sessionId) async {
    final data = await postJson('${AppConfig.apiV1}/games/sessions/$sessionId/complete');
    return GameSessionSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<List<ContentPackSummary>> listContentPacks() async {
    final data = await getJson('${AppConfig.apiV1}/games/content-packs');
    return (data as List)
        .map((e) => ContentPackSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Record a single in-game action (best-effort; offline actions are queued
  /// locally by the caller).
  Future<bool> recordGameAction({
    required String sessionId,
    required String actionType,
    Map<String, dynamic>? actionData,
    bool? isCorrect,
    int? responseTimeMs,
  }) async {
    await postJson(
      '${AppConfig.apiV1}/games/sessions/$sessionId/actions',
      body: {
        'action_type': actionType,
        'action_data': actionData ?? const {},
        if (isCorrect != null) 'is_correct': isCorrect,
        if (responseTimeMs != null) 'response_time_ms': responseTimeMs,
      },
    );
    return true;
  }

  Future<MatchItBoard> matchItBoard({
    required String packId,
    required int difficultyLevel,
  }) async {
    final data = await getJson(
      '${AppConfig.apiV1}/games/content-packs/$packId/board',
      query: {'difficulty_level': '$difficultyLevel'},
    );
    return MatchItBoard.fromServerJson(data as Map<String, dynamic>);
  }

  Future<RecallBoard> recallBoard({
    required int difficultyLevel,
  }) async {
    final data = await getJson(
      '${AppConfig.apiV1}/games/recall/board',
      query: {'difficulty_level': '$difficultyLevel'},
    );
    return RecallBoard.fromServerJson(data as Map<String, dynamic>);
  }

  Future<RoutineBoard> routineBoard({
    required String patientId,
    required int difficultyLevel,
  }) async {
    final data = await getJson(
      '${AppConfig.apiV1}/games/routine/board',
      query: {'patient_id': patientId, 'difficulty_level': '$difficultyLevel'},
    );
    return RoutineBoard.fromServerJson(data as Map<String, dynamic>);
  }

  // =====================================================================
  // Reminders
  // =====================================================================

  Future<List<ReminderScheduleModel>> reminderSchedules(String patientId) async {
    final data = await getJson('${AppConfig.apiV1}/reminders/schedules/$patientId');
    return (data as List)
        .map((e) => ReminderScheduleModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Today's reminder events (real event IDs + status) for the patient.
  Future<List<ReminderEventModel>> reminderEvents(String patientId) async {
    final data = await getJson('${AppConfig.apiV1}/reminders/patients/$patientId/events');
    return (data as List)
        .map((e) => ReminderEventModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Record an acknowledgment for a reminder event.
  Future<bool> acknowledgeReminder(String eventId, {String method = 'button'}) async {
    final data = await postJson(
      '${AppConfig.apiV1}/reminders/events/$eventId/acknowledge',
      body: {'method': method},
    );
    return data != null;
  }

  /// Retrieve the patient's daily routine (backend returns the default
  /// 10-step routine when the caregiver has not customized it).
  Future<List<RoutineStep>> patientRoutine(String patientId) async {
    final data = await getJson('${AppConfig.apiV1}/games/patients/$patientId/routine');
    final list = (data as Map<String, dynamic>)['routine'] as List;
    return list.map((e) => RoutineStep.fromJson(e as Map<String, dynamic>)).toList();
  }

  // =====================================================================
  // Voice companion
  // =====================================================================

  Future<CompanionReply> companionTextChat({
    required String patientId,
    required String message,
    String language = 'assamese',
    List<Map<String, String>>? history,
  }) async {
    final data = await postJson(
      '${AppConfig.apiV1}/companion/chat/text',
      body: {
        'patient_id': patientId,
        'message': message,
        'language': language,
        if (history != null && history.isNotEmpty) 'history': history,
      },
    );
    return CompanionReply.fromJson(data as Map<String, dynamic>);
  }

  // =====================================================================
  // Speech — server-side ASR/TTS (the device only records and plays;
  // all speech intelligence lives in the backend provider chain).
  // =====================================================================

  /// Transcribe recorded audio via POST /language/asr.
  /// [audioBase64] must be base64 wav (16kHz mono preferred).
  /// Throws [ApiException] on 400 (unsupported language) or 502 (provider).
  Future<String> transcribeAudio({
    required String audioBase64,
    required String language,
  }) async {
    final data = await postJson(
      '${AppConfig.apiV1}/language/asr',
      body: {'audio_base64': audioBase64, 'source_language': language},
    );
    return (data as Map<String, dynamic>)['recognized_text'] as String? ?? '';
  }

  /// Synthesize [text] via POST /language/tts; returns raw audio bytes
  /// for playback. Throws [ApiException] on failure — callers fall back
  /// to text display.
  Future<Uint8List> synthesizeSpeech({
    required String text,
    required String language,
  }) async {
    final data = await postJson(
      '${AppConfig.apiV1}/language/tts',
      body: {'text': text, 'target_language': language},
    );
    final b64 =
        (data as Map<String, dynamic>)['audio_base64'] as String? ?? '';
    return base64Decode(b64);
  }

  /// Full difficulty map for LevelConfig sync (GET /games/level-config).
  Future<Map<String, dynamic>> fetchLevelConfig() async {
    final data = await getJson('${AppConfig.apiV1}/games/level-config');
    return data as Map<String, dynamic>;
  }

  // =====================================================================
  // Caregiver dashboard
  // =====================================================================

  Future<List<Map<String, dynamic>>> caregiverPatients(String caregiverId) async {
    final data =
        await getJson('${AppConfig.apiV1}/dashboard/caregivers/$caregiverId/patients');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> patientSummary(String patientId) async {
    final data = await getJson('${AppConfig.apiV1}/dashboard/patients/$patientId/summary');
    return data as Map<String, dynamic>;
  }

  Future<void> acknowledgeAlert(String alertId) async {
    await postJson('${AppConfig.apiV1}/dashboard/alerts/$alertId/acknowledge');
  }

  // =====================================================================
  // Caregiver schedule editing + DPDP audit (same endpoints as the web
  // dashboard; server enforces roles/tiers — client only reflects them).
  // =====================================================================

  Future<void> createSchedule({
    required String patientId,
    required String reminderType, // medicine|water|food|exercise
    required String cadence, // "08:00" | "daily@08:00,20:00"
  }) async {
    await postJson('${AppConfig.apiV1}/reminders/schedules',
        body: {
          'patient_id': patientId,
          'reminder_type': reminderType,
          'cadence': cadence,
        });
  }

  Future<void> deleteSchedule(String scheduleId) async {
    // Plain DELETE with auth; no body (matches web dashboard contract).
    final res =
        await _send('DELETE', '${AppConfig.apiV1}/reminders/schedules/$scheduleId');
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw ApiException('HTTP ${res.statusCode}', statusCode: res.statusCode);
  }
  /// Read-only DPDP audit trail. Admin-only server-side; other roles get 403
  /// which callers surface as "admin-only".
  Future<List<Map<String, dynamic>>> auditLogs({int limit = 50}) async {
    final data = await getJson('${AppConfig.apiV1}/compliance/audit-logs?limit=$limit');
    return (data as List).cast<Map<String, dynamic>>();
  }
}

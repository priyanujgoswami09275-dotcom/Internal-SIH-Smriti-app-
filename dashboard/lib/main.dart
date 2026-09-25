/// ElderCare Caregiver Dashboard (Flutter Web) — multi-patient view for
/// family caregivers, ASHA workers, and clinicians.
///
/// Wired to the backend dashboard endpoints:
///   POST /api/v1/auth/login           -> JWT
///   GET  /api/v1/dashboard/caregivers/{id}/patients
///   GET  /api/v1/dashboard/patients/{id}/summary
///   POST /api/v1/dashboard/alerts/{id}/acknowledge
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/monad_theme.dart';
import 'widgets/risk_screening_card.dart';
import 'widgets/risk_intake_form.dart';
import 'widgets/monad/monad_pill_button.dart';
import 'widgets/rag_upload_widget.dart';

import 'config.dart';

enum ApiErrorKind { network, rateLimited, forbidden, server, http }

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.retryAfter,
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  bool get isNetworkError => kind == ApiErrorKind.network;
  bool get isRateLimited => kind == ApiErrorKind.rateLimited;
  bool get isForbidden => kind == ApiErrorKind.forbidden;
  bool get isServerError => kind == ApiErrorKind.server;

  int? get retryAfterSeconds => retryAfter?.inSeconds;

  @override
  String toString() => message;
}

String describeApiError(ApiException error, {String? context}) {
  if (error.kind == ApiErrorKind.rateLimited) {
    final wait = error.retryAfter == null
        ? ''
        : ' Retry after ${error.retryAfter!.inSeconds} seconds.';
    return 'Rate limit reached.$wait';
  }
  if (error.kind == ApiErrorKind.network) {
    return 'Network unavailable. Check your connection and retry.';
  }
  if (error.kind == ApiErrorKind.forbidden) {
    if (context == 'audit') {
      return 'Audit trail request denied by the server (403). ${error.message}';
    }
    return 'Access denied by the server (403). ${error.message}';
  }
  if (error.kind == ApiErrorKind.server) {
    return 'Server error (${error.statusCode ?? 500}): ${error.message}. Try again.';
  }
  return 'Request failed (${error.statusCode ?? 0}). ${error.message}';
}

// =====================================================================

// =====================================================================
// Tiny typed client (self-contained; no shared package dependency)
//
// Tokens are persisted (localStorage on web) so a page reload keeps the
// session, and a 401 transparently refreshes using the refresh token and
// retries once — fixing the 15-minute access-token expiry killing the UI.
// =====================================================================

class Api {
  static String? _token;
  static String? _refreshToken;
  static String? _userId;
  static String? _role;

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kUserId = 'user_id';
  static const _kRole = 'user_role';

  static String? get userId => _userId;
  static String? get role => _role;
  static bool get hasSession => _token != null && _refreshToken != null;

  /// Injectable client seam for tests (minimal: production uses the
  /// top-level http helpers; tests set a fake via [testClient]).
  static http.Client? _testClient;

  @visibleForTesting
  static set testClient(http.Client? c) => _testClient = c;

  @visibleForTesting
  static http.Client? get testClient => _testClient;

  @visibleForTesting
  static void setTestSession(
      {String? token, String? refreshToken, String? userId, String? role}) {
    _token = token;
    _refreshToken = refreshToken;
    _userId = userId;
    _role = role ?? 'admin';
  }

  @visibleForTesting
  static void resetForTest() {
    _token = null;
    _refreshToken = null;
    _userId = null;
    _role = null;
    _refreshInFlight = null;
    _testClient = null;
  }

  /// Load any persisted session at startup.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kAccess);
    _refreshToken = prefs.getString(_kRefresh);
    _userId = prefs.getString(_kUserId);
    _role = prefs.getString(_kRole);
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) {
      await prefs.setString(_kAccess, _token!);
    } else {
      await prefs.remove(_kAccess);
    }
    if (_refreshToken != null) {
      await prefs.setString(_kRefresh, _refreshToken!);
    } else {
      await prefs.remove(_kRefresh);
    }
    if (_userId != null) {
      await prefs.setString(_kUserId, _userId!);
    } else {
      await prefs.remove(_kUserId);
    }
    if (_role != null) {
      await prefs.setString(_kRole, _role!);
    } else {
      await prefs.remove(_kRole);
    }
  }

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Future<http.Response> _rawPost(Uri url,
      {Map<String, String>? headers, Object? body}) {
    final c = _testClient;
    if (c != null) return c.post(url, headers: headers, body: body);
    return http.post(url, headers: headers, body: body);
  }

  static Future<http.Response> _rawGet(Uri url,
      {Map<String, String>? headers}) {
    final c = _testClient;
    if (c != null) return c.get(url, headers: headers);
    return http.get(url, headers: headers);
  }

  static Future<http.Response> _rawDelete(Uri url,
      {Map<String, String>? headers}) {
    final c = _testClient;
    if (c != null) return c.delete(url, headers: headers);
    return http.delete(url, headers: headers);
  }

  static Future<http.StreamedResponse> _rawSend(http.BaseRequest request) {
    final c = _testClient;
    if (c != null) return c.send(request);
    return request.send();
  }

  static Future<http.Response> _networkCall(
      Future<http.Response> Function() send) async {
    try {
      return await send();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Network request failed. Check your connection and retry.',
      );
    }
  }

  static Future<http.StreamedResponse> _networkSend(
      Future<http.StreamedResponse> Function() send) async {
    try {
      return await send();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        kind: ApiErrorKind.network,
        message: 'Network request failed. Check your connection and retry.',
      );
    }
  }

  static Future<dynamic> _post(String path,
      {Map<String, dynamic>? body, bool auth = true}) async {
    return _withRefresh(
        auth,
        () => _networkCall(() => _rawPost(Uri.parse('$apiBaseUrl$path'),
            headers: _headers(), body: jsonEncode(body ?? const {}))));
  }

  static Future<dynamic> _get(String path, {bool auth = true}) async {
    return _withRefresh(
        auth,
        () => _networkCall(
            () => _rawGet(Uri.parse('$apiBaseUrl$path'), headers: _headers())));
  }

  /// Shared refresh-retry core at the raw-response level.
  static Future<http.Response> _withRefreshResponse(
      Future<http.Response> Function() send) async {
    var res = await send();
    if (res.statusCode == 401 && await _refresh()) {
      res = await send();
    }
    return res;
  }

  /// Run a request; on 401 (expired access token) refresh once and retry.
  static Future<dynamic> _withRefresh(
      bool auth, Future<http.Response> Function() send) async {
    if (!auth) return _decode(await send());
    return _decode(await _withRefreshResponse(send));
  }

  /// DELETE with the same refresh-retry as GET/POST. Returns the raw
  /// response so the `deleteSchedule` call-site `_decode` is unchanged.
  static Future<http.Response> _delete(String path) => _withRefreshResponse(
      () => _networkCall(
          () => _rawDelete(Uri.parse('$apiBaseUrl$path'), headers: _headers())));

  static Duration? _retryAfter(http.Response res) {
    final raw = res.headers['retry-after'] ?? res.headers['Retry-After'];
    if (raw == null || raw.isEmpty) return null;
    final seconds = int.tryParse(raw);
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    final date = DateTime.tryParse(raw);
    if (date == null) return null;
    final difference = date.difference(DateTime.now());
    return difference.isNegative ? Duration.zero : difference;
  }

  static dynamic _decode(http.Response res) {
    dynamic data;
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body);
      } catch (_) {
        data = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final detail = data is Map && data['detail'] != null
        ? data['detail'].toString()
        : 'HTTP ${res.statusCode}';
    final kind = res.statusCode == 429
        ? ApiErrorKind.rateLimited
        : res.statusCode == 403
            ? ApiErrorKind.forbidden
            : res.statusCode >= 500
                ? ApiErrorKind.server
                : ApiErrorKind.http;
    throw ApiException(
      kind: kind,
      message: detail,
      statusCode: res.statusCode,
      retryAfter: _retryAfter(res),
    );
  }

  /// In-flight refresh future: concurrent 401s await the same refresh
  /// instead of firing parallel refresh POSTs.
  static Future<bool>? _refreshInFlight;

  /// Exchange the refresh token for a fresh pair. Returns false when it fails
  /// (caller should send the user back to login). Serialized: concurrent
  /// callers share one in-flight refresh.
  static Future<bool> _refresh() {
    final ongoing = _refreshInFlight;
    if (ongoing != null) return ongoing;
    final fut = _doRefresh();
    _refreshInFlight = fut;
    fut.whenComplete(() => _refreshInFlight = null);
    return fut;
  }

  static Future<bool> _doRefresh() async {
    if (_refreshToken == null) return false;
    try {
      final res = await _rawPost(
        Uri.parse('$apiBaseUrl/api/v1/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );
      if (res.statusCode != 200) {
        await logout();
        return false;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      _token = data['access_token'] as String?;
      _refreshToken = data['refresh_token'] as String? ?? _refreshToken;
      await _persist();
      return _token != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> login(String phone, String password) async {
    final data = await _post('/api/v1/auth/login',
        body: {'phone': phone, 'password': password}, auth: false);
    _token = data['access_token'] as String;
    _refreshToken = data['refresh_token'] as String?;
    final me = await _get('/api/v1/auth/me');
    _userId = me['id'] as String?;
    _role = me['role'] as String?;
    await _persist();
  }

  /// Validate a restored session by fetching /auth/me (refreshing if needed).
  static Future<bool> validateSession() async {
    if (!hasSession) return false;
    try {
      final me = await _get('/api/v1/auth/me');
      _userId = me['id'] as String? ?? _userId;
      _role = me['role'] as String? ?? _role;
      await _persist();
      return _userId != null;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort server logout (POST /api/v1/auth/logout, access-token
  /// authed per backend/app/routes/auth.py) BEFORE clearing local state, so
  /// the server refresh token is revoked. Network/server errors are ignored:
  /// the local clear must always happen. Uses the raw client (never
  /// [_withRefresh]) to avoid refresh recursion.
  static Future<void> logout() async {
    final refreshToken = _refreshToken;
    try {
      if (_token != null) {
        await _rawPost(
          Uri.parse('$apiBaseUrl/api/v1/auth/logout'),
          headers: _headers(),
          body: jsonEncode({
            if (refreshToken != null) 'refresh_token': refreshToken,
          }),
        ).timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // best-effort only — fall through to the local clear.
    }
    _token = null;
    _refreshToken = null;
    _userId = null;
    _role = null;
    await _persist();
  }

  static Future<List<Map<String, dynamic>>> patients(String caregiverId) async {
    final data = await _get('/api/v1/dashboard/caregivers/$caregiverId/patients');
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> summary(String patientId) async {
    return await _get('/api/v1/dashboard/patients/$patientId/summary');
  }

  static Future<void> acknowledge(String alertId) async {
    await _post('/api/v1/dashboard/alerts/$alertId/acknowledge');
  }

  static Future<List<Map<String, dynamic>>> schedules(String patientId) async {
    final data = await _get('/api/v1/reminders/schedules/$patientId');
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<void> createSchedule(String patientId, String reminderType,
      String cadence) async {
    await _post('/api/v1/reminders/schedules',
        body: {'patient_id': patientId, 'reminder_type': reminderType, 'cadence': cadence});
  }

  static Future<void> deleteSchedule(String scheduleId) async {
    // plain DELETE, no body
    final res = await _delete('/api/v1/reminders/schedules/$scheduleId');
    _decode(res);
  }

  static Future<List<Map<String, dynamic>>> auditLogs({
    int offset = 0,
    int limit = 50,
  }) async {
    final data = await _get(
      '/api/v1/compliance/audit-logs?limit=$limit&offset=$offset',
    );
    return (data as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> riskScreeningConsent(
      String patientId) async {
    final data = await _get(
      '/api/v1/dashboard/patients/$patientId/risk-screening/consent',
    );
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<Map<String, dynamic>?> getRiskScreening(
      String patientId) async {
    try {
      final data = await _get('/api/v1/patients/$patientId/risk-screening');
      if (data is! Map) return null;
      final result = Map<String, dynamic>.from(data);
      if (result['status'] == 'not_assessed') return null;
      return result;
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// POST /api/v1/patients/{id}/risk-screening with Authorization header
  /// and refresh-retry (via [_post]). Throws with the server `detail` on
  /// 401/403/422 so callers surface it instead of failing silently.
  static Future<Map<String, dynamic>> submitRiskScreening(
      {required String patientId,
      required Map<String, dynamic> payload}) async {
    final data =
        await _post('/api/v1/patients/$patientId/risk-screening', body: payload);
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  /// POST /api/v1/reports/documents/upload as an authed multipart request.
  /// Backend contract (`backend/app/routes/reports.py`): multipart `file`
  /// part + `patient_id` / `doc_type` / `title` fields; staff roles +
  /// clinical access + `health_data` consent enforced server-side.
  /// Sends the auth header via [_headers] (Content-Type dropped so the
  /// multipart boundary survives) with refresh-retry via [_withRefresh].
  /// Throws with the server `detail` on failure so callers surface it.
  static Future<dynamic> uploadDocument({
    required String patientId,
    required Uint8List bytes,
    required String filename,
    String docType = 'prescription',
    String? title,
  }) async {
    return _withRefresh(true, () async {
      // patient_id is a query param on the FastAPI signature; it is also
      // sent as a form field so the contract holds either way.
      final uri = Uri.parse('$apiBaseUrl/api/v1/reports/documents/upload')
          .replace(queryParameters: {'patient_id': patientId});
      final req = http.MultipartRequest('POST', uri);
      final h = _headers()..remove('Content-Type');
      req.headers.addAll(h);
      req.fields['patient_id'] = patientId;
      req.fields['doc_type'] = docType;
      if (title != null && title.isNotEmpty) req.fields['title'] = title;
      req.files
          .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final streamed = await _networkSend(() => _rawSend(req));
      return http.Response.fromStream(streamed);
    });
  }
}

// =====================================================================
// Trend sparkline (pure CustomPaint — no chart dependency)
// =====================================================================

class TrendChart extends StatelessWidget {
  final List<double> values; // null-free; gaps already dropped by caller
  final String title;
  final String unitLabel;
  const TrendChart(
      {super.key, required this.values, required this.title, this.unitLabel = ''});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: Monad.softShape,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: Monad.monoCaption),
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              width: double.infinity,
              child: values.length < 2
                  ? Center(
                      child: Text('Not enough data yet', style: Monad.monoBodySm))
                  : CustomPaint(
                      painter: _TrendPainter(values: values, color: Monad.lakeBlue)),
            ),
            const SizedBox(height: 8),
            Text(
              values.length < 2
                  ? ''
                  : 'last ${values.length} active days · ${_range()}$unitLabel',
              style: Monad.monoCaption,
            ),
          ],
        ),
      ),
    );
  }

  String _range() {
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    return lo == hi ? lo.toStringAsFixed(0) : '${lo.toStringAsFixed(0)}–${hi.toStringAsFixed(0)}';
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _TrendPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      hi = lo + 1; // flat line
    }
    double x(int i) => i / (values.length - 1) * size.width;
    double y(double v) => size.height - 6 - (v - lo) / (hi - lo) * (size.height - 12);

    final line = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      line.lineTo(x(i), y(values[i]));
    }
    final fill = Path.from(line)
      ..lineTo(x(values.length - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();

    canvas.drawPath(fill, Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill);
    canvas.drawPath(line, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.values != values;
}



void main() async {
  validateApiConfig();
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  runApp(const CaregiverDashboardApp());
}

class CaregiverDashboardApp extends StatelessWidget {
  const CaregiverDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caregiver Dashboard — Smriti',
      debugShowCheckedModeBanner: false,
      theme: Monad.theme(),
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _checking = true;
  String? _userId;
  String? _role;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final ok = await Api.validateSession();
    if (!mounted) return;
    setState(() {
      _userId = ok ? Api.userId : null;
      _role = ok ? Api.role : null;
      _checking = false;
    });
  }

  void _onLoggedIn(String userId, String? role) => setState(() {
        _userId = userId;
        _role = role;
      });

  Future<void> _logout() async {
    await Api.logout();
    if (mounted) {
      setState(() {
        _userId = null;
        _role = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_userId != null) {
      return _DashboardScreen(
          caregiverId: _userId!, role: _role, onLogout: _logout);
    }
    return _LoginScreen(onLoggedIn: _onLoggedIn);
  }
}

// =====================================================================
// Login
// =====================================================================

class _LoginScreen extends StatefulWidget {
  final void Function(String userId, String? role) onLoggedIn;
  const _LoginScreen({required this.onLoggedIn});

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.login(_phone.text.trim(), _password.text);
      if (!mounted) return;
      widget.onLoggedIn(Api.userId!, Api.role);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = describeApiError(error));
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Monad.parchment,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: const BoxDecoration(
                    color: Monad.lakeBlue,
                    shape: BoxShape.circle,
                  ),
                ),
                Text('Caregiver Dashboard',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text('SMRITI · MEMORY ASSISTANCE PLATFORM',
                    textAlign: TextAlign.center,
                    style: Monad.monoCaption),
                const SizedBox(height: 32),
                TextField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _signIn(),
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center,
                      style: Monad.monoBodySm.copyWith(color: Monad.crimson)),
                ],
                const SizedBox(height: 24),
                MonadPillButton(
                  label: 'Sign In',
                  onPressed: _signIn,
                  busy: _busy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Dashboard
// =====================================================================

enum _ConsentState { checking, granted, required, unavailable }

enum _SelectionStatus { success, failed, stale }

class _DashboardScreen extends StatefulWidget {
  final String caregiverId;
  final String? role;
  final VoidCallback onLogout;
  const _DashboardScreen(
      {required this.caregiverId, required this.role, required this.onLogout});

  @override
  State<_DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<_DashboardScreen> {
  static const int _auditPageSize = 50;

  List<Map<String, dynamic>>? _patients;
  String? _selectedPatientId;
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;
  String? _refreshError;
  List<Map<String, dynamic>>? _schedules;
  String? _scheduleError;
  List<Map<String, dynamic>>? _auditLogs;
  String? _auditError;
  int _auditOffset = 0;
  bool _auditHasNext = false;
  bool _auditLoading = false;
  Map<String, dynamic>? _riskScreeningResult;
  RiskScreeningState _riskScreeningState = RiskScreeningState.notAssessed;
  String? _riskScreeningError;
  _ConsentState _consentState = _ConsentState.checking;
  String? _consentError;
  int _selectionGeneration = 0;

  bool _isClinicalView(Map summary) {
    final tier = summary['permission_tier'] as String?;
    if (tier != null) return tier == 'clinical';
    return summary['view'] == 'clinical';
  }

  bool _isCurrent(int generation, String patientId) =>
      mounted && generation == _selectionGeneration && _selectedPatientId == patientId;

  String _errorText(Object error, {String? context}) {
    if (error is ApiException) return describeApiError(error, context: context);
    return '$error';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_selectionGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _refreshError = null;
      _summary = null;
      _selectedPatientId = null;
      _schedules = null;
      _resetPatientState();
    });
    try {
      final patients = await Api.patients(widget.caregiverId);
      if (!mounted || generation != _selectionGeneration) return;
      setState(() {
        _patients = patients;
        _loading = patients.isEmpty ? false : _loading;
      });
      if (patients.isNotEmpty) {
        await _select(patients.first['patient_id'] as String, silent: true);
      }
    } catch (error) {
      if (!mounted || generation != _selectionGeneration) return;
      setState(() {
        _loading = false;
        _error = _errorText(error);
      });
    }
  }

  Future<_SelectionStatus> _select(
    String patientId, {
    bool silent = false,
  }) async {
    final generation = ++_selectionGeneration;
    final changed = _selectedPatientId != patientId;
    if (!mounted) return _SelectionStatus.stale;
    setState(() {
      _loading = !silent || changed || _summary == null;
      _error = null;
      _refreshError = null;
      if (changed) {
        _selectedPatientId = patientId;
        _summary = null;
        _schedules = null;
        _resetPatientState();
      }
    });
    try {
      final summary = await Api.summary(patientId);
      if (!_isCurrent(generation, patientId)) return _SelectionStatus.stale;

      List<Map<String, dynamic>>? schedules;
      String? scheduleError;
      try {
        schedules = await Api.schedules(patientId);
      } catch (error) {
        scheduleError = _errorText(error);
      }
      if (!_isCurrent(generation, patientId)) return _SelectionStatus.stale;

      var consentState = _ConsentState.checking;
      String? consentError;
      var riskState = RiskScreeningState.notAssessed;
      Map<String, dynamic>? riskResult;
      String? riskError;
      if (_isClinicalView(summary)) {
        try {
          final consent = await Api.riskScreeningConsent(patientId);
          if (!_isCurrent(generation, patientId)) return _SelectionStatus.stale;
          consentState = consent['health_data_consent'] == true
              ? _ConsentState.granted
              : _ConsentState.required;
          if (consentState == _ConsentState.granted) {
            try {
              riskResult = await Api.getRiskScreening(patientId);
              if (!_isCurrent(generation, patientId)) {
                return _SelectionStatus.stale;
              }
              riskState = riskResult == null
                  ? RiskScreeningState.notAssessed
                  : riskScreeningStateFromResponse(riskResult);
              if (riskState == RiskScreeningState.consentRequired) {
                consentState = _ConsentState.required;
              }
            } catch (error) {
              riskState = _riskStateForError(error);
              riskError = _errorText(error);
              if (error is ApiException && error.statusCode == 403) {
                consentState = _ConsentState.required;
              }
            }
          } else {
            riskState = RiskScreeningState.consentRequired;
          }
        } catch (error) {
          consentState = _ConsentState.unavailable;
          consentError = _errorText(error);
          riskState = _riskStateForError(error);
          riskError = consentError;
        }
      } else {
        consentState = _ConsentState.unavailable;
      }
      if (!_isCurrent(generation, patientId)) return _SelectionStatus.stale;

      setState(() {
        _selectedPatientId = patientId;
        _summary = summary;
        _schedules = schedules;
        _loading = false;
        _error = null;
        _refreshError = null;
        _consentState = consentState;
        _consentError = consentError;
        _riskScreeningResult = riskResult;
        _riskScreeningState = riskState;
        _riskScreeningError = riskError;
        _scheduleError = scheduleError;
      });
      return _SelectionStatus.success;
    } catch (error) {
      if (!_isCurrent(generation, patientId)) return _SelectionStatus.stale;
      final message = _errorText(error);
      setState(() {
        _loading = false;
        if (changed || _summary == null) {
          _error = message;
        } else {
          _refreshError = message;
        }
      });
      return _SelectionStatus.failed;
    }
  }

  void _resetPatientState() {
    _riskScreeningResult = null;
    _riskScreeningState = RiskScreeningState.notAssessed;
    _riskScreeningError = null;
    _consentState = _ConsentState.checking;
    _consentError = null;
    _scheduleError = null;
  }

  RiskScreeningState _riskStateForError(Object error) {
    if (error is ApiException) {
      if (error.isNetworkError) return RiskScreeningState.transportFailure;
      if (error.statusCode == 403 &&
          error.message.toLowerCase().contains('consent')) {
        return RiskScreeningState.consentRequired;
      }
      if (error.statusCode == 422) return RiskScreeningState.validationFailed;
      if (error.isServerError) return RiskScreeningState.inferenceFailed;
      if (error.statusCode == 404) return RiskScreeningState.notAssessed;
    }
    return RiskScreeningState.transportFailure;
  }

  Future<void> _addSchedule(String reminderType, String cadence) async {
    final pid = _selectedPatientId;
    if (pid == null) return;
    try {
      await Api.createSchedule(pid, reminderType, cadence);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add reminder: ${_errorText(error)}')),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$reminderType reminder added at $cadence')),
    );
    final outcome = await _select(pid, silent: true);
    if (outcome == _SelectionStatus.failed && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('Reminder added, but refresh failed: ${_refreshError ?? 'try again'}')),
        );
    }
  }

  Future<void> _removeSchedule(String scheduleId) async {
    final pid = _selectedPatientId;
    if (pid == null) return;
    try {
      await Api.deleteSchedule(scheduleId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove reminder: ${_errorText(error)}')),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reminder removed')),
    );
    final outcome = await _select(pid, silent: true);
    if (outcome == _SelectionStatus.failed && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('Reminder removed, but refresh failed: ${_refreshError ?? 'try again'}')),
        );
    }
  }

  Future<void> _toggleAudit() async {
    if (_auditLogs != null) {
      setState(() {
        _auditLogs = null;
        _auditError = null;
        _auditOffset = 0;
        _auditHasNext = false;
      });
      return;
    }
    await _loadAuditPage(0);
  }

  Future<void> _loadAuditPage(int offset) async {
    if (_auditLoading) return;
    setState(() {
      _auditLoading = true;
      _auditError = null;
    });
    try {
      final logs = await Api.auditLogs(
        offset: offset,
        limit: _auditPageSize,
      );
      if (!mounted) return;
      setState(() {
        _auditOffset = offset;
        _auditLogs = logs;
        _auditHasNext = logs.length == _auditPageSize;
        _auditLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _auditLogs ??= [];
        _auditError = _errorText(error, context: 'audit');
        _auditLoading = false;
      });
    }
  }

  Future<void> _ack(String alertId) async {
    final pid = _selectedPatientId;
    if (pid == null) return;
    try {
      await Api.acknowledge(alertId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not acknowledge alert: ${_errorText(error)}')),
        );
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alert acknowledged')),
    );
    final outcome = await _select(pid, silent: true);
    if (outcome == _SelectionStatus.failed && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('Alert acknowledged, but refresh failed: ${_refreshError ?? 'try again'}')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caregiver Dashboard'),
        actions: [
          if (widget.role == 'admin')
            IconButton(
                tooltip: 'Compliance audit trail (admin)',
                onPressed: _toggleAudit,
                icon: const Icon(Icons.receipt_long)),
          IconButton(
              tooltip: 'Refresh',
              onPressed: _selectedPatientId == null ? _load : () => _select(_selectedPatientId!),
              icon: const Icon(Icons.refresh)),
          IconButton(tooltip: 'Sign out', onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(fontSize: 17)),
              const SizedBox(height: 16),
              MonadPillButton(
                label: 'Retry',
                onPressed: _selectedPatientId == null
                    ? _load
                    : () => _select(_selectedPatientId!),
              ),
            ],
          ),
        ),
      );
    }
    final patients = _patients ?? const [];
    if (patients.isEmpty) {
      final message = switch (widget.role) {
        'asha_worker' => 'No patients are assigned to this staff account yet.',
        'clinician' || 'admin' =>
          'No patients are available in the clinical roster yet.',
        _ => 'No patients are linked to this account yet.',
      };
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, style: Monad.monoBodyLg, textAlign: TextAlign.center),
        ),
      );
    }
    final summary = _summary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final content = <Widget>[
          if (summary != null) _summaryContent(summary),
        ];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (wide)
              Row(children: [
                Expanded(child: _roster(patients)),
              ])
            else
              _roster(patients),
            const SizedBox(height: 16),
            if (_refreshError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Monad.tintGold,
                  borderRadius: BorderRadius.circular(Monad.radiusMin),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _refreshError!,
                        style: Monad.monoBodySm.copyWith(color: Monad.graphite),
                      ),
                    ),
                    TextButton(
                      onPressed: _selectedPatientId == null
                          ? _load
                          : () => _select(_selectedPatientId!),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            ...content,
            if (_auditLogs != null) ...[
              const SizedBox(height: 16),
              if (_auditError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _auditError!,
                          style: Monad.monoBodySm.copyWith(color: Monad.crimson),
                        ),
                      ),
                      TextButton(
                        onPressed: _auditLoading
                            ? null
                            : () => _loadAuditPage(_auditOffset),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              _auditPanel(),
            ],
          ],
        );
      },
    );
  }

  Widget _roster(List<Map<String, dynamic>> patients) {
    return Card(
      elevation: 0,
      shape: Monad.softShape,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedPatientId,
            isExpanded: true,
            hint: Text('Select patient', style: Monad.monoBody),
            items: patients.map((p) {
              return DropdownMenuItem<String>(
                value: p['patient_id'] as String,
                child: Text(
                  '${p['name']} · ${p['district'] ?? 'NER'} · '
                  '${p['cognitive_baseline'] ?? ''} · '
                  '${(p['relationship_type'] ?? '').toString().toUpperCase()}',
                  style: Monad.monoBody.copyWith(color: Monad.offBlack),
                ),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) _select(v);
            },
          ),
        ),
      ),
    );
  }

  Widget _summaryContent(Map<String, dynamic> s) {
    final isClinical = _isClinicalView(s);
    final consentGranted = _consentState == _ConsentState.granted;
    final accuracy = (s['accuracy_pct'] as num? ?? 0).toDouble();
    final compliance = (s['compliance_pct'] as num? ?? 0).toDouble();
    final remindersTotal = (s['reminders_total'] as num? ?? 0).toInt();
    final speed = (s['avg_response_time_ms'] as num? ?? 0).toDouble();
    final alerts = s['active_alerts'] as List? ?? const [];
    final flags = (s['clinical_flags'] as Map<String, dynamic>? ?? const {})
        .cast<String, dynamic>();
    final trends = (s['daily_trends'] as List? ?? const [])
        .cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isClinical) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Monad.tintGold,
              borderRadius: BorderRadius.circular(Monad.radiusMin),
              border: Border.all(color: Monad.ash, width: 1),
            ),
            child: const Row(children: [
              Icon(Icons.lock_outline, size: 22, color: Monad.graphite),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Basic view — clinical detail (accuracy, trends, flags) is '
                  'visible to linked clinical staff only.',
                  style: Monad.monoBodySm,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        // Metric tiles
        if (isClinical) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              final tiles = [
                _tile('Cognitive accuracy (7d)', '${accuracy.toStringAsFixed(0)}%',
                    '${s['games_played'] ?? 0} games', Monad.offBlack),
                // reminders_total == 0 means "no data", not 100%: the
                // backend still reports 100.0, so correct it client-side.
                _tile(
                    'Reminder compliance',
                    remindersTotal == 0
                        ? '—'
                        : '${compliance.toStringAsFixed(0)}%',
                    remindersTotal == 0
                        ? 'no reminders yet'
                        : '${s['reminders_acknowledged']}/${s['reminders_total']} acknowledged',
                    Monad.offBlack),
                _tile('Avg response time', speed > 0 ? '${(speed / 1000).toStringAsFixed(1)}s' : '—',
                    'last 7 days', Monad.offBlack),
              ];
              if (wide) {
                return Row(
                  children: tiles
                      .map((t) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: t)))
                      .toList(),
                );
              }
              return Column(children: [
                for (final t in tiles)
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: t),
              ]);
            },
          ),
          const SizedBox(height: 12),
        ],
        // Trend charts (clinical detail — hidden for basic tier by the backend)
        if (trends.isNotEmpty && isClinical) ...[
          LayoutBuilder(builder: (context, c) {
            final acc = trends
                .map((t) => (t['accuracy_pct'] as num?)?.toDouble())
                .whereType<double>()
                .toList();
            final rt = trends
                .map((t) => (t['avg_response_time_ms'] as num?)?.toDouble())
                .whereType<double>()
                .toList();
            // Aggregates pool all games per day — say so in the titles.
            final charts = [
              TrendChart(values: acc, title: 'Daily accuracy trend (14d), all games', unitLabel: '%'),
              TrendChart(values: rt, title: 'Response time trend (14d), all games', unitLabel: 'ms'),
            ];
            if (c.maxWidth >= 700) {
              return Row(children: [
                for (final ch in charts)
                  Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: ch)),
              ]);
            }
            return Column(children: [
              for (final ch in charts)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: ch),
            ]);
          }),
          const SizedBox(height: 12),
        ],
        if (_schedules != null || _scheduleError != null) _schedulesCard(),
        const SizedBox(height: 12),
        if (isClinical && consentGranted) ...[
          const SizedBox(height: 8),
          RagUploadWidget(
            key: ValueKey('rag-${_selectedPatientId ?? ''}'),
            patientId: _selectedPatientId ?? '',
          ),
        ] else if (isClinical &&
            (_consentState == _ConsentState.required ||
                _consentState == _ConsentState.unavailable)) ...[
          const SizedBox(height: 8),
          _consentNotice(
            _consentState == _ConsentState.required
                ? 'Medical document upload requires health_data consent.'
                : 'Medical document upload is unavailable until consent can be verified.',
          ),
        ],
        const SizedBox(height: 8),
        // Alerts
        if (alerts.isNotEmpty) ...[
          Text('ACTIVE RISK ALERTS', style: Monad.monoLabel),
          const SizedBox(height: 8),
          for (final a in alerts.cast<Map<String, dynamic>>())
            Card(
              elevation: 0,
              color: (a['severity'] == 'critical' || a['severity'] == 'warning')
                  ? Monad.tintCoral
                  : Monad.tintGold,
              shape: Monad.softShape,
              child: ListTile(
                leading: Icon(Icons.warning_amber_rounded,
                    color: (a['severity'] == 'critical' || a['severity'] == 'warning')
                        ? Monad.crimson
                        : Monad.graphite,
                    size: 30),
                title: Text(a['summary'] as String? ?? 'Alert', style: Monad.monoBody.copyWith(color: Monad.offBlack)),
                subtitle: Text('Type: ${a['trigger_type']} · ${a['severity']}', style: Monad.monoBodySm),
                trailing: TextButton(
                  onPressed: () => _ack(a['id'] as String),
                  child: const Text('Acknowledge'),
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        // Clinical insight
        if (isClinical)
          Card(
            elevation: 0,
            shape: Monad.softShape,
            child: ListTile(
              leading: Icon(
                flags['cognitive_drop_detected'] == true
                    ? Icons.trending_down
                    : Icons.trending_up,
                color: flags['cognitive_drop_detected'] == true ? Monad.crimson : Monad.offBlack,
                size: 32,
              ),
              title: Text(flags['cognitive_drop_detected'] == true
                  ? 'Cognitive drop detected (<60% accuracy)'
                  : 'Cognitive baseline stable', style: Monad.monoBody.copyWith(color: Monad.offBlack)),
              subtitle: Text('Reminder flag: ${flags['high_missed_reminders'] == true ? '3+ missed in 7 days' : 'none'}', style: Monad.monoBodySm),
            ),
          ),
        const SizedBox(height: 12),
        if (isClinical) ...[
          RiskScreeningCard(
            result: _riskScreeningResult,
            state: _riskScreeningState,
            errorMessage: _riskScreeningError ?? _consentError,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.medical_services, size: 18),
            label: const Text('Run Screening (32 inputs)'),
            onPressed: consentGranted
                ? () => showDialog(
                      context: context,
                      builder: (_) => RiskIntakeForm(
                        patientId: _selectedPatientId ?? '',
                        patientName: s['patient_name'] as String? ?? '',
                        onResult: (result) => setState(() {
                          _riskScreeningResult = result;
                          _riskScreeningState =
                              riskScreeningStateFromResponse(result);
                          _riskScreeningError = null;
                        }),
                        onFailure: (state, message) => setState(() {
                          _riskScreeningState = state;
                          _riskScreeningError = message;
                        }),
                      ),
                    )
                : null,
          ),
        ] else ...[
          _consentNotice(
            'Clinical screening, trends, and document controls are hidden for this basic server view.',
          ),
        ],
      ],
    );
  }

  Widget _consentNotice(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Monad.tintGold,
        borderRadius: BorderRadius.circular(Monad.radiusMin),
        border: Border.all(color: Monad.ash, width: 1),
      ),
      child: Row(children: [
        const Icon(Icons.lock_outline, size: 22, color: Monad.graphite),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: Monad.monoBodySm)),
      ]),
    );
  }

  Widget _schedulesCard() {
    final schedules = _schedules ?? const <Map<String, dynamic>>[];
    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reminder schedules', style: Monad.subheading),
            const SizedBox(height: 8),
            Text('Times are local (IST). Format: HH:MM, comma-separated for multiple.',
                style: Monad.monoCaption),
            if (_scheduleError != null) ...[
              const SizedBox(height: 8),
              Text(
                'Reminder schedules could not be loaded: $_scheduleError',
                style: Monad.monoBodySm.copyWith(color: Monad.terracotta),
              ),
            ],
            const SizedBox(height: 16),
            for (final s in schedules.cast<Map<String, dynamic>>())
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  s['reminder_type'] == 'medicine'
                      ? Icons.medication
                      : s['reminder_type'] == 'water'
                          ? Icons.water_drop
                          : s['reminder_type'] == 'food'
                              ? Icons.restaurant
                              : Icons.directions_walk,
                  color: Monad.offBlack,
                ),
                title: Text('${s['reminder_type']}'.toUpperCase(),
                    style: Monad.monoLabel),
                subtitle: Text('${s['cadence']} · ${s['is_active'] == true ? 'active' : 'paused'}', style: Monad.monoBodySm),
                trailing: IconButton(
                  tooltip: 'Remove schedule',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Monad.graphite,
                  onPressed: () => _removeSchedule(s['id'] as String),
                ),
              ),
            const SizedBox(height: 8),
            _addScheduleRow(),
          ],
        ),
      ),
    );
  }

  Widget _addScheduleRow() {
    const types = ['medicine', 'water', 'food', 'exercise'];
    String type = 'medicine';
    final timeCtl = TextEditingController(text: '08:00');
    return StatefulBuilder(
      builder: (context, setState) => Row(
        children: [
          DropdownButton<String>(
            value: type,
            items: [
              for (final t in types)
                DropdownMenuItem(value: t, child: Text(t.toUpperCase()))
            ],
            onChanged: (v) => setState(() => type = v ?? type),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: timeCtl,
              decoration: const InputDecoration(
                  isDense: true, border: OutlineInputBorder(), labelText: 'HH:MM'),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Add schedule',
            icon: const Icon(Icons.add_circle, color: Monad.lakeBlue, size: 32),
            onPressed: () => _addSchedule(type, timeCtl.text.trim()),
          ),
        ],
      ),
    );
  }

  Widget _auditPanel() {
    final logs = _auditLogs ?? const <Map<String, dynamic>>[];
    final previousOffset = _auditOffset <= _auditPageSize
        ? 0
        : _auditOffset - _auditPageSize;
    return Card(
      elevation: 0,
      color: Monad.periwinkleMist,
      shape: Monad.softShape,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AUDIT TRAIL · PAGE ${_auditOffset ~/ _auditPageSize + 1}',
                style: Monad.monoLabel),
            const SizedBox(height: 8),
            if (_auditLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (logs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No audit rows on this page.',
                    style: Monad.monoBodySm),
              )
            else
              Column(
                children: [
                  for (final log in logs.cast<Map<String, dynamic>>()) ...[
                    ListTile(
                      dense: true,
                      title: Text(
                        '${log['id']} · ${log['action']} · ${log['resource_type']}',
                        style: Monad.monoBodySm.copyWith(color: Monad.offBlack),
                      ),
                      subtitle: Text(
                        'resource ${log['resource_id']} · by ${log['user_id']} · '
                        '${log['timestamp']}'
                        '${log['ip_address'] != null ? ' · ${log['ip_address']}' : ''}\n'
                        'details: ${log['details'] is Map ? jsonEncode(log['details']) : log['details']?.toString() ?? '{}'}',
                        style: Monad.monoCaption,
                      ),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _auditOffset == 0 || _auditLoading
                      ? null
                      : () => _loadAuditPage(previousOffset),
                  child: const Text('PREVIOUS'),
                ),
                TextButton(
                  onPressed: !_auditHasNext || _auditLoading
                      ? null
                      : () => _loadAuditPage(
                          _auditOffset + _auditPageSize),
                  child: const Text('NEXT'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(String title, String value, String subtitle, Color color) {
    return Card(
      elevation: 0,
      shape: Monad.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: Monad.monoCaption),
            const SizedBox(height: 12),
            Text(value,
                style: Monad.subheading.copyWith(
                    fontSize: 32, letterSpacing: -0.64, color: color)),
            const SizedBox(height: 8),
            Text(subtitle, style: Monad.monoBodySm),
          ],
        ),
      ),
    );
  }
}

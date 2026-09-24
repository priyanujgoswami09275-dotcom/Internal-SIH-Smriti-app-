/// Auth session — holds the JWT pair + user profile and persists them with
/// shared_preferences so the patient/caregiver stays logged in across app
/// launches (refresh token allows silent re-login in low-connectivity areas).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shared_models.dart';
import 'api_service.dart';
import 'offline_sync_service.dart';

enum AuthStatus { restoring, unauthenticated, authenticated }

class AuthSession extends ChangeNotifier {
  AuthSession._() {
    // Dead sessions (rotated/expired refresh) bounce to login instead of
    // stranding the user, and silent refreshes persist across restarts.
    ApiService.onUnauthorized = () => logout();
    ApiService.onTokensRefreshed = (access, refresh) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAccess, access);
      await prefs.setString(_kRefresh, refresh);
    };
  }

  static final AuthSession instance = AuthSession._();

  static const _kAccess = 'auth.access';
  static const _kRefresh = 'auth.refresh';
  static const _kUser = 'auth.user';

  AuthStatus _status = AuthStatus.restoring;
  UserModel? _user;

  AuthStatus get status => _status;
  UserModel? get user => _user;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isPatient => _user?.role == Role.patient;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_kAccess);
    final refresh = prefs.getString(_kRefresh);
    final userRaw = prefs.getString(_kUser);

    if (access != null && refresh != null && userRaw != null) {
      _user = UserModel.fromJson(jsonDecode(userRaw) as Map<String, dynamic>);
      ApiService.instance.authToken = access;
      ApiService.instance.refreshToken = refresh;
      _status = AuthStatus.authenticated;
      OfflineSyncService.instance.setActiveAccount(_user?.id);
      notifyListeners();
      return;
    }

    _status = AuthStatus.unauthenticated;
    OfflineSyncService.instance.resetForLogout();
    notifyListeners();
  }

  Future<void> login({required String phone, required String password}) async {
    final tokens = await ApiService.instance.login(phone: phone, password: password);
    await _applyTokens(tokens);
  }

  Future<void> register({
    required String phone,
    required String password,
    required String name,
    String role = 'patient',
  }) async {
    final tokens = await ApiService.instance.register(
      phone: phone,
      password: password,
      role: role,
    );
    await _applyTokens(tokens);
    // A patient must have a PatientProfile to play/remind; create one bound
    // to this account on first registration.
    if (role == 'patient') {
      await _ensurePatientProfile(name);
    }
  }

  Future<void> _applyTokens(AuthTokens tokens) async {
    ApiService.instance.authToken = tokens.accessToken;
    ApiService.instance.refreshToken = tokens.refreshToken;
    _user = await ApiService.instance.me();
    _status = AuthStatus.authenticated;
    OfflineSyncService.instance.setActiveAccount(_user?.id);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, tokens.accessToken);
    await prefs.setString(_kRefresh, tokens.refreshToken);
    await prefs.setString(_kUser, jsonEncode(_user!.toJson()));
    notifyListeners();
  }

  Future<void> _ensurePatientProfile(String name) async {
    try {
      final existing = await ApiService.instance.myPatient();
      if (existing != null) return;
      final created = await ApiService.instance.createMyPatient(name: name);
      await ApiService.instance.grantConsent(patientId: created.id);
    } catch (e) {
      debugPrint('Could not ensure patient profile: $e');
    }
  }

  Future<void> logout() async {
    OfflineSyncService.instance.resetForLogout();
    try {
      await ApiService.instance.logout();
    } catch (_) {
      // Token may already be invalid; clear locally regardless.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kUser);
    _user = null;
    ApiService.instance.authToken = null;
    ApiService.instance.refreshToken = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}

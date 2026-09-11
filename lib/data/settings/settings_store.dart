import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/dtos.dart';

/// App settings store.
/// - `baseUrl` and `currentRouteId`: SharedPreferences (not sensitive).
/// - `field_token` (JWT) and the login session: the system's secure storage.
class SettingsStore {
  SettingsStore({FlutterSecureStorage? secure})
      : _secure = secure ??
            const FlutterSecureStorage(
              // EncryptedSharedPreferences (Jetpack Security): stable backend on
              // Android; the default (KeyStore) reads inconsistently after a
              // cold boot.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _kBaseUrl = 'base_url';
  static const _kCurrentRoute = 'current_route_id';
  static const _kToken = 'field_token';
  static const _kSession = 'field_session';

  final FlutterSecureStorage _secure;

  Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kBaseUrl);
  }

  Future<void> setBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, value.trim());
  }

  Future<String?> getCurrentRouteId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kCurrentRoute);
  }

  Future<void> setCurrentRouteId(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_kCurrentRoute);
    } else {
      await prefs.setString(_kCurrentRoute, value);
    }
  }

  Future<String?> getToken() async {
    try {
      return await _secure.read(key: _kToken);
    } catch (_) {
      // Never let a decryption failure bring down the request/UI.
      return null;
    }
  }

  Future<void> setToken(String value) =>
      _secure.write(key: _kToken, value: value.trim());

  Future<bool> hasToken() async {
    final t = await getToken();
    return t != null && t.isNotEmpty;
  }

  // ---- Login session (Spec 5, T5.1) ----
  //
  // The whole session (person + every ESP's token) lives in secure storage.
  // The ACTIVE ESP's token is mirrored into the legacy `field_token` slot,
  // so the API client and all existing flows keep working untouched — and
  // the manual paste path (CL1) keeps writing that same slot.

  Future<FieldSession?> getSession() async {
    try {
      final raw = await _secure.read(key: _kSession);
      if (raw == null || raw.isEmpty) return null;
      return FieldSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A corrupt or undecryptable session must never brick the app; the
      // worker simply logs in again (tokens are re-issued fresh, BR-FRESH).
      return null;
    }
  }

  /// Persists the session and mirrors the active ESP's token (if any chosen)
  /// into the `field_token` slot.
  Future<void> saveSession(FieldSession session) async {
    await _secure.write(key: _kSession, value: jsonEncode(session.toJson()));
    final active = session.activeEsp;
    if (active != null) {
      await setToken(active.fieldToken);
    }
  }

  /// CL5: makes one ESP active. Rewrites the mirrored token accordingly.
  Future<FieldSession?> setActiveEsp(int tenantId) async {
    final session = await getSession();
    if (session == null) return null;
    final updated = session.withActiveTenant(tenantId);
    await saveSession(updated);
    return updated;
  }

  /// T5.4 will call this on logout: wipes session and mirrored token. The
  /// capture queue is NOT touched here — it never is (CL4).
  Future<void> clearSession() async {
    await _secure.delete(key: _kSession);
    await _secure.delete(key: _kToken);
  }
}

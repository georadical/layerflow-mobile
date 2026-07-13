import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Almacén de configuración de la app.
/// - `baseUrl` y `currentRouteId`: SharedPreferences (no sensible).
/// - `field_token` (JWT): almacenamiento seguro del sistema.
class SettingsStore {
  SettingsStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  static const _kBaseUrl = 'base_url';
  static const _kCurrentRoute = 'current_route_id';
  static const _kToken = 'field_token';

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

  Future<String?> getToken() => _secure.read(key: _kToken);

  Future<void> setToken(String value) =>
      _secure.write(key: _kToken, value: value.trim());

  Future<bool> hasToken() async {
    final t = await getToken();
    return t != null && t.isNotEmpty;
  }
}

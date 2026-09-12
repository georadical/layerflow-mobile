/// App configuration constants (no secrets).
///
/// The backend `baseUrl` and the `field_token` do NOT live here: they are
/// configured at runtime from the Settings screen and stored in
/// `SettingsStore` (SharedPreferences + secure storage).
library;

class AppConfig {
  const AppConfig._();

  /// Logical name of the local SQLite file.
  static const String dbName = 'layerflow_capture';

  /// Network timeouts.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// Paths of the capture API contract (LayerFlow backend).
  static const String postPlacasPath = '/field/capture/placas';
  static String routeFramePath(String routeId) =>
      '/field/capture/route/$routeId';

  /// Routes assigned to the authenticated field worker.
  static const String assignedRoutesPath = '/field/routes';

  /// Field login (Spec 5): credentials → one fresh token per active ESP.
  static const String loginPath = '/field/login';

  /// Silent renewal; the 7-day grace window exists only here.
  static const String refreshPath = '/field/token/refresh';

  /// Local sync states.
  static const String syncPending = 'pending';
  static const String syncSynced = 'synced';
  static const String syncError = 'error';

  /// Outcomes of a manual send attempt (Spec 4, BR7). Stored per route so the
  /// worker can tell "never tried" from "tried and failed" after the message
  /// is gone.
  static const String pushOk = 'ok';
  static const String pushPartial = 'partial';
  static const String pushNetwork = 'network';
  static const String pushAuth = 'auth';
  static const String pushHttp = 'http';
}

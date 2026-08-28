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

  /// Local sync states.
  static const String syncPending = 'pending';
  static const String syncSynced = 'synced';
  static const String syncError = 'error';
}

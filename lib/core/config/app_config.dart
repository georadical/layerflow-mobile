/// Constantes de configuración de la app (no secretos).
///
/// El `baseUrl` del backend y el `field_token` NO viven aquí: se configuran en
/// tiempo de ejecución desde la pantalla de Ajustes y se guardan en
/// `SettingsStore` (SharedPreferences + almacenamiento seguro).
library;

class AppConfig {
  const AppConfig._();

  /// Nombre lógico del archivo SQLite local.
  static const String dbName = 'layerflow_capture';

  /// Timeouts de red.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// Rutas del contrato de la API de captura (backend LayerFlow).
  static const String postPlacasPath = '/field/capture/placas';
  static String routeFramePath(String routeId) =>
      '/field/capture/route/$routeId';

  /// Estados de sincronización local.
  static const String syncPending = 'pending';
  static const String syncSynced = 'synced';
  static const String syncError = 'error';
}

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/location/location_source.dart';
import '../data/api/api_client.dart';
import '../data/db/database.dart';
import '../data/repositories/capture_repository.dart';
import '../data/settings/settings_store.dart';
import '../data/sync/sync_service.dart';

/// Base de datos (drift). Vive lo que vive la app.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(settingsStoreProvider)),
);

final captureRepositoryProvider = Provider<CaptureRepository>(
  (ref) => CaptureRepository(ref.watch(databaseProvider)),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    ref.watch(apiClientProvider),
    ref.watch(captureRepositoryProvider),
  ),
);

/// Fuente de ubicación. MVP: NULA (coordinate-free). Aquí se enchufará la
/// implementación Bluetooth/NMEA en la fase GNSS, sin tocar el resto.
final locationSourceProvider =
    Provider<LocationSource>((ref) => const NullLocationSource());

/// Conectividad en vivo (para habilitar/deshabilitar sync). Emite primero el
/// estado actual (checkConnectivity no se auto-emite) y luego los cambios.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) async* {
    final connectivity = Connectivity();
    yield await connectivity.checkConnectivity();
    yield* connectivity.onConnectivityChanged;
  },
);

bool _isOnline(List<ConnectivityResult> r) =>
    r.any((e) => e != ConnectivityResult.none);

final isOnlineProvider = Provider<bool>((ref) {
  final conn = ref.watch(connectivityProvider);
  return conn.maybeWhen(data: _isOnline, orElse: () => false);
});

/// Ruta activa (persistida en Ajustes).
final currentRouteIdProvider =
    StateNotifierProvider<CurrentRouteNotifier, String?>(
  (ref) => CurrentRouteNotifier(ref.watch(settingsStoreProvider)),
);

class CurrentRouteNotifier extends StateNotifier<String?> {
  CurrentRouteNotifier(this._settings) : super(null) {
    _load();
  }

  final SettingsStore _settings;

  Future<void> _load() async {
    state = await _settings.getCurrentRouteId();
  }

  Future<void> setRoute(String? routeId) async {
    await _settings.setCurrentRouteId(routeId);
    state = routeId;
  }
}

/// Stream de capturas de una ruta (ordenadas por `orden`).
final capturesProvider =
    StreamProvider.family<List<Capture>, String>((ref, routeId) {
  return ref.watch(captureRepositoryProvider).watchCaptures(routeId);
});

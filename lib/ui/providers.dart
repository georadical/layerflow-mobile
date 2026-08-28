import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jwt.dart';
import '../core/location/location_source.dart';
import '../data/api/api_client.dart';
import '../data/db/database.dart';
import '../data/repositories/capture_repository.dart';
import '../data/settings/settings_store.dart';
import '../data/sync/sync_service.dart';

/// Database (drift). Lives as long as the app does.
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

/// Location source. MVP: NULL (coordinate-free). The Bluetooth/NMEA
/// implementation will plug in here during the GNSS phase, without touching
/// the rest.
final locationSourceProvider =
    Provider<LocationSource>((ref) => const NullLocationSource());

/// Live connectivity (to enable/disable sync). Emits the current state first
/// (checkConnectivity does not self-emit) and then the changes.
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

/// Active route (persisted in Settings).
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

/// State of the pasted field_token (to warn about expiry in the field).
enum TokenStatus { missing, malformed, expired, expiringSoon, ok }

/// field_token expiry info (`exp` claim, signature not verified).
/// Invalidate this provider after saving in Settings to refresh it.
final fieldTokenInfoProvider = FutureProvider<JwtInfo>((ref) async {
  final token = await ref.watch(settingsStoreProvider).getToken();
  return parseJwt(token);
});

final tokenStatusProvider = FutureProvider<TokenStatus>((ref) async {
  final token = await ref.watch(settingsStoreProvider).getToken();
  if (token == null || token.trim().isEmpty) return TokenStatus.missing;
  final info = parseJwt(token);
  if (info.isMalformed) return TokenStatus.malformed;
  if (info.isExpired) return TokenStatus.expired;
  if (info.expiresSoon()) return TokenStatus.expiringSoon;
  return TokenStatus.ok;
});

/// Stream of a route's captures (sorted by `orden`).
final capturesProvider =
    StreamProvider.family<List<Capture>, String>((ref, routeId) {
  return ref.watch(captureRepositoryProvider).watchCaptures(routeId);
});

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jwt.dart';
import '../core/location/location_source.dart';
import '../data/api/api_client.dart';
import '../data/api/dtos.dart';
import '../data/cache/assigned_routes_cache.dart';
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

final assignedRoutesCacheProvider =
    Provider<AssignedRoutesCache>((ref) => AssignedRoutesCache());

/// The assigned-route list plus where it came from.
class AssignedRoutesState {
  const AssignedRoutesState({required this.routes, required this.fromCache});

  final AssignedRoutes routes;

  /// True when the network failed and this is the last cached copy, so the
  /// screen can say so instead of passing stale data off as fresh.
  final bool fromCache;
}

/// Routes assigned to the worker: fetch, cache, and fall back to that cache.
///
/// The fallback is deliberately not applied to 401/403. Those mean the token
/// is wrong, and showing a cached list would invite the worker to tap a route
/// that cannot possibly load — the screen must send them to Ajustes instead.
final assignedRoutesProvider =
    AsyncNotifierProvider<AssignedRoutesNotifier, AssignedRoutesState>(
  AssignedRoutesNotifier.new,
);

class AssignedRoutesNotifier extends AsyncNotifier<AssignedRoutesState> {
  @override
  Future<AssignedRoutesState> build() => _fetch();

  /// Pull-to-refresh. Keeps the current list on screen while it reloads.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  Future<AssignedRoutesState> _fetch() async {
    final api = ref.read(apiClientProvider);
    final cache = ref.read(assignedRoutesCacheProvider);
    try {
      final routes = await api.getAssignedRoutes();
      await cache.save(routes);
      return AssignedRoutesState(routes: routes, fromCache: false);
    } on ApiException catch (e) {
      final isAuth = e.statusCode == 401 || e.statusCode == 403;
      if (isAuth) rethrow;
      final cached = await cache.load();
      if (cached == null) rethrow;
      return AssignedRoutesState(routes: cached, fromCache: true);
    }
  }
}

/// Pulls a route's frame and merges it locally, so the resume view owns its
/// own loading and error states instead of the caller pre-fetching for it.
///
/// Offline it is a no-op: the screen still opens on whatever the device holds
/// (A4). autoDispose so re-entering a route re-pulls rather than showing a
/// frame from an earlier visit.
final routeFrameProvider =
    FutureProvider.autoDispose.family<void, String>((ref, routeId) async {
  if (!ref.read(isOnlineProvider)) return;
  await ref.read(syncServiceProvider).pullFrame(routeId);
});

/// Stream of a route's captures (sorted by `orden`).
final capturesProvider =
    StreamProvider.family<List<Capture>, String>((ref, routeId) {
  return ref.watch(captureRepositoryProvider).watchCaptures(routeId);
});

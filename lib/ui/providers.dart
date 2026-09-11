import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
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

/// The login session (Spec 5). Null = logged out (or pre-login, CL1 paste).
final sessionProvider =
    AsyncNotifierProvider<SessionNotifier, FieldSession?>(SessionNotifier.new);

class SessionNotifier extends AsyncNotifier<FieldSession?> {
  @override
  Future<FieldSession?> build() => ref.read(settingsStoreProvider).getSession();

  /// POST /field/login. On success the session is persisted; with exactly
  /// one ESP it becomes active immediately (no pointless choice screen),
  /// with several the gate shows the choice (CL5). Throws ApiException for
  /// the screen to map (A1/A2/offline).
  Future<void> login({required String email, required String password}) async {
    final api = ref.read(apiClientProvider);
    final store = ref.read(settingsStoreProvider);

    final res = await api.login(email: email, password: password);
    final session = FieldSession(
      email: email.trim().toLowerCase(),
      workerNombre: res.workerNombre,
      workerDocumento: res.workerDocumento,
      esps: res.esps,
      activeTenantId: res.esps.length == 1 ? res.esps.single.tenantId : null,
    );
    await store.saveSession(session);
    state = AsyncData(session);
    _tokenChanged();
  }

  /// CL5: pick the active ESP. Rewrites the mirrored token.
  Future<void> chooseEsp(int tenantId) async {
    final updated =
        await ref.read(settingsStoreProvider).setActiveEsp(tenantId);
    if (updated != null) {
      state = AsyncData(updated);
      _tokenChanged();
    }
  }

  /// The mirrored token changed: everything derived from it must refetch.
  void _tokenChanged() {
    ref.invalidate(assignedRoutesProvider);
    ref.invalidate(fieldTokenInfoProvider);
    ref.invalidate(tokenStatusProvider);
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

/// Name of the ESP the current token belongs to.
///
/// Read from the cached route list rather than the network: the ESP is a
/// property of the session, not of a route, and screens that show it must not
/// pay for a request to do so. Null until the selector has run once.
/// Reads the cache only. Watching `assignedRoutesProvider` here would make any
/// screen that merely labels a route issue a request.
final espNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final cached = await ref.read(assignedRoutesCacheProvider).load();
  return cached?.esp;
});

/// A route's `codigo` as already stored on the device. Pure local read: it
/// never triggers a request, so screens like Home can label a route without
/// going to the network.
final storedRouteCodigoProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, routeId) async {
  final route = await ref.read(databaseProvider).getRoute(routeId);
  return route?.codigo;
});

/// Human label for a route: its codigo and the ESP it belongs to.
///
/// Joined with a separator rather than parentheses: the wire already sends
/// names like "ESP Isnos (muestra)", so wrapping would nest brackets. Degrades
/// gracefully — a missing ESP leaves the codigo alone, and a missing codigo
/// leaves a plain "Ruta", never a raw UUID.
String routeLabel({String? codigo, String? esp}) {
  final base = codigo == null ? 'Ruta' : 'Ruta $codigo';
  return esp == null || esp.isEmpty ? base : '$base · $esp';
}

/// A route's `codigo`, read from the device.
///
/// Only the selector knows the codigo up front; opening a route by its
/// `route_id` or resuming the active one does not. It is stored locally as
/// part of the frame merge, so the screen can recover it instead of falling
/// back to an anonymous "Ruta".
final routeCodigoProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, routeId) async {
  // Wait for the pull when one is happening: the codigo lands with the merge.
  // A failed or skipped pull still falls back to whatever is already stored.
  try {
    await ref.watch(routeFrameProvider(routeId).future);
  } catch (_) {
    // Offline or rejected: the local copy, if any, is still the best answer.
  }
  final route = await ref.read(databaseProvider).getRoute(routeId);
  return route?.codigo;
});

/// Drives a route's push. Nothing here runs on its own: every send and every
/// retry is triggered by the worker (Spec 3, BR1).
final pushProvider =
    NotifierProvider.family<PushNotifier, bool, String>(PushNotifier.new);

/// State is simply "a batch is in flight", which also guards against a double
/// send: a second tap while true is ignored (T3.5).
class PushNotifier extends FamilyNotifier<bool, String> {
  @override
  bool build(String routeId) => false;

  /// Returns the outcome, or throws ApiException for the caller to map.
  ///
  /// Every real attempt is recorded on the route — failures included — so
  /// the send bar can show it after the message is gone (Spec 4, BR7). A
  /// no-op (empty queue) is not an attempt and records nothing.
  Future<SyncResult?> send() async {
    if (state) return null;
    state = true;
    final repo = ref.read(captureRepositoryProvider);
    try {
      final result = await ref.read(syncServiceProvider).pushPending(arg);
      if (!result.isNoop) {
        await repo.recordPushAttempt(
          routeId: arg,
          outcome: result.isOk ? AppConfig.pushOk : AppConfig.pushPartial,
        );
      }
      return result;
    } on ApiException catch (e) {
      // No verdict reached the items (BR3); the attempt itself still counts.
      await repo.recordPushAttempt(
        routeId: arg,
        outcome: switch (e.statusCode) {
          null => AppConfig.pushNetwork,
          401 || 403 => AppConfig.pushAuth,
          _ => AppConfig.pushHttp,
        },
      );
      rethrow;
    } finally {
      state = false;
    }
  }
}

/// A route's row as stored on the device, watched live — the send bar reads
/// the last attempt from here (Spec 4, BR7).
final routeRowProvider = StreamProvider.autoDispose.family<Route?, String>(
  (ref, routeId) => ref.watch(databaseProvider).watchRoute(routeId),
);

/// How many of a route's rows are still waiting or were refused.
final pendingCountProvider = Provider.family<int, String>((ref, routeId) {
  final rows = ref.watch(capturesProvider(routeId)).valueOrNull ?? const [];
  return rows.where((c) => c.syncStatus != AppConfig.syncSynced).length;
});

/// Stream of a route's captures (sorted by `posicion`).
final capturesProvider =
    StreamProvider.family<List<Capture>, String>((ref, routeId) {
  return ref.watch(captureRepositoryProvider).watchCaptures(routeId);
});

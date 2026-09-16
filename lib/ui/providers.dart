import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/jwt.dart';
import '../core/location/location_source.dart';
import '../data/api/api_client.dart';
import '../data/api/dtos.dart';
import '../data/cache/assigned_routes_cache.dart';
import '../data/db/database.dart';
import '../core/survey/survey_pyramid.dart';
import '../data/repositories/capture_repository.dart';
import '../data/repositories/evidence_repository.dart';
import '../data/repositories/r1_directory_repository.dart';
import '../data/repositories/survey_repository.dart';
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

final r1DirectoryRepositoryProvider = Provider<R1DirectoryRepository>(
  (ref) => R1DirectoryRepository(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
    ref.watch(settingsStoreProvider),
  ),
);

/// Tenant of the active session's ESP; null in the paste flow, where the
/// typeahead has no directory to draw from.
final activeTenantIdProvider = Provider<int?>(
  (ref) => ref.watch(sessionProvider).valueOrNull?.activeTenantId,
);

final evidenceRepositoryProvider = Provider<EvidenceRepository>(
  (ref) => EvidenceRepository(ref.watch(databaseProvider)),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    ref.watch(apiClientProvider),
    ref.watch(captureRepositoryProvider),
    evidence: ref.watch(evidenceRepositoryProvider),
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

/// WiFi right now — the gate for ROUTINE photo uploads (CL-R5). Divergence
/// ships on any network; routine waits for a send made under WiFi.
final isOnWifiProvider = Provider<bool>((ref) {
  final conn = ref.watch(connectivityProvider);
  return conn.maybeWhen(
    data: (r) => r.contains(ConnectivityResult.wifi),
    orElse: () => false,
  );
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

  /// CL5: pick the active ESP. Rewrites the mirrored token. Also used by
  /// the Spec 6 switcher — the active route is cleared because it belonged
  /// to the previous ESP (BR5; a no-op on the login-time choice).
  Future<void> chooseEsp(int tenantId) async {
    final updated =
        await ref.read(settingsStoreProvider).setActiveEsp(tenantId);
    if (updated != null) {
      await ref.read(currentRouteIdProvider.notifier).setRoute(null);
      state = AsyncData(updated);
      _tokenChanged();
    }
  }

  /// CL2 — silent renewal, called on app open. Moves no capture data, so
  /// the manual-only doctrine is untouched; it only renews the credential.
  ///
  /// Refreshes when the ACTIVE token is expired (the server's 7-day grace
  /// decides if that still works) or expires within 7 days — the worker may
  /// be heading into weeks without signal, so renew with maximum runway.
  /// Recovery hierarchy: signal → refresh → login (field-login.md).
  Future<void> refreshIfNeeded() async {
    final session = state.valueOrNull;
    final active = session?.activeEsp;
    if (session == null || active == null) return;
    if (!ref.read(isOnlineProvider)) return;

    final info = parseJwt(active.fieldToken);
    if (!info.isExpired && !info.expiresSoon(thresholdDays: 7)) return;

    try {
      // The interceptor sends the mirrored (= active) token.
      final fresh = await ref.read(apiClientProvider).refreshToken();
      final updated = session.withEspToken(active.tenantId, fresh);
      await ref.read(settingsStoreProvider).saveSession(updated);
      state = AsyncData(updated);
      ref.invalidate(fieldTokenInfoProvider);
      ref.invalidate(tokenStatusProvider);
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        // Beyond grace, or revoked: the hierarchy's next step is login,
        // which re-issues every token fresh (BR-FRESH). Clearing the
        // session is what routes the gate there. The queue is untouched,
        // as always (CL4).
        await ref.read(settingsStoreProvider).clearSession();
        state = const AsyncData(null);
      }
      // Anything else (no route to host, 5xx): keep working with the
      // current token; the next app open retries. Silent by design.
    }
  }

  /// CL4: wipes tokens and session. The capture queue is NEVER touched —
  /// this person's unsent rows stay parked on the device, bound to their
  /// email, and resume when the SAME person logs back in.
  Future<void> logout() async {
    await ref.read(settingsStoreProvider).clearSession();
    // The active route belonged to the closed session's ESP.
    await ref.read(currentRouteIdProvider.notifier).setRoute(null);
    state = const AsyncData(null);
    _tokenChanged();
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
    // The cache slot follows the ACTIVE tenant (Spec 6, BR3): offline, ESP
    // B must fall back to B's own copy or to nothing — never to A's list.
    // Null (paste flow) keeps its single implicit slot.
    final session = await ref.read(sessionProvider.future);
    final tenantId = session?.activeTenantId;
    try {
      final routes = await api.getAssignedRoutes();
      await cache.save(routes, tenantId: tenantId);
      return AssignedRoutesState(routes: routes, fromCache: false);
    } on ApiException catch (e) {
      final isAuth = e.statusCode == 401 || e.statusCode == 403;
      if (isAuth) rethrow;
      final cached = await cache.load(tenantId: tenantId);
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
  // Opening a route online is a sync moment (CL-R4): refresh the R1
  // directory in the background. Fire-and-forget — capture NEVER blocks
  // on a stale directory, and a failure only means fewer suggestions.
  final tenantId = ref.read(activeTenantIdProvider);
  if (tenantId != null) {
    unawaited(
      ref.read(r1DirectoryRepositoryProvider).refresh(tenantId).catchError(
            (_) => const R1RefreshResult(unchanged: true, count: 0),
          ),
    );
  }
  await ref.read(syncServiceProvider).pullFrame(routeId);
});

/// Name of the ESP the current token belongs to.
///
/// From the session's active ESP when one exists — it follows a switch
/// instantly and needs no request (Spec 6). The cache stays as fallback for
/// the paste flow (per-tenant slots; null = the paste slot). Watching
/// `assignedRoutesProvider` here would make any screen that merely labels a
/// route issue a request.
final espNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final session = await ref.watch(sessionProvider.future);
  final active = session?.activeEsp;
  if (active != null) return active.espNombre;
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
      final owner = ref.read(queueOwnerProvider);
      final result =
          await ref.read(syncServiceProvider).pushPending(arg, owner: owner);
      if (!result.isNoop) {
        await repo.recordPushAttempt(
          routeId: arg,
          outcome: result.isOk ? AppConfig.pushOk : AppConfig.pushPartial,
        );
      }
      // CL-R5: the evidence leg rides the SAME gesture, after the placa
      // push so the census_codes exist. Its transport failures are silent
      // here (held rows just wait); verdicts are recorded per row.
      final evidence = await ref.read(syncServiceProvider).pushEvidence(
            arg,
            owner: owner,
            wifiAvailable: ref.read(isOnWifiProvider),
          );
      if (evidence.uploaded > 0 || evidence.failed > 0) {
        final extra = 'fotos: ${evidence.uploaded} subidas'
            '${evidence.failed > 0 ? ', ${evidence.failed} rechazadas' : ''}'
            '${evidence.held > 0 ? ', ${evidence.held} en espera' : ''}';
        return SyncResult(
          attempted: result.attempted,
          synced: result.synced,
          failed: result.failed,
          message: result.isNoop ? extra : '${result.message} · $extra',
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

/// The person key that owns new queue rows: the session's normalized email,
/// or null in the paste flow (unowned rows, visible to any session).
final queueOwnerProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider).valueOrNull?.email,
);

/// Unsent PHOTOS of a route. Separate from the capture count because a
/// routine photo waits for WiFi and can easily outlive its queue row —
/// the send bar must stay alive for it (E2E finding).
final pendingEvidenceCountProvider =
    StreamProvider.autoDispose.family<int, String>((ref, routeId) {
  final owner = ref.watch(queueOwnerProvider);
  return ref
      .watch(evidenceRepositoryProvider)
      .watchPendingCount(routeId, owner: owner);
});

/// How many of a route's rows are still waiting or were refused.
final pendingCountProvider = Provider.family<int, String>((ref, routeId) {
  final rows = ref.watch(capturesProvider(routeId)).valueOrNull ?? const [];
  return rows.where((c) => c.syncStatus != AppConfig.syncSynced).length;
});

/// Stream of a route's captures (sorted by `posicion`).
final capturesProvider =
    StreamProvider.family<List<Capture>, String>((ref, routeId) {
  final owner = ref.watch(queueOwnerProvider);
  return ref
      .watch(captureRepositoryProvider)
      .watchCaptures(routeId, owner: owner);
});

// ---- Extended survey (Spec 8, T8.5) ----

final surveyRepositoryProvider = Provider<SurveyRepository>(
  (ref) => SurveyRepository(ref.watch(databaseProvider)),
);

/// Live map of a route's surveys, keyed by the anchor's clientId — the resume
/// list hangs a per-unit survey-state chip from it (CL-E1), CL4-scoped.
final routeSurveysProvider =
    StreamProvider.autoDispose.family<Map<String, Survey>, String>(
  (ref, routeId) {
    final owner = ref.watch(queueOwnerProvider);
    return ref
        .watch(surveyRepositoryProvider)
        .watchSurveysForRoute(routeId, owner: owner)
        .map((list) => {for (final s in list) s.anchorClientId: s});
  },
);

/// Identity of the survey being edited: the anchor unit and its route.
class SurveyArgs {
  const SurveyArgs({required this.anchorClientId, required this.routeId});

  final String anchorClientId;
  final String routeId;

  @override
  bool operator ==(Object other) =>
      other is SurveyArgs &&
      other.anchorClientId == anchorClientId &&
      other.routeId == routeId;

  @override
  int get hashCode => Object.hash(anchorClientId, routeId);
}

/// Drives one predio's survey form (Spec 8, T8.5). Loads the persisted
/// structure (or a fresh unifamiliar), and every gesture auto-saves to drift
/// so a half-done survey is never memory-only (CL-E6). autoDispose so
/// re-entering reloads from the source of truth.
final surveyControllerProvider = AsyncNotifierProvider.autoDispose
    .family<SurveyController, SurveyStructure, SurveyArgs>(
  SurveyController.new,
);

class SurveyController
    extends AutoDisposeFamilyAsyncNotifier<SurveyStructure, SurveyArgs> {
  @override
  Future<SurveyStructure> build(SurveyArgs arg) async {
    final loaded =
        await ref.read(surveyRepositoryProvider).loadStructure(arg.anchorClientId);
    return loaded ?? SurveyStructure.unifamiliar();
  }

  Future<void> _apply(SurveyStructure next) async {
    state = AsyncData(next);
    await ref.read(surveyRepositoryProvider).saveSurvey(
          anchorClientId: arg.anchorClientId,
          routeId: arg.routeId,
          structure: next,
          owner: ref.read(queueOwnerProvider),
        );
  }

  SurveyStructure get _cur => state.requireValue;

  Future<void> setAnswers(int floor, int unit, SurveyAnswers answers) =>
      _apply(_cur.setAnswers(floor, unit, answers));

  Future<void> addUnit(int floor) => _apply(_cur.addUnit(floor));

  Future<void> addFloor() => _apply(_cur.addFloor());

  Future<void> removeUnit(int floor, int unit) =>
      _apply(_cur.removeUnit(floor, unit));

  Future<void> removeFloor(int floor) => _apply(_cur.removeFloor(floor));

  /// Declares the totalizador with its just-taken photo (CL-E4): the photo
  /// is queued as evidence (proposito=totalizador, always divergencia, bound
  /// to the anchor's client_id) and the 99/99 is added to the structure. It
  /// travels on the SAME Enviar as the placas, via /field/capture/evidence.
  Future<void> declareTotalizador(String photoPath) async {
    await ref.read(evidenceRepositoryProvider).enqueue(
          clientId: arg.anchorClientId,
          routeId: arg.routeId,
          filePath: photoPath,
          soporte: AppConfig.soporteDivergencia,
          proposito: AppConfig.propositoTotalizador,
          owner: ref.read(queueOwnerProvider),
        );
    await _apply(_cur.declareTotalizador(photo: photoPath));
  }

  /// Undeclares the totalizador before sending: drops the 99/99 and its
  /// queued photo (row + local file).
  Future<void> clearTotalizador() async {
    await ref.read(evidenceRepositoryProvider).remove(
          arg.anchorClientId,
          proposito: AppConfig.propositoTotalizador,
        );
    await _apply(_cur.clearTotalizador());
  }
}

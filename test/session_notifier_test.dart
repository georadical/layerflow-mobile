import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/api_client.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/settings/settings_store.dart';
import 'package:layerflow_capture/ui/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mem_secure.dart';

class _FakeLoginApi implements ApiClient {
  _FakeLoginApi({this.response, this.throwing, this.refreshResult});

  final LoginResponse? response;
  final ApiException? throwing;

  /// Returned by refreshToken; an ApiException value is thrown instead.
  final Object? refreshResult;

  String? lastEmail;
  int refreshCalls = 0;

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    if (throwing != null) throw throwing!;
    return response!;
  }

  @override
  Future<String> refreshToken() async {
    refreshCalls++;
    final r = refreshResult;
    if (r is ApiException) throw r;
    if (r is String) return r;
    throw UnimplementedError();
  }

  @override
  Future<AssignedRoutes> getAssignedRoutes() => throw UnimplementedError();

  @override
  Future<RouteFrame> getRouteFrame(String routeId) =>
      throw UnimplementedError();

  @override
  Future<PlacaBatchResponse> postPlacas(PlacaBatchRequest batch) =>
      throw UnimplementedError();
}

const _elias = LoginEsp(
  tenantId: 2,
  espNombre: 'ESP Elías',
  fieldWorkerId: 'fw-2',
  rutasAsignadas: 1,
  fieldToken: 'token-elias',
);
const _isnos = LoginEsp(
  tenantId: 3,
  espNombre: 'ESP Isnos (muestra)',
  fieldWorkerId: 'fw-3',
  rutasAsignadas: 1,
  fieldToken: 'token-isnos',
);

ProviderContainer _container(ApiClient api, SettingsStore store) {
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(api),
    settingsStoreProvider.overrideWithValue(store),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('login with ONE esp activates it immediately and mirrors its token',
      () async {
    final store = SettingsStore(secure: MemSecure());
    final api = _FakeLoginApi(
      response: const LoginResponse(workerNombre: 'Ana', esps: [_isnos]),
    );
    final c = _container(api, store);
    await c.read(sessionProvider.future);

    await c
        .read(sessionProvider.notifier)
        .login(email: '  Campo1@LayerFlow.co ', password: 'x');

    final session = c.read(sessionProvider).value!;
    expect(session.activeEsp!.tenantId, 3, reason: 'no pointless choice');
    expect(session.email, 'campo1@layerflow.co',
        reason: 'the person key is the NORMALIZED email (CL4)');
    expect(await store.getToken(), 'token-isnos');
  });

  test('login with TWO esps leaves the choice open (CL5), then chooseEsp',
      () async {
    final store = SettingsStore(secure: MemSecure());
    final api = _FakeLoginApi(
      response:
          const LoginResponse(workerNombre: 'Ana', esps: [_elias, _isnos]),
    );
    final c = _container(api, store);
    await c.read(sessionProvider.future);
    final notifier = c.read(sessionProvider.notifier);

    await notifier.login(email: 'campo1@layerflow.co', password: 'x');
    expect(c.read(sessionProvider).value!.activeEsp, isNull);

    await notifier.chooseEsp(2);
    expect(c.read(sessionProvider).value!.activeEsp!.espNombre, 'ESP Elías');
    expect(await store.getToken(), 'token-elias');
    // The choice survives a restart: it lives in the store, not in memory.
    expect((await store.getSession())!.activeTenantId, 2);
  });

  group('refreshIfNeeded (T5.3, CL2)', () {
    // Unsigned JWT with a real exp claim, enough for parseJwt.
    String jwtExpiring(Duration fromNow) {
      String seg(Map<String, dynamic> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      final exp = DateTime.now().add(fromNow).millisecondsSinceEpoch ~/ 1000;
      return '${seg({'alg': 'none'})}.${seg({'exp': exp})}.x';
    }

    FieldSession sessionWithExpiry(Duration fromNow) => FieldSession(
          email: 'campo1@layerflow.co',
          workerNombre: 'Ana',
          esps: [
            LoginEsp(
              tenantId: 3,
              espNombre: 'ESP Isnos (muestra)',
              fieldWorkerId: 'fw-3',
              fieldToken: jwtExpiring(fromNow),
            ),
          ],
          activeTenantId: 3,
        );

    ProviderContainer container(
      ApiClient api,
      SettingsStore store, {
      bool online = true,
    }) {
      final c = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
        settingsStoreProvider.overrideWithValue(store),
        isOnlineProvider.overrideWithValue(online),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('renews a token due within 7 days and persists it', () async {
      final store = SettingsStore(secure: MemSecure());
      await store.saveSession(sessionWithExpiry(const Duration(days: 2)));
      final api = _FakeLoginApi(refreshResult: 'token-fresh');
      final c = container(api, store);
      await c.read(sessionProvider.future);

      await c.read(sessionProvider.notifier).refreshIfNeeded();

      expect(api.refreshCalls, 1);
      expect(await store.getToken(), 'token-fresh',
          reason: 'the mirror must carry the renewed token');
      expect((await store.getSession())!.activeEsp!.fieldToken, 'token-fresh');
    });

    test('a token with plenty of life left is not refreshed', () async {
      final store = SettingsStore(secure: MemSecure());
      await store.saveSession(sessionWithExpiry(const Duration(days: 25)));
      final api = _FakeLoginApi(refreshResult: 'token-fresh');
      final c = container(api, store);
      await c.read(sessionProvider.future);

      await c.read(sessionProvider.notifier).refreshIfNeeded();

      expect(api.refreshCalls, 0);
    });

    test('offline: no request is even attempted', () async {
      final store = SettingsStore(secure: MemSecure());
      await store.saveSession(sessionWithExpiry(const Duration(days: 2)));
      final api = _FakeLoginApi(refreshResult: 'token-fresh');
      final c = container(api, store, online: false);
      await c.read(sessionProvider.future);

      await c.read(sessionProvider.notifier).refreshIfNeeded();

      expect(api.refreshCalls, 0);
    });

    test('401 beyond grace clears the session → the gate shows login',
        () async {
      final store = SettingsStore(secure: MemSecure());
      await store.saveSession(sessionWithExpiry(const Duration(days: -10)));
      final api = _FakeLoginApi(
          refreshResult: ApiException('beyond grace', statusCode: 401));
      final c = container(api, store);
      await c.read(sessionProvider.future);

      await c.read(sessionProvider.notifier).refreshIfNeeded();

      expect(c.read(sessionProvider).value, isNull);
      expect(await store.getSession(), isNull);
      expect(await store.getToken(), isNull);
    });

    test('a transport failure keeps session and token untouched', () async {
      final store = SettingsStore(secure: MemSecure());
      final session = sessionWithExpiry(const Duration(days: 2));
      await store.saveSession(session);
      final api = _FakeLoginApi(
          refreshResult: ApiException('Sin conexión con el backend.'));
      final c = container(api, store);
      await c.read(sessionProvider.future);

      await c.read(sessionProvider.notifier).refreshIfNeeded();

      expect(c.read(sessionProvider).value, isNotNull);
      expect(await store.getToken(), session.activeEsp!.fieldToken,
          reason: 'no verdict, no change — same doctrine as the queue');
    });
  });

  test('chooseEsp clears the active route — it belonged to the other ESP',
      () async {
    SharedPreferences.setMockInitialValues(
        {'current_route_id': 'route-of-isnos'});
    final store = SettingsStore(secure: MemSecure());
    final api = _FakeLoginApi(
      response:
          const LoginResponse(workerNombre: 'Ana', esps: [_elias, _isnos]),
    );
    final c = _container(api, store);
    await c.read(sessionProvider.future);
    // Materialise the notifier that holds the persisted active route.
    expect(await store.getCurrentRouteId(), 'route-of-isnos');

    await c
        .read(sessionProvider.notifier)
        .login(email: 'campo1@layerflow.co', password: 'x');
    await c.read(sessionProvider.notifier).chooseEsp(2);

    expect(await store.getCurrentRouteId(), isNull,
        reason: 'Spec 6 BR5: the active route never survives a switch');
  });

  test('a 401 leaves no session and no token behind', () async {
    final store = SettingsStore(secure: MemSecure());
    final api = _FakeLoginApi(throwing: ApiException('bad', statusCode: 401));
    final c = _container(api, store);
    await c.read(sessionProvider.future);

    await expectLater(
      c
          .read(sessionProvider.notifier)
          .login(email: 'campo1@layerflow.co', password: 'nope'),
      throwsA(isA<ApiException>()),
    );
    expect(c.read(sessionProvider).value, isNull);
    expect(await store.getToken(), isNull);
  });
}

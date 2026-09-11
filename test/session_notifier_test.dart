import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/api_client.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/settings/settings_store.dart';
import 'package:layerflow_capture/ui/providers.dart';

import 'support/mem_secure.dart';

class _FakeLoginApi implements ApiClient {
  _FakeLoginApi({this.response, this.throwing});

  final LoginResponse? response;
  final ApiException? throwing;
  String? lastEmail;

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
  Future<String> refreshToken() => throw UnimplementedError();

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

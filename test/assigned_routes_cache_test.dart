import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/cache/assigned_routes_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

AssignedRoutes _routes(String esp, String codigo) => AssignedRoutes(
      esp: esp,
      items: [
        RouteSummary(routeId: 'r-$codigo', codigo: codigo, estado: 'verificada')
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('each tenant falls back to ITS copy, never to another one (BR3)',
      () async {
    final cache = AssignedRoutesCache();
    await cache.save(_routes('ESP Elías', 'E10'), tenantId: 2);
    await cache.save(_routes('ESP Isnos', '10'), tenantId: 3);

    expect((await cache.load(tenantId: 2))!.esp, 'ESP Elías');
    expect((await cache.load(tenantId: 3))!.esp, 'ESP Isnos');
  });

  test('a tenant with no copy gets null — the tenant-isolation rule', () async {
    final cache = AssignedRoutesCache();
    await cache.save(_routes('ESP Elías', 'E10'), tenantId: 2);

    expect(await cache.load(tenantId: 3), isNull,
        reason: "ESP B offline must never be served ESP A's list");
    expect(await cache.load(), isNull,
        reason: 'the paste-flow slot is separate from every tenant slot');
  });

  test('the paste-flow slot (null tenant) still round-trips', () async {
    final cache = AssignedRoutesCache();
    await cache.save(_routes('ESP Isnos', '10'));

    expect((await cache.load())!.esp, 'ESP Isnos');
    await cache.clear();
    expect(await cache.load(), isNull);
  });
}

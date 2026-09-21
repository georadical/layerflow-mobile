import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/parada/face_prediction.dart';
import 'package:layerflow_capture/data/api/api_client.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/capture_repository.dart';
import 'package:layerflow_capture/ui/providers.dart';

import 'support/sqlite3.dart';

/// The provider never calls the network in these tests (paradas are seeded
/// straight into the cache), so a no-op ApiClient is enough.
class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation inv) => super.noSuchMethod(inv);
}

Future<AppDatabase?> _memoryDb() async {
  useSystemSqlite3();
  try {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    return db;
  } catch (_) {
    return null;
  }
}

R1DirectoryCompanion _r1(
  int tenant,
  String npn,
  String norm,
  String cruce,
  String placa,
) =>
    R1DirectoryCompanion.insert(
      tenantId: tenant,
      npn: npn,
      direccion: norm,
      direccionNorm: norm,
      manzana: const Value('001'),
      tipoVia: const Value('CARRERA'),
      numVia: const Value('2'),
      numCruce: Value(cruce),
      placa: Value(placa),
      parseOk: const Value(true),
    );

ProviderContainer _container(AppDatabase db, int? tenant, List<Capture> caps) =>
    ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(_NoApi()),
      activeTenantIdProvider.overrideWithValue(tenant),
      capturesProvider.overrideWith((ref, routeId) => Stream.value(caps)),
    ]);

void main() {
  const routeId = 'r1';
  const tenant = 1;

  test('assisted route: predicts the next placa, binds the face, persists dir',
      () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);

    // A face on the odd acera (CARRERA 2 # 4), manzana 001.
    await db.replaceR1Slice(tenant, [
      _r1(tenant, 'npn-09', 'CARRERA 2 # 4-09', '4', '09'),
      _r1(tenant, 'npn-15', 'CARRERA 2 # 4-15', '4', '15'),
      _r1(tenant, 'npn-23', 'CARRERA 2 # 4-23', '4', '23'),
    ]);
    // The parada the worker is standing at (direction not resolved yet).
    await db.upsertParada(ParadasCompanion.insert(
      stopId: 's1',
      routeId: routeId,
      faceSequence: 1,
      blockFaceId: 'bf1',
      manzana: const Value('001'),
      orientation: const Value('N'),
      updatedAt: DateTime.now(),
    ));
    // The first placa captured on the face, linked to R1 09 (the anchor).
    await CaptureRepository(db).appendCapture(
      routeId: routeId,
      placa: 'CARRERA 2 # 4-09',
      manzanaCatastral: '001',
      npn: 'npn-09',
      blockFaceId: 'bf1',
    );
    final caps = await (db.select(db.captures)
          ..where((c) => c.routeId.equals(routeId)))
        .get();

    final c = _container(db, tenant, caps);
    addTearDown(c.dispose);
    // Prime the streams the provider reads synchronously.
    await c.read(routeStopsProvider(routeId).future);
    await c.read(capturesProvider(routeId).future);

    final ctx = await c.read(paradaCaptureContextProvider(routeId).future);
    expect(ctx, isNotNull);
    expect(ctx!.parada.stopId, 's1');
    expect(ctx.parada.blockFaceId, 'bf1');
    expect(ctx.capturedOnFace, 1);
    expect(ctx.prediction!.direction, FaceDirection.ascendente);
    expect(ctx.expectedDireccion, 'CARRERA 2 # 4-15');
    expect(ctx.expectedRow!.npn, 'npn-15');

    // The resolved direction is persisted so a mid-face anchor does not stall.
    expect((await db.getParada('s1'))!.direction, 'ascendente');
  });

  test('unassisted route (no parada) → null context, classic flow', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);

    final c = _container(db, tenant, const []);
    addTearDown(c.dispose);
    await c.read(routeStopsProvider(routeId).future);
    await c.read(capturesProvider(routeId).future);

    final ctx = await c.read(paradaCaptureContextProvider(routeId).future);
    expect(ctx, isNull);
  });
}

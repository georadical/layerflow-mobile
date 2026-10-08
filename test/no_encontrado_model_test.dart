import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/capture_repository.dart';

import 'support/sqlite3.dart';

/// NE.3 — the local model for "No encontrado en campo": a negative record in a
/// SIBLING table (no capture row, no posicion), photo-exempt, undoable.
Future<AppDatabase?> _tryMemoryDb() async {
  useSystemSqlite3();
  try {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    return db;
  } catch (_) {
    return null;
  }
}

void main() {
  const routeId = 'route-1';

  test('append + read: stores its fields, no capture / no posicion consumed',
      () async {
    final db = await _tryMemoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    final id = await repo.appendNoEncontrado(
      routeId: routeId,
      direccionNorm: 'CALLE 13 # 3-20',
      npn: 'npn-20',
      manzana: '41551010100000327',
      stopId: 's1',
      observacion: 'demolido, hoy parqueadero',
      owner: 'ana@x.com',
    );

    // Scoped to the owner — an unscoped read hides an unsent owned row (CL4).
    final ne =
        (await repo.noEncontradosForRoute(routeId, owner: 'ana@x.com')).single;
    expect(ne.clientId, id);
    expect(ne.direccionNorm, 'CALLE 13 # 3-20');
    expect(ne.npn, 'npn-20');
    expect(ne.manzana, '41551010100000327');
    expect(ne.stopId, 's1');
    expect(ne.observacion, 'demolido, hoy parqueadero');
    expect(ne.syncStatus, AppConfig.syncPending);

    // A sibling record: no capture row exists, and no posicion was consumed.
    expect(await repo.capturesForRoute(routeId), isEmpty);
    expect(await repo.nextPosicion(routeId), 1);
  });

  test('observación / npn / manzana are optional (blank → null)', () async {
    final db = await _tryMemoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    await repo.appendNoEncontrado(
        routeId: routeId, direccionNorm: 'CALLE 13 # 3-20', observacion: '  ');
    final ne = (await repo.noEncontradosForRoute(routeId)).single;
    expect(ne.observacion, isNull);
    expect(ne.npn, isNull);
    expect(ne.manzana, isNull);
  });

  test('several not-founds coexist (distinct client_ids)', () async {
    final db = await _tryMemoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    final a = await repo.appendNoEncontrado(
        routeId: routeId, direccionNorm: 'CALLE 13 # 3-20');
    final b = await repo.appendNoEncontrado(
        routeId: routeId, direccionNorm: 'CALLE 13 # 3-26');
    expect(a, isNot(b));
    final rows = await repo.noEncontradosForRoute(routeId);
    expect(rows.map((n) => n.direccionNorm),
        containsAll(['CALLE 13 # 3-20', 'CALLE 13 # 3-26']));
  });

  test('undo deletes the not-found before send', () async {
    final db = await _tryMemoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    final id = await repo.appendNoEncontrado(
        routeId: routeId, direccionNorm: 'CALLE 13 # 3-20');
    expect(await repo.noEncontradosForRoute(routeId), hasLength(1));
    expect(await repo.deleteNoEncontrado(id), 1);
    expect(await repo.noEncontradosForRoute(routeId), isEmpty);
  });

  test("CL4: another person's unsent not-found is hidden", () async {
    final db = await _tryMemoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    await repo.appendNoEncontrado(
        routeId: routeId, direccionNorm: 'CALLE 13 # 3-20', owner: 'ana@x.com');

    expect(await repo.noEncontradosForRoute(routeId, owner: 'ana@x.com'),
        hasLength(1));
    expect(await repo.noEncontradosForRoute(routeId, owner: 'beto@x.com'),
        isEmpty);
    // An unscoped read sees only synced/unowned rows.
    expect(await repo.noEncontradosForRoute(routeId), isEmpty);
  });
}

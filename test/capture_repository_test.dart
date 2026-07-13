import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/capture_repository.dart';

/// Intenta crear una BD drift en memoria. Devuelve null si el host no tiene
/// sqlite3 nativo (p. ej. falta sqlite3.dll) para poder saltar el test en vez
/// de fallar.
Future<AppDatabase?> _tryMemoryDb() async {
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

  test('append: orden es monotónico y arranca en 1', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('sqlite3 nativo no disponible en el host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    await repo.appendCapture(routeId: routeId, placa: 'A');
    await repo.appendCapture(routeId: routeId, placa: 'B');
    await repo.appendCapture(routeId: routeId, placa: 'C');

    final rows = await repo.capturesForRoute(routeId);
    expect(rows.map((c) => c.orden), [1, 2, 3]);
    expect(rows.map((c) => c.placa), ['A', 'B', 'C']);
  });

  test('editar no cambia el orden y re-marca pending', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('sqlite3 nativo no disponible en el host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    final id = await repo.appendCapture(routeId: routeId, placa: 'A');
    await repo.markSynced(clientId: id, loc: 5, remoteId: 'r1');
    await repo.editCapture(clientId: id, placa: 'A corregida');

    final row = (await repo.capturesForRoute(routeId)).single;
    expect(row.orden, 1);
    expect(row.placa, 'A corregida');
    expect(row.syncStatus, 'pending');
  });

  test('placa en blanco se guarda como null', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('sqlite3 nativo no disponible en el host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    await repo.appendCapture(routeId: routeId, placa: '   ');
    final row = (await repo.capturesForRoute(routeId)).single;
    expect(row.placa, isNull);
  });

  test('mergeFrame reanuda items del servidor sin duplicar y continúa el orden',
      () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('sqlite3 nativo no disponible en el host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    // El servidor ya tenía 2 capturas.
    await repo.mergeFrame(RouteFrame(
      routeId: routeId,
      codigo: '10',
      items: const [
        RouteFrameItem(clientId: 's1', orden: 1, loc: 5, placa: 'C 5 1 11'),
        RouteFrameItem(clientId: 's2', orden: 2, loc: 10, placa: 'C 5 1 15'),
      ],
    ));

    var rows = await repo.capturesForRoute(routeId);
    expect(rows.length, 2);
    expect(rows.every((c) => c.syncStatus == 'synced'), isTrue);

    // La siguiente captura local debe ser orden 3 (append tras reanudar).
    expect(await repo.nextOrden(routeId), 3);

    // Re-merge del mismo frame: idempotente (no duplica).
    await repo.mergeFrame(RouteFrame(
      routeId: routeId,
      items: const [
        RouteFrameItem(clientId: 's1', orden: 1, loc: 5, placa: 'C 5 1 11'),
      ],
    ));
    rows = await repo.capturesForRoute(routeId);
    expect(rows.length, 2);
  });

  test('mergeFrame preserva capturas locales pendientes sin enviar', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('sqlite3 nativo no disponible en el host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    final localId = await repo.appendCapture(routeId: routeId, placa: 'LOCAL');
    await repo.mergeFrame(RouteFrame(
      routeId: routeId,
      items: const [
        RouteFrameItem(clientId: 's1', orden: 1, loc: 5, placa: 'SERVER'),
      ],
    ));

    final local = await db.getCapture(localId);
    expect(local, isNotNull);
    expect(local!.placa, 'LOCAL');
    expect(local.syncStatus, 'pending');
  });
}

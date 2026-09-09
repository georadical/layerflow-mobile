import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/capture_repository.dart';

import 'support/sqlite3.dart';

/// Tries to create an in-memory drift DB. Returns null when the host has no
/// native sqlite3 (e.g. missing sqlite3.dll) so the test can be skipped
/// instead of failing.
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

  test('append: orden is monotonic and starts at 1', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
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

  test('editing does not change orden and re-marks as pending', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
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

  test('blank placa is stored as null', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    await repo.appendCapture(routeId: routeId, placa: '   ');
    final row = (await repo.capturesForRoute(routeId)).single;
    expect(row.placa, isNull);
  });

  test(
      'mergeFrame resumes server items without duplicating and continues '
      'the orden', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    // The server already had 2 captures.
    await repo.mergeFrame(const RouteFrame(
      routeId: routeId,
      codigo: '10',
      items: [
        RouteFrameItem(clientId: 's1', orden: 1, loc: 5, placa: 'C 5 1 11'),
        RouteFrameItem(clientId: 's2', orden: 2, loc: 10, placa: 'C 5 1 15'),
      ],
    ));

    var rows = await repo.capturesForRoute(routeId);
    expect(rows.length, 2);
    expect(rows.every((c) => c.syncStatus == 'synced'), isTrue);

    // The next local capture must be orden 3 (append after resuming).
    expect(await repo.nextOrden(routeId), 3);

    // Re-merge of the same frame: idempotent (no duplicates).
    await repo.mergeFrame(const RouteFrame(
      routeId: routeId,
      items: [
        RouteFrameItem(clientId: 's1', orden: 1, loc: 5, placa: 'C 5 1 11'),
      ],
    ));
    rows = await repo.capturesForRoute(routeId);
    expect(rows.length, 2);
  });

  test('mergeFrame preserves unsent pending local captures', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    final localId = await repo.appendCapture(routeId: routeId, placa: 'LOCAL');
    await repo.mergeFrame(const RouteFrame(
      routeId: routeId,
      items: [
        RouteFrameItem(clientId: 's1', orden: 1, loc: 5, placa: 'SERVER'),
      ],
    ));

    final local = await db.getCapture(localId);
    expect(local, isNotNull);
    expect(local!.placa, 'LOCAL');
    expect(local.syncStatus, 'pending');
  });

  test('anchorLoc: stored loc wins; orden*5 only for a never-synced row', () {
    // Office already relocated this one: its loc is NOT orden*5 any more.
    // A blanket orden*5 here would point the mark at the wrong place.
    final moved = Capture(
      clientId: 'a',
      routeId: routeId,
      orden: 2,
      loc: 7,
      syncStatus: AppConfig.syncSynced,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(CaptureRepository.anchorLoc(moved), 7);

    final neverSynced = Capture(
      clientId: 'b',
      routeId: routeId,
      orden: 3,
      syncStatus: AppConfig.syncPending,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(CaptureRepository.anchorLoc(neverSynced), 15);
  });

  test('REGRESSION: editing the placa preserves the relocation mark', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);
    final id = await repo.appendCapture(routeId: routeId, placa: 'X');
    await repo.setInsAfter(clientId: id, insAfter: 10);

    // The exact path that would silently clear the mark under the
    // full-replacement contract (Spec 2.1, A3).
    await repo.editCapture(clientId: id, placa: 'X corregida');

    final row = (await repo.capturesForRoute(routeId)).single;
    expect(row.placa, 'X corregida');
    expect(row.insAfter, 10, reason: 'a placa fix must never drop the mark');
    expect(row.syncStatus, AppConfig.syncPending);
  });

  test('mergeFrame clears a local mark the office resolved (null wins)',
      () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    // A synced row with a mark, as it would look after push + markSynced.
    await repo.mergeFrame(const RouteFrame(
      routeId: routeId,
      items: [
        RouteFrameItem(clientId: 's1', orden: 1, loc: 5, insAfter: 10),
      ],
    ));
    expect((await repo.capturesForRoute(routeId)).single.insAfter, 10);

    // Office applied the shift: frame returns the unit clean, at a new loc.
    await repo.mergeFrame(const RouteFrame(
      routeId: routeId,
      items: [
        RouteFrameItem(clientId: 's1', orden: 1, loc: 15),
      ],
    ));
    final row = (await repo.capturesForRoute(routeId)).single;
    expect(row.loc, 15);
    expect(row.insAfter, isNull,
        reason: 'the frame is the source of truth on resume (BR5)');
  });

  test('setInsAfter guards the contract range 0-9999', () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);
    final id = await repo.appendCapture(routeId: routeId, placa: 'X');

    // One bad value would 422 the entire batch, not just its item (BR6).
    expect(() => repo.setInsAfter(clientId: id, insAfter: -1),
        throwsArgumentError);
    expect(() => repo.setInsAfter(clientId: id, insAfter: 10000),
        throwsArgumentError);
    await repo.setInsAfter(clientId: id, insAfter: 0); // start of route: valid
    expect((await repo.capturesForRoute(routeId)).single.insAfter, 0);
  });
}

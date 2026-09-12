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

  test('append: posicion is monotonic and starts at 1', () async {
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
    expect(rows.map((c) => c.posicion), [1, 2, 3]);
    expect(rows.map((c) => c.placa), ['A', 'B', 'C']);
  });

  test('editing does not change posicion and re-marks as pending', () async {
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
    expect(row.posicion, 1);
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
      'the posicion', () async {
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
        RouteFrameItem(clientId: 's1', posicion: 1, loc: 5, placa: 'C 5 1 11'),
        RouteFrameItem(clientId: 's2', posicion: 2, loc: 10, placa: 'C 5 1 15'),
      ],
    ));

    var rows = await repo.capturesForRoute(routeId);
    expect(rows.length, 2);
    expect(rows.every((c) => c.syncStatus == 'synced'), isTrue);

    // The next local capture must be posicion 3 (append after resuming).
    expect(await repo.nextPosicion(routeId), 3);

    // Re-merge of the same frame: idempotent (no duplicates).
    await repo.mergeFrame(const RouteFrame(
      routeId: routeId,
      items: [
        RouteFrameItem(clientId: 's1', posicion: 1, loc: 5, placa: 'C 5 1 11'),
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
        RouteFrameItem(clientId: 's1', posicion: 1, loc: 5, placa: 'SERVER'),
      ],
    ));

    final local = await db.getCapture(localId);
    expect(local, isNotNull);
    expect(local!.placa, 'LOCAL');
    expect(local.syncStatus, 'pending');
  });

  test('anchorLoc: stored loc wins; posicion*5 only for a never-synced row',
      () {
    // Office already relocated this one: its loc is NOT posicion*5 any more.
    // A blanket posicion*5 here would point the mark at the wrong place.
    final moved = Capture(
      clientId: 'a',
      routeId: routeId,
      posicion: 2,
      loc: 7,
      syncStatus: AppConfig.syncSynced,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(CaptureRepository.anchorLoc(moved), 7);

    final neverSynced = Capture(
      clientId: 'b',
      routeId: routeId,
      posicion: 3,
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
        RouteFrameItem(clientId: 's1', posicion: 1, loc: 5, insAfter: 10),
      ],
    ));
    expect((await repo.capturesForRoute(routeId)).single.insAfter, 10);

    // Office applied the shift: frame returns the unit clean, at a new loc.
    await repo.mergeFrame(const RouteFrame(
      routeId: routeId,
      items: [
        RouteFrameItem(clientId: 's1', posicion: 1, loc: 15),
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

  group('queue ownership (Spec 5, T5.4 / CL4)', () {
    test('an unsent row is invisible to another person and to the paste flow',
        () async {
      final db = await _tryMemoryDb();
      if (db == null) {
        markTestSkipped('native sqlite3 not available on the host');
        return;
      }
      addTearDown(db.close);
      final repo = CaptureRepository(db);

      // A synced row (shared truth) and A's unsent capture.
      await repo.mergeFrame(const RouteFrame(
        routeId: routeId,
        items: [RouteFrameItem(clientId: 's1', posicion: 1, loc: 5)],
      ));
      await repo.appendCapture(
          routeId: routeId, placa: 'DE A', owner: 'a@x.co');

      // A sees both; B and the paste flow see only the synced row.
      expect((await repo.capturesForRoute(routeId, owner: 'a@x.co')).length, 2);
      final forB = await repo.capturesForRoute(routeId, owner: 'b@x.co');
      expect(forB.length, 1,
          reason: "A's parked queue must not appear under B");
      expect(forB.single.syncStatus, AppConfig.syncSynced);
      expect((await repo.capturesForRoute(routeId)).length, 1);
    });

    test("the push scope excludes another person's parked rows", () async {
      final db = await _tryMemoryDb();
      if (db == null) {
        markTestSkipped('native sqlite3 not available on the host');
        return;
      }
      addTearDown(db.close);
      final repo = CaptureRepository(db);

      await repo.appendCapture(
          routeId: routeId, placa: 'DE A', owner: 'a@x.co');
      await repo.appendCapture(routeId: routeId, placa: 'LIBRE'); // unowned
      await repo.appendCapture(
          routeId: routeId, placa: 'DE B', owner: 'b@x.co');

      final forB = await repo.pending(routeId, owner: 'b@x.co');
      expect(forB.map((c) => c.placa), ['LIBRE', 'DE B'],
          reason: "B pushes their own rows and unowned ones, never A's");
    });

    test('pendingCountForOwner backs the logout warning', () async {
      final db = await _tryMemoryDb();
      if (db == null) {
        markTestSkipped('native sqlite3 not available on the host');
        return;
      }
      addTearDown(db.close);
      final repo = CaptureRepository(db);

      await repo.appendCapture(routeId: routeId, placa: 'A1', owner: 'a@x.co');
      await repo.appendCapture(
          routeId: 'route-2', placa: 'A2', owner: 'a@x.co');
      await repo.appendCapture(routeId: routeId, placa: 'B1', owner: 'b@x.co');

      expect(await repo.pendingCountForOwner('a@x.co'), 2,
          reason: 'device-wide, across routes, only this person + unowned');
    });

    test('editing a synced row hands its unsent content to the editor',
        () async {
      final db = await _tryMemoryDb();
      if (db == null) {
        markTestSkipped('native sqlite3 not available on the host');
        return;
      }
      addTearDown(db.close);
      final repo = CaptureRepository(db);

      await repo.mergeFrame(const RouteFrame(
        routeId: routeId,
        items: [RouteFrameItem(clientId: 's1', posicion: 1, loc: 5)],
      ));
      await repo.editCapture(
          clientId: 's1', placa: 'CORREGIDA', owner: 'a@x.co');

      final row =
          (await repo.capturesForRoute(routeId, owner: 'a@x.co')).single;
      expect(row.ownerEmail, 'a@x.co');
      expect(row.syncStatus, AppConfig.syncPending);
      // And that pending edit is now parked away from everyone else.
      expect(await repo.capturesForRoute(routeId, owner: 'b@x.co'), isEmpty);
    });
  });

  test('recordPushAttempt: first attempt inserts, the next one replaces it',
      () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    // No frame was ever pulled: the route row does not exist yet. The first
    // send attempt must create it, not crash (Spec 4, T4.1).
    await repo.recordPushAttempt(
        routeId: routeId, outcome: AppConfig.pushNetwork);
    var route = await db.getRoute(routeId);
    expect(route, isNotNull);
    expect(route!.lastPushOutcome, AppConfig.pushNetwork);
    expect(route.lastPushAt, isNotNull);

    await repo.recordPushAttempt(routeId: routeId, outcome: AppConfig.pushOk);
    route = await db.getRoute(routeId);
    expect(route!.lastPushOutcome, AppConfig.pushOk,
        reason: 'only the LAST attempt is remembered');
  });

  test('recordPushAttempt does not clobber the rest of the route row',
      () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    // A route as the frame merge leaves it, codigo included.
    await repo.mergeFrame(const RouteFrame(
      routeId: routeId,
      codigo: '10',
      items: [RouteFrameItem(clientId: 's1', posicion: 1, loc: 5)],
    ));

    await repo.recordPushAttempt(routeId: routeId, outcome: AppConfig.pushAuth);

    final route = await db.getRoute(routeId);
    expect(route!.codigo, '10',
        reason: 'the upsert must only touch the attempt columns');
    expect(route.lastPushOutcome, AppConfig.pushAuth);
  });

  test('office renumbering reaches a queued row: position updates, edits stay',
      () async {
    final db = await _tryMemoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);

    // A synced unit the worker then edits and marks (now pending, unsent).
    await repo.mergeFrame(const RouteFrame(
      routeId: routeId,
      items: [RouteFrameItem(clientId: 'u1', posicion: 6, loc: 30, placa: 'X')],
    ));
    await repo.editCapture(clientId: 'u1', placa: 'X corregida');
    await repo.setInsAfter(clientId: 'u1', insAfter: 5);

    // The office applies a shift meanwhile: the unit comes back at a new
    // position. Re-pushing the stale posicion 6 would collide with whichever
    // unit now holds loc 30 — on every retry, forever.
    await repo.mergeFrame(const RouteFrame(
      routeId: routeId,
      items: [RouteFrameItem(clientId: 'u1', posicion: 2, loc: 10, placa: 'X')],
    ));

    final row = (await repo.capturesForRoute(routeId)).single;
    expect(row.posicion, 2, reason: 'position belongs to the server');
    expect(row.loc, 10);
    expect(row.placa, 'X corregida',
        reason: 'unsent content belongs to the worker');
    expect(row.insAfter, 5, reason: 'the mark is unsent content too');
    expect(row.syncStatus, AppConfig.syncPending);
  });
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/api_client.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/parada_repository.dart';

import 'support/sqlite3.dart';

/// Fake /stops: returns whatever [stops] is set to.
class _FakeStopsApi implements ApiClient {
  _FakeStopsApi(this.stops);
  RouteStops stops;

  @override
  Future<RouteStops> getRouteStops(String routeId) async => stops;

  @override
  dynamic noSuchMethod(Invocation inv) => super.noSuchMethod(inv);
}

RouteStops _stops(String routeId, List<RouteStop> items) =>
    RouteStops(routeId: routeId, items: items);

RouteStop _stop(String id, int seq, {bool swept = false}) => RouteStop(
      stopId: id,
      faceSequence: seq,
      blockFaceId: 'bf-$id',
      faceIndex: seq,
      manzanaCatastral: '001',
      orientation: 'N',
      swept: swept,
    );

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

void main() {
  const routeId = 'route-1';

  test('refreshStops caches paradas; currentParada is the lowest unswept',
      () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final api = _FakeStopsApi(_stops(routeId, [
      _stop('s1', 1, swept: true),
      _stop('s2', 2),
      _stop('s3', 3),
    ]));
    final repo = ParadaRepository(db, api);

    await repo.refreshStops(routeId);
    expect((await repo.stopsForRoute(routeId)).length, 3);
    expect((await repo.currentParada(routeId))!.stopId, 's2');
  });

  test('markSwept advances the current parada and queues the sweep', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final api =
        _FakeStopsApi(_stops(routeId, [_stop('s1', 1), _stop('s2', 2)]));
    final repo = ParadaRepository(db, api);
    await repo.refreshStops(routeId);

    expect((await repo.currentParada(routeId))!.stopId, 's1');
    await repo.markSwept('s1');
    expect((await repo.currentParada(routeId))!.stopId, 's2');
    final pending = await repo.pendingSweeps(routeId);
    expect(pending.map((p) => p.stopId), ['s1']);
    expect(pending.single.sweptSynced, isFalse);
  });

  test('refreshStops preserves a still-unsynced local sweep (Q1)', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final api =
        _FakeStopsApi(_stops(routeId, [_stop('s1', 1), _stop('s2', 2)]));
    final repo = ParadaRepository(db, api);
    await repo.refreshStops(routeId);

    // Offline sweep of s1, not yet pushed.
    await repo.markSwept('s1');
    // The server still reports s1 as unswept (our mark has not reached it).
    api.stops = _stops(routeId, [_stop('s1', 1), _stop('s2', 2)]);
    await repo.refreshStops(routeId);

    final s1 = await db.getParada('s1');
    expect(s1!.swept, isTrue, reason: 'the pending local sweep is preserved');
    expect(s1.sweptSynced, isFalse);
    // The current parada is still s2, not back to s1.
    expect((await repo.currentParada(routeId))!.stopId, 's2');
  });

  test('refreshStops takes the server swept when nothing is pending', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final api = _FakeStopsApi(_stops(routeId, [_stop('s1', 1)]));
    final repo = ParadaRepository(db, api);
    await repo.refreshStops(routeId);
    expect((await db.getParada('s1'))!.swept, isFalse);

    // The office swept it (e.g. another device); a refresh reflects it.
    api.stops = _stops(routeId, [_stop('s1', 1, swept: true)]);
    await repo.refreshStops(routeId);
    final s1 = await db.getParada('s1');
    expect(s1!.swept, isTrue);
    expect(s1.sweptSynced, isTrue);
  });

  test(
      'refreshStops carries the terna + cardinal (address-profiles '
      'AP.1–AP.5)', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final api = _FakeStopsApi(_stops(routeId, [
      const RouteStop(
        stopId: 's1',
        faceSequence: 1,
        blockFaceId: 'bf1',
        tipoVia: 'CALLE',
        numVia: '11',
        numCruce: '3A',
        cardinal: 'SUR',
        cardinalPosicion: 'via',
      ),
    ]));
    final repo = ParadaRepository(db, api);
    await repo.refreshStops(routeId);

    final s1 = await db.getParada('s1');
    expect(s1!.tipoVia, 'CALLE');
    expect(s1.cardinal, 'SUR');
    expect(s1.cardinalPosicion, 'via');
  });

  test(
      'markSweepSynced confirms; markSweepError records and keeps pending '
      '(PC.5)', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final api = _FakeStopsApi(_stops(routeId, [_stop('s1', 1)]));
    final repo = ParadaRepository(db, api);
    await repo.refreshStops(routeId);
    await repo.markSwept('s1'); // optimistic-local, queues the push

    await repo.markSweepError('s1', 'Hay una parada anterior sin barrer.');
    var s1 = await db.getParada('s1');
    expect(s1!.sweptSynced, isFalse, reason: 'kept pending — retries itself');
    expect(s1.sweepError, 'Hay una parada anterior sin barrer.');
    expect((await repo.pendingSweeps(routeId)).map((p) => p.stopId), ['s1']);

    await repo.markSweepSynced('s1');
    s1 = await db.getParada('s1');
    expect(s1!.sweptSynced, isTrue);
    expect(s1.sweepError, isNull);
    expect(await repo.pendingSweeps(routeId), isEmpty);
  });

  test(
      'a fresh markSwept clears a stale sweepError (a new attempt '
      'supersedes the old verdict)', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final api = _FakeStopsApi(_stops(routeId, [_stop('s1', 1)]));
    final repo = ParadaRepository(db, api);
    await repo.refreshStops(routeId);
    await repo.markSweepError('s1', 'Faltan fotos por sincronizar.');

    await repo.markSwept('s1');
    expect((await db.getParada('s1'))!.sweepError, isNull);
  });

  test('refreshStops preserves a sweepError untouched by the refresh',
      () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final api = _FakeStopsApi(_stops(routeId, [_stop('s1', 1)]));
    final repo = ParadaRepository(db, api);
    await repo.refreshStops(routeId);
    await repo.markSweepError('s1', 'Faltan fotos por sincronizar.');

    await repo.refreshStops(routeId); // an unrelated re-pull of the route
    expect((await db.getParada('s1'))!.sweepError,
        'Faltan fotos por sincronizar.');
  });

  test('setDirection persists per face', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final api = _FakeStopsApi(_stops(routeId, [_stop('s1', 1)]));
    final repo = ParadaRepository(db, api);
    await repo.refreshStops(routeId);

    await repo.setDirection('s1', 'ascendente');
    expect((await db.getParada('s1'))!.direction, 'ascendente');
  });

  test('a re-planned route drops stops no longer sent', () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);
    final api =
        _FakeStopsApi(_stops(routeId, [_stop('s1', 1), _stop('s2', 2)]));
    final repo = ParadaRepository(db, api);
    await repo.refreshStops(routeId);
    expect((await repo.stopsForRoute(routeId)).length, 2);

    api.stops = _stops(routeId, [_stop('s1', 1)]); // s2 removed
    await repo.refreshStops(routeId);
    final ids = (await repo.stopsForRoute(routeId)).map((p) => p.stopId);
    expect(ids, ['s1']);
  });
}

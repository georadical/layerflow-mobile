import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/data/api/api_client.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/capture_repository.dart';
import 'package:layerflow_capture/data/sync/sync_service.dart';

import 'support/sqlite3.dart';

/// Stands in for the network. Each test says what the wire does; nothing here
/// touches HTTP.
class _FakeApi implements ApiClient {
  _FakeApi({this.respond, this.throwing});

  /// Builds the response from the batch the service actually sent.
  final PlacaBatchResponse Function(PlacaBatchRequest)? respond;
  final ApiException? throwing;

  PlacaBatchRequest? lastBatch;
  int calls = 0;

  @override
  Future<PlacaBatchResponse> postPlacas(PlacaBatchRequest batch) async {
    calls++;
    lastBatch = batch;
    if (throwing != null) throw throwing!;
    return respond!(batch);
  }

  @override
  Future<AssignedRoutes> getAssignedRoutes() => throw UnimplementedError();

  @override
  Future<RouteFrame> getRouteFrame(String routeId) =>
      throw UnimplementedError();

  @override
  Future<R1DirectoryResponse> getR1Directory({String? knownVersion}) =>
      throw UnimplementedError();

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> refreshToken() => throw UnimplementedError();
}

PlacaItemResult _ok(String clientId, int loc) =>
    PlacaItemResult(clientId: clientId, ok: true, id: 'r-$clientId', loc: loc);

PlacaItemResult _bad(String clientId, String error) =>
    PlacaItemResult(clientId: clientId, ok: false, error: error);

PlacaBatchResponse _response(List<PlacaItemResult> items) => PlacaBatchResponse(
      batchId: 'b1',
      total: items.length,
      created: items.where((i) => i.ok).length,
      updated: 0,
      errores: items.where((i) => !i.ok).length,
      items: items,
    );

void main() {
  const routeId = 'route-1';

  Future<AppDatabase?> memoryDb() async {
    useSystemSqlite3();
    try {
      final db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get();
      return db;
    } catch (_) {
      return null;
    }
  }

  /// Seeds `count` captures and returns the repository plus their clientIds.
  Future<(CaptureRepository, List<String>)> seed(
    AppDatabase db,
    int count,
  ) async {
    final repo = CaptureRepository(db);
    final ids = <String>[];
    for (var i = 1; i <= count; i++) {
      ids.add(await repo.appendCapture(routeId: routeId, placa: 'C $i'));
    }
    return (repo, ids);
  }

  test('nothing queued sends no request', () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final api = _FakeApi(respond: (_) => _response(const []));
    final result =
        await SyncService(api, CaptureRepository(db)).pushPending(routeId);

    expect(result.isNoop, isTrue);
    expect(api.calls, 0, reason: 'An empty queue must not fire a request.');
  });

  test('every item accepted marks the rows synced with the server loc',
      () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final (repo, ids) = await seed(db, 2);
    final api = _FakeApi(
      respond: (b) => _response([
        for (var i = 0; i < b.items.length; i++)
          _ok(b.items[i].clientId, (i + 1) * 5),
      ]),
    );

    final result = await SyncService(api, repo).pushPending(routeId);

    expect(result.synced, 2);
    expect(result.failed, 0);
    final rows = await repo.capturesForRoute(routeId);
    expect(rows.map((r) => r.syncStatus), everyElement(AppConfig.syncSynced));
    expect(rows.map((r) => r.loc), [5, 10]);
    expect(ids.length, 2);
  });

  test('a rejected item does not drag the accepted ones down', () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final (repo, ids) = await seed(db, 2);
    final api = _FakeApi(
      respond: (b) => _response([
        _ok(b.items[0].clientId, 5),
        _bad(b.items[1].clientId, 'Orden duplicado en la ruta.'),
      ]),
    );

    final result = await SyncService(api, repo).pushPending(routeId);

    expect(result.synced, 1);
    expect(result.failed, 1);
    final rows = await repo.capturesForRoute(routeId);
    expect(rows.first.syncStatus, AppConfig.syncSynced);
    expect(rows.last.syncStatus, AppConfig.syncError);
    // The reason must survive to the row: the worker has to be able to read it.
    expect(rows.last.syncError, 'Orden duplicado en la ruta.');
    expect(ids.length, 2);
  });

  test('an item missing from the response is never assumed sent', () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final (repo, _) = await seed(db, 2);
    // The server answers about the first item only.
    final api = _FakeApi(
      respond: (b) => _response([_ok(b.items[0].clientId, 5)]),
    );

    final result = await SyncService(api, repo).pushPending(routeId);

    expect(result.synced, 1);
    expect(result.failed, 1);
    final rows = await repo.capturesForRoute(routeId);
    expect(rows.last.syncStatus, AppConfig.syncError);
  });

  test('a transport failure leaves the queue untouched, not rejected',
      () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final (repo, _) = await seed(db, 2);
    final api = _FakeApi(
      throwing: ApiException('no autenticado', statusCode: 401),
    );

    await expectLater(
      SyncService(api, repo).pushPending(routeId),
      throwsA(isA<ApiException>()),
    );

    // Nothing was rejected on its merits, so no row may be marked `error`:
    // that badge means "the server refused this", and a 401 never got a
    // verdict on any item.
    final rows = await repo.capturesForRoute(routeId);
    expect(rows.map((r) => r.syncStatus), everyElement(AppConfig.syncPending));
    expect(rows.map((r) => r.syncError), everyElement(isNull));
  });

  test('retrying includes rows the server rejected, with the same client_id',
      () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final (repo, ids) = await seed(db, 1);

    final failing = _FakeApi(
      respond: (b) => _response([_bad(b.items[0].clientId, 'rechazado')]),
    );
    await SyncService(failing, repo).pushPending(routeId);
    expect((await repo.capturesForRoute(routeId)).single.syncStatus,
        AppConfig.syncError);

    final retry = _FakeApi(
      respond: (b) => _response([_ok(b.items[0].clientId, 5)]),
    );
    final result = await SyncService(retry, repo).pushPending(routeId);

    expect(result.synced, 1);
    // Idempotency rests on this: the retry carries the original client_id, so
    // the backend updates instead of creating a second unit.
    expect(retry.lastBatch!.items.single.clientId, ids.single);
    expect(retry.lastBatch!.batchId, isNot(failing.lastBatch!.batchId),
        reason: 'each attempt gets its own batch_id (BR7)');
  });

  test('INVARIANT: the pushed payload carries no coordinates', () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final (repo, _) = await seed(db, 1);
    final api = _FakeApi(
      respond: (b) => _response([_ok(b.items[0].clientId, 5)]),
    );

    await SyncService(api, repo).pushPending(routeId);

    final json = api.lastBatch!.toJson();
    final item = (json['items'] as List).single as Map<String, dynamic>;
    for (final key in [...json.keys, ...item.keys]) {
      expect(
        key,
        isNot(anyOf('lat', 'lon', 'latitude', 'longitude', 'coords', 'geom')),
      );
    }
  });

  test('the relocation mark travels on every push of the row', () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final (repo, ids) = await seed(db, 2);
    await repo.setInsAfter(clientId: ids.last, insAfter: 5);

    final api = _FakeApi(
      respond: (b) => _response([
        for (final i in b.items) _ok(i.clientId, i.posicion * 5),
      ]),
    );
    await SyncService(api, repo).pushPending(routeId);

    final items = api.lastBatch!.items;
    // Unmarked row: no ins_after key at all (omitted == null to the server).
    expect(items.first.insAfter, isNull);
    expect(items.first.toJson().containsKey('ins_after'), isFalse);
    // Marked row: the mark rides along — full-replacement contract (BR3).
    expect(items.last.insAfter, 5);
    expect(items.last.toJson()['ins_after'], 5);
  });
}

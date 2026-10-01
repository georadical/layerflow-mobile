import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/data/api/api_client.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/api/sync_dtos.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/capture_repository.dart';
import 'package:layerflow_capture/data/repositories/parada_repository.dart';
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

  /// Ordered log of wire calls across placas + sweeps, so a test can assert
  /// the per-parada interleave (PC.6): "placa:<ids>" and "sweep:<stopId>".
  final List<String> callLog = [];

  @override
  Future<PlacaBatchResponse> postPlacas(PlacaBatchRequest batch) async {
    calls++;
    lastBatch = batch;
    callLog.add('placa:${batch.items.map((i) => i.clientId).join(",")}');
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
  Future<void> uploadEvidence({
    required String clientId,
    required String soporte,
    required String filePath,
    String proposito = 'placa',
  }) =>
      throw UnimplementedError();

  @override
  Future<SyncPushResponse> pushSync(SyncPushRequest req) =>
      throw UnimplementedError();

  @override
  Future<RouteStops> getRouteStops(String routeId) =>
      throw UnimplementedError();

  /// stopId → what the wire does for THIS parada's swept push. Absent =
  /// UnimplementedError (tests that never touch the sweep leg).
  final Map<String, Future<void> Function()> sweptBehavior = {};
  final List<String> sweptCalls = [];

  @override
  Future<void> markSwept(String routeId, String stopId,
      {required bool swept}) async {
    sweptCalls.add(stopId);
    callLog.add('sweep:$stopId');
    final behavior = sweptBehavior[stopId];
    if (behavior == null) throw UnimplementedError();
    return behavior();
  }

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> refreshToken() => throw UnimplementedError();
}

// (Spec 7) The npn must ride on every push — see the dedicated test below.
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

  test(
      'a closed-route 409 leaves the queue untouched and carries its codigo '
      '(Spec 9)', () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final (repo, _) = await seed(db, 2);
    final api = _FakeApi(
      throwing: ApiException('captura cerrada',
          statusCode: 409, codigo: AppConfig.codeRutaPlacasCerrada),
    );

    // The codigo rides through the service so the UI can map the cause.
    await expectLater(
      SyncService(api, repo).pushPending(routeId),
      throwsA(isA<ApiException>()
          .having((e) => e.codigo, 'codigo', 'ruta_placas_cerrada')),
    );

    // Nothing was written server-side, and no row is marked on its merits.
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

  test('the sin_r1 finding travels on every push, never beside npn (CL-R7)',
      () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final (repo, ids) = await seed(db, 2);
    await repo.setSinR1(clientId: ids.last, sinR1: true);

    final api = _FakeApi(
      respond: (b) => _response([
        for (final i in b.items) _ok(i.clientId, i.posicion * 5),
      ]),
    );
    await SyncService(api, repo).pushPending(routeId);

    final items = api.lastBatch!.items;
    expect(items.first.toJson().containsKey('sin_r1'), isFalse,
        reason: 'nothing to declare: the server preserves what it holds');
    expect(items.last.toJson()['sin_r1'], true);
    expect(items.last.toJson().containsKey('npn'), isFalse,
        reason: 'mutually exclusive by contract');

    // And a RETRACTION must travel as an explicit false.
    await repo.setSinR1(clientId: ids.last, sinR1: false);
    await SyncService(api, repo).pushPending(routeId);
    expect(api.lastBatch!.items.last.toJson()['sin_r1'], false);
  });

  test('the npn link travels on every push of the row (Spec 7)', () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final (repo, ids) = await seed(db, 2);
    await repo.setNpn(clientId: ids.last, npn: 'npn-1');

    final api = _FakeApi(
      respond: (b) => _response([
        for (final i in b.items) _ok(i.clientId, i.posicion * 5),
      ]),
    );
    await SyncService(api, repo).pushPending(routeId);

    final items = api.lastBatch!.items;
    // Unlinked row: no npn key at all (omitting clears, by contract).
    expect(items.first.toJson().containsKey('npn'), isFalse);
    // Linked row: the link rides along, like the mark.
    expect(items.last.toJson()['npn'], 'npn-1');
  });

  test('the block_face_id binding travels on every push (Spec 10)', () async {
    final db = await memoryDb();
    if (db == null) {
      markTestSkipped('native sqlite3 not available on the host');
      return;
    }
    addTearDown(db.close);
    final repo = CaptureRepository(db);
    await repo.appendCapture(routeId: routeId, placa: 'A', blockFaceId: 'bf-9');
    await repo.appendCapture(routeId: routeId, placa: 'B'); // unbound

    final api = _FakeApi(
      respond: (b) => _response([
        for (final i in b.items) _ok(i.clientId, i.posicion * 5),
      ]),
    );
    await SyncService(api, repo).pushPending(routeId);

    final items = api.lastBatch!.items;
    expect(items.first.toJson()['block_face_id'], 'bf-9');
    // Unbound row: no key at all (omitting keeps, by contract).
    expect(items.last.toJson().containsKey('block_face_id'), isFalse);
  });

  group('pushSweeps (Spec 10, PC.5)', () {
    Future<void> seedParada(
      AppDatabase db,
      String stopId, {
      bool swept = true,
    }) =>
        db.upsertParada(ParadasCompanion.insert(
          stopId: stopId,
          routeId: routeId,
          faceSequence: 1,
          swept: Value(swept),
          sweptSynced: const Value(false),
          updatedAt: DateTime.now(),
        ));

    test('no pending sweeps: a no-op, the wire is never touched', () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      final api = _FakeApi();
      final service = SyncService(api, CaptureRepository(db),
          parada: ParadaRepository(db, api));

      final result = await service.pushSweeps(routeId);
      expect(result.synced, 0);
      expect(result.held, 0);
      expect(result.failed, 0);
      expect(api.sweptCalls, isEmpty);
    });

    test('a confirmed sweep marks the row synced', () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      await seedParada(db, 's1');
      final api = _FakeApi()..sweptBehavior['s1'] = () async {};
      final service = SyncService(api, CaptureRepository(db),
          parada: ParadaRepository(db, api));

      final result = await service.pushSweeps(routeId);
      expect(result.synced, 1);
      expect((await db.getParada('s1'))!.sweptSynced, isTrue);
    });

    test(
        'a merit rejection (barrido_fuera_de_orden) records the reason and '
        'stays pending for the next Enviar', () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      await seedParada(db, 's1');
      final api = _FakeApi()
        ..sweptBehavior['s1'] = () async => throw ApiException(
              'Hay una parada anterior sin barrer.',
              statusCode: 409,
              codigo: AppConfig.codeBarridoFueraDeOrden,
            );
      final service = SyncService(api, CaptureRepository(db),
          parada: ParadaRepository(db, api));

      final result = await service.pushSweeps(routeId);
      expect(result.failed, 1);
      final s1 = await db.getParada('s1');
      expect(s1!.sweptSynced, isFalse,
          reason: 'kept pending — it retries on the next Enviar');
      expect(s1.sweepError, 'Hay una parada anterior sin barrer.');
      // Decision 1: the local walk is untouched either way.
      expect(s1.swept, isTrue);
    });

    test(
        'foto_obligatoria_pendiente names the offending locs from '
        'detail.localizaciones', () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      await seedParada(db, 's1');
      final api = _FakeApi()
        ..sweptBehavior['s1'] = () async => throw ApiException(
              'hay placas sin foto',
              statusCode: 409,
              codigo: AppConfig.codeFotoObligatoriaPendiente,
              localizaciones: [30],
            );
      final service = SyncService(api, CaptureRepository(db),
          parada: ParadaRepository(db, api));

      final result = await service.pushSweeps(routeId);
      expect(result.failed, 1);
      // The worker sees exactly where to re-shoot, not just the raw code.
      expect(
          (await db.getParada('s1'))!.sweepError, 'Faltan fotos en la loc 30.');
    });

    test('foto_obligatoria_pendiente with several locs pluralises', () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      await seedParada(db, 's1');
      final api = _FakeApi()
        ..sweptBehavior['s1'] = () async => throw ApiException(
              'hay placas sin foto',
              statusCode: 409,
              codigo: AppConfig.codeFotoObligatoriaPendiente,
              localizaciones: [30, 45],
            );
      final service = SyncService(api, CaptureRepository(db),
          parada: ParadaRepository(db, api));

      await service.pushSweeps(routeId);
      expect((await db.getParada('s1'))!.sweepError,
          'Faltan fotos en loc 30, 45.');
    });

    test('a reopen (swept:false) clears the rejection and requeues', () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      await seedParada(db, 's1');
      final repo = ParadaRepository(db, _FakeApi());
      await repo.markSweepError('s1', 'Faltan fotos en la loc 30.');

      // The correction path: reopen makes it unswept, clears the error, and
      // queues the swept:false push.
      await repo.markSwept('s1', swept: false);
      final s1 = await db.getParada('s1');
      expect(s1!.swept, isFalse);
      expect(s1.sweepError, isNull);
      expect(s1.sweptSynced, isFalse);
    });

    test(
        'a transport failure holds the chain — no verdict, no change, the '
        'rest wait too', () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      await seedParada(db, 's1');
      await seedParada(db, 's2');
      final api = _FakeApi()
        ..sweptBehavior['s1'] = () async => throw ApiException('sin conexión');
      final service = SyncService(api, CaptureRepository(db),
          parada: ParadaRepository(db, api));

      final result = await service.pushSweeps(routeId);
      expect(result.held, 1);
      expect(result.synced, 0);
      expect(result.failed, 0);
      expect(api.sweptCalls, ['s1'], reason: 's2 never attempted');
      final s1 = await db.getParada('s1');
      expect(s1!.sweptSynced, isFalse);
      expect(s1.sweepError, isNull,
          reason: 'a transport failure is not a verdict — nothing recorded');
    });

    test(
        'idempotency (confirmed live with the backend 2026-09-22): a '
        'redundant re-push of an already-swept parada answers 200 and '
        'clears any prior error', () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      await seedParada(db, 's1');
      await ParadaRepository(db, _FakeApi()).markSweepError(
          's1', 'Hay una parada anterior sin barrer.'); // a stale rejection
      final api = _FakeApi()..sweptBehavior['s1'] = () async {};
      final service = SyncService(api, CaptureRepository(db),
          parada: ParadaRepository(db, api));

      final result = await service.pushSweeps(routeId);
      expect(result.synced, 1);
      final s1 = await db.getParada('s1');
      expect(s1!.sweptSynced, isTrue);
      expect(s1.sweepError, isNull);
    });
  });

  group('pushRoute — per-parada walk order (PC.6)', () {
    Future<void> seedParadaWithSweep(AppDatabase db, String id, int seq) =>
        db.upsertParada(ParadasCompanion.insert(
          stopId: id,
          routeId: routeId,
          faceSequence: seq,
          swept: const Value(true),
          sweptSynced: const Value(false),
          updatedAt: DateTime.now(),
        ));

    test('interleaves placas → sweep per parada, in face_sequence order',
        () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      await seedParadaWithSweep(db, 's1', 1);
      await seedParadaWithSweep(db, 's2', 2);
      final repo = CaptureRepository(db);
      final c1 =
          await repo.appendCapture(routeId: routeId, placa: 'A', stopId: 's1');
      final c2 =
          await repo.appendCapture(routeId: routeId, placa: 'B', stopId: 's2');
      final api = _FakeApi(
        respond: (b) => _response(
            [for (final i in b.items) _ok(i.clientId, i.posicion * 5)]),
      )
        ..sweptBehavior['s1'] = () async {}
        ..sweptBehavior['s2'] = () async {};
      final service = SyncService(api, repo, parada: ParadaRepository(db, api));

      final r = await service.pushRoute(routeId, wifiAvailable: true);

      // The root fix: parada 1 fully lands (placa THEN sweep) before parada 2's
      // placa is pushed — so the backend never sees a later placa ahead of an
      // earlier sweep.
      expect(api.callLog, ['placa:$c1', 'sweep:s1', 'placa:$c2', 'sweep:s2']);
      expect(r.placas.synced, 2);
      expect(r.sweep.synced, 2);
    });

    test(
        'a sweep transport-held stops the chain; the later parada is untouched',
        () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      await seedParadaWithSweep(db, 's1', 1);
      await seedParadaWithSweep(db, 's2', 2);
      final repo = CaptureRepository(db);
      await repo.appendCapture(routeId: routeId, placa: 'A', stopId: 's1');
      await repo.appendCapture(routeId: routeId, placa: 'B', stopId: 's2');
      final api = _FakeApi(
        respond: (b) => _response(
            [for (final i in b.items) _ok(i.clientId, i.posicion * 5)]),
      )
        ..sweptBehavior['s1'] = (() async {
          throw ApiException('sin conexión'); // transport, not a verdict
        })
        ..sweptBehavior['s2'] = () async {};
      final service = SyncService(api, repo, parada: ParadaRepository(db, api));

      final r = await service.pushRoute(routeId, wifiAvailable: true);

      // s1 placa pushed, s1 sweep attempted (held) → stop. s2 never touched.
      expect(api.callLog, [
        'placa:${(await repo.capturesForRoute(routeId)).first.clientId}',
        'sweep:s1'
      ]);
      expect(r.sweep.held, 1);
      // s2's placa stays pending (not attempted).
      final s2cap = (await repo.capturesForRoute(routeId)).last;
      expect(s2cap.syncStatus, AppConfig.syncPending);
    });

    test('unassigned captures (no stop_id) ride after the ordered paradas',
        () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      await seedParadaWithSweep(db, 's1', 1);
      final repo = CaptureRepository(db);
      final onFace =
          await repo.appendCapture(routeId: routeId, placa: 'A', stopId: 's1');
      final loose = await repo.appendCapture(routeId: routeId, placa: 'Z');
      final api = _FakeApi(
        respond: (b) => _response(
            [for (final i in b.items) _ok(i.clientId, i.posicion * 5)]),
      )..sweptBehavior['s1'] = () async {};
      final service = SyncService(api, repo, parada: ParadaRepository(db, api));

      await service.pushRoute(routeId, wifiAvailable: true);

      expect(api.callLog, ['placa:$onFace', 'sweep:s1', 'placa:$loose']);
    });
  });

  group('parada_ya_barrida guard (PC.6)', () {
    test('a placa rejected onto a swept parada gets the reopen message',
        () async {
      final db = await memoryDb();
      if (db == null) return markTestSkipped('native sqlite3 not available');
      addTearDown(db.close);
      final (repo, ids) = await seed(db, 1);
      final api = _FakeApi(
        respond: (b) => _response([
          PlacaItemResult(
            clientId: b.items[0].clientId,
            ok: false,
            codigo: AppConfig.codeParadaYaBarrida,
            error: 'parada ya barrida',
          ),
        ]),
      );

      await SyncService(api, repo).pushPending(routeId);

      final row = (await repo.capturesForRoute(routeId)).single;
      expect(row.syncStatus, AppConfig.syncError);
      expect(row.syncError, contains('reábrela'));
      expect(ids.length, 1);
    });
  });
}

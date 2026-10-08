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
      direccionNorm: norm,
      npn: Value<String?>(npn),
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
    // The parada the worker is standing at (direction not resolved yet). It
    // carries a terna (Decisions v2 §7) — an urban parada — matching the
    // R1 rows above, so hasTerna is true and prediction runs.
    await db.upsertParada(ParadasCompanion.insert(
      stopId: 's1',
      routeId: routeId,
      faceSequence: 1,
      blockFaceId: const Value('bf1'),
      tipoVia: const Value('CARRERA'),
      numVia: const Value('2'),
      numCruce: const Value('4'),
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
      stopId: 's1',
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
    expect(ctx.capturedOnStop, 1);
    expect(ctx.hasTerna, isTrue);
    expect(ctx.prediction!.direction, FaceDirection.ascendente);
    expect(ctx.expectedDireccion, 'CARRERA 2 # 4-15');
    expect(ctx.expectedRow!.npn, 'npn-15');
    // The face acera parity comes from the anchor (09 is odd → 1), for the
    // soft warning when a typed distance looks like the other acera.
    expect(ctx.facePlacaParity, 1);

    // The resolved direction is persisted so a mid-face anchor does not stall.
    expect((await db.getParada('s1'))!.direction, 'ascendente');

    // The live preview composes vía+cruce from the parada — the worker never
    // types them (Decisions v2 §4).
    expect(ctx.previewFor(''), 'CARRERA 2 # 4-__');
    expect(ctx.previewFor('15'), 'CARRERA 2 # 4-15');
  });

  test('Spec 13: a MIDDLE anchor warns "no inicia la parada", does not predict',
      () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);

    await db.replaceR1Slice(tenant, [
      _r1(tenant, 'npn-09', 'CARRERA 2 # 4-09', '4', '09'),
      _r1(tenant, 'npn-15', 'CARRERA 2 # 4-15', '4', '15'),
      _r1(tenant, 'npn-23', 'CARRERA 2 # 4-23', '4', '23'),
    ]);
    await db.upsertParada(ParadasCompanion.insert(
      stopId: 's1',
      routeId: routeId,
      faceSequence: 1,
      manzana: const Value('001'),
      updatedAt: DateTime.now(),
    )); // direction null → inferred from the anchor's position in the face

    // Anchor the MIDDLE placa (4-15: 4-09 before, 4-23 after).
    await CaptureRepository(db).appendCapture(
      routeId: routeId,
      placa: 'CARRERA 2 # 4-15',
      manzanaCatastral: '001',
      npn: 'npn-15',
      stopId: 's1',
    );
    final caps = await (db.select(db.captures)
          ..where((c) => c.routeId.equals(routeId)))
        .get();

    final c = _container(db, tenant, caps);
    addTearDown(c.dispose);
    await c.read(routeStopsProvider(routeId).future);
    await c.read(capturesProvider(routeId).future);

    final ctx = await c.read(paradaCaptureContextProvider(routeId).future);
    expect(ctx, isNotNull);
    expect(ctx!.warning, 'esta placa no inicia la parada');
    expect(ctx.prediction?.direction, FaceDirection.indeterminada);
    expect(ctx.expectedDireccion, isNull); // no guess from a middle anchor
    // A middle anchor leaves the direction unresolved (not persisted).
    expect((await db.getParada('s1'))!.direction, isNull);
  });

  test('Spec 13: isMiddleAnchorProvider — middle true (R1 or hallazgo), extremes false',
      () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);

    await db.replaceR1Slice(tenant, [
      _r1(tenant, 'npn-09', 'CARRERA 2 # 4-09', '4', '09'),
      _r1(tenant, 'npn-15', 'CARRERA 2 # 4-15', '4', '15'),
      _r1(tenant, 'npn-23', 'CARRERA 2 # 4-23', '4', '23'),
    ]);
    final c = _container(db, tenant, const []);
    addTearDown(c.dispose);

    Future<bool> isMiddle(String d) => c.read(
        isMiddleAnchorProvider((manzana: '001', direccionNorm: d)).future);

    expect(await isMiddle('CARRERA 2 # 4-15'), isTrue); // one before, one after
    expect(await isMiddle('CARRERA 2 # 4-09'), isFalse); // min endpoint
    expect(await isMiddle('CARRERA 2 # 4-23'), isFalse); // max endpoint
    // Spec 13 (Jorge 2026-10-07): a HALLAZGO not in R1 is judged by PARSING the
    // address, same as an R1 pick — so a free-typed middle anchor is blocked too.
    expect(await isMiddle('CARRERA 2 # 4-19'), isTrue); // middle hallazgo (15<19<23)
    expect(await isMiddle('CARRERA 2 # 4-99'), isFalse); // extreme hallazgo (beyond max)
  });

  test('Spec 13: a hallazgo BEYOND the R1 max anchors (descending) + predicts',
      () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);

    await db.replaceR1Slice(tenant, [
      _r1(tenant, 'npn-09', 'CARRERA 2 # 4-09', '4', '09'),
      _r1(tenant, 'npn-15', 'CARRERA 2 # 4-15', '4', '15'),
      _r1(tenant, 'npn-23', 'CARRERA 2 # 4-23', '4', '23'),
    ]);
    await db.upsertParada(ParadasCompanion.insert(
      stopId: 's1',
      routeId: routeId,
      faceSequence: 1,
      manzana: const Value('001'),
      updatedAt: DateTime.now(),
    ));
    // The extreme placa 4-33 is MISSING from an outdated R1 → captured as a
    // hallazgo (free text, no npn/direccion_norm). Same acera (odd) as the face
    // — a face is one acera, keyed by parity.
    await CaptureRepository(db).appendCapture(
      routeId: routeId,
      placa: 'CARRERA 2 # 4-33',
      manzanaCatastral: '001',
      stopId: 's1',
    );
    final caps = await (db.select(db.captures)
          ..where((c) => c.routeId.equals(routeId)))
        .get();

    final c = _container(db, tenant, caps);
    addTearDown(c.dispose);
    await c.read(routeStopsProvider(routeId).future);
    await c.read(capturesProvider(routeId).future);

    final ctx = await c.read(paradaCaptureContextProvider(routeId).future);
    expect(ctx, isNotNull);
    // Beyond the max → it's the last → descending → predicts the max R1 placa.
    expect(ctx!.prediction?.direction, FaceDirection.descendente);
    expect(ctx.expectedDireccion, 'CARRERA 2 # 4-23');
    expect(ctx.anchorFace?.placaNum, 33); // the hallazgo anchors
    expect(ctx.warning, isNull); // a valid endpoint, not a middle anchor
  });

  test('Spec 13: a hallazgo BELOW the R1 min anchors (ascending) + predicts',
      () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);

    await db.replaceR1Slice(tenant, [
      _r1(tenant, 'npn-09', 'CARRERA 2 # 4-09', '4', '09'),
      _r1(tenant, 'npn-15', 'CARRERA 2 # 4-15', '4', '15'),
      _r1(tenant, 'npn-23', 'CARRERA 2 # 4-23', '4', '23'),
    ]);
    await db.upsertParada(ParadasCompanion.insert(
      stopId: 's1',
      routeId: routeId,
      faceSequence: 1,
      manzana: const Value('001'),
      updatedAt: DateTime.now(),
    ));
    await CaptureRepository(db).appendCapture(
      routeId: routeId,
      placa: 'CARRERA 2 # 4-05', // below the min, missing from R1
      manzanaCatastral: '001',
      stopId: 's1',
    );
    final caps = await (db.select(db.captures)
          ..where((c) => c.routeId.equals(routeId)))
        .get();

    final c = _container(db, tenant, caps);
    addTearDown(c.dispose);
    await c.read(routeStopsProvider(routeId).future);
    await c.read(capturesProvider(routeId).future);

    final ctx = await c.read(paradaCaptureContextProvider(routeId).future);
    expect(ctx, isNotNull);
    expect(ctx!.prediction?.direction, FaceDirection.ascendente);
    expect(ctx.expectedDireccion, 'CARRERA 2 # 4-09');
    expect(ctx.anchorFace?.placaNum, 5);
  });

  test('Spec 13 (AM.4): manzana parada WITHOUT terna predicts from the anchor',
      () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);

    // Same R1 face as the assisted test — manzana 001, rows carry the terna.
    await db.replaceR1Slice(tenant, [
      _r1(tenant, 'npn-09', 'CARRERA 2 # 4-09', '4', '09'),
      _r1(tenant, 'npn-15', 'CARRERA 2 # 4-15', '4', '15'),
      _r1(tenant, 'npn-23', 'CARRERA 2 # 4-23', '4', '23'),
    ]);
    // A parada with a MANZANA but NO terna (the Pitalito pilot shape). Before
    // AM.4 the hasTerna gate sent this to bare() (rural); now it predicts from
    // the anchor's R1 row, since the manzana + a linked anchor are enough.
    await db.upsertParada(ParadasCompanion.insert(
      stopId: 's1',
      routeId: routeId,
      faceSequence: 1,
      manzana: const Value('001'),
      updatedAt: DateTime.now(),
    ));
    // Anchor: first placa on the face, linked to R1 09.
    await CaptureRepository(db).appendCapture(
      routeId: routeId,
      placa: 'CARRERA 2 # 4-09',
      manzanaCatastral: '001',
      npn: 'npn-09',
      stopId: 's1',
    );
    final caps = await (db.select(db.captures)
          ..where((c) => c.routeId.equals(routeId)))
        .get();

    final c = _container(db, tenant, caps);
    addTearDown(c.dispose);
    await c.read(routeStopsProvider(routeId).future);
    await c.read(capturesProvider(routeId).future);

    final ctx = await c.read(paradaCaptureContextProvider(routeId).future);
    expect(ctx, isNotNull);
    expect(ctx!.hasTerna, isFalse); // the PARADA carries no terna…
    expect(ctx.prediction, isNotNull); // …yet it predicts from the anchor's R1.
    expect(ctx.expectedDireccion, 'CARRERA 2 # 4-15');
    expect(ctx.expectedRow!.npn, 'npn-15');
    expect(ctx.facePlacaParity, 1);

    // AM.8: the anchor's terna is exposed, and previewFromAnchor composes the
    // full address from it + a typed distance — the basis of distance mode.
    expect(ctx.anchorFace, isNotNull);
    expect(ctx.anchorFace!.via, 'CARRERA');
    expect(ctx.anchorFace!.numVia, '2');
    expect(ctx.anchorFace!.numCruce, '4');
    expect(ctx.previewFromAnchor('23'), 'CARRERA 2 # 4-23');
    expect(ctx.previewFromAnchor(''), 'CARRERA 2 # 4-__');
  });

  test('Spec 15 (V4.6): multi-unit anchor (npn null) predicts by direccion_norm',
      () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);

    await db.replaceR1Slice(tenant, [
      _r1(tenant, 'npn-09', 'CARRERA 2 # 4-09', '4', '09'),
      _r1(tenant, 'npn-15', 'CARRERA 2 # 4-15', '4', '15'),
      _r1(tenant, 'npn-23', 'CARRERA 2 # 4-23', '4', '23'),
    ]);
    await db.upsertParada(ParadasCompanion.insert(
      stopId: 's1',
      routeId: routeId,
      faceSequence: 1,
      manzana: const Value('001'),
      updatedAt: DateTime.now(),
    ));
    // v4: a MULTI-UNIT placa anchor — captured with npn=null + direccion_norm
    // (the placa). The provider must resolve its terna by direccion_norm.
    await CaptureRepository(db).appendCapture(
      routeId: routeId,
      placa: 'CARRERA 2 # 4-09',
      manzanaCatastral: '001',
      direccionNorm: 'CARRERA 2 # 4-09',
      stopId: 's1',
    );
    final caps = await (db.select(db.captures)
          ..where((c) => c.routeId.equals(routeId)))
        .get();
    expect(caps.single.npn, isNull); // multi-unit: no npn
    expect(caps.single.direccionNorm, 'CARRERA 2 # 4-09');

    final c = _container(db, tenant, caps);
    addTearDown(c.dispose);
    await c.read(routeStopsProvider(routeId).future);
    await c.read(capturesProvider(routeId).future);

    final ctx = await c.read(paradaCaptureContextProvider(routeId).future);
    expect(ctx, isNotNull);
    expect(ctx!.prediction, isNotNull); // predicts despite the null npn
    expect(ctx.expectedDireccion, 'CARRERA 2 # 4-15');
    expect(ctx.anchorFace!.via, 'CARRERA');
  });

  test('rural parada (no terna): bare context, no prediction, no R1 lookup',
      () async {
    final db = await _memoryDb();
    if (db == null) return markTestSkipped('native sqlite3 not available');
    addTearDown(db.close);

    // A rural parada: no block_face_id, no terna (Decisions v2 §6/§8) — a
    // predio reached mid-route with no manzana face at all.
    await db.upsertParada(ParadasCompanion.insert(
      stopId: 's-rural',
      routeId: routeId,
      faceSequence: 4,
      updatedAt: DateTime.now(),
    ));
    await CaptureRepository(db).appendCapture(
      routeId: routeId,
      placa: 'FINCA CANAÁN',
      stopId: 's-rural',
    );
    final caps = await (db.select(db.captures)
          ..where((c) => c.routeId.equals(routeId)))
        .get();

    final c = _container(db, tenant, caps);
    addTearDown(c.dispose);
    await c.read(routeStopsProvider(routeId).future);
    await c.read(capturesProvider(routeId).future);

    final ctx = await c.read(paradaCaptureContextProvider(routeId).future);
    expect(ctx, isNotNull);
    expect(ctx!.hasTerna, isFalse);
    expect(ctx.capturedOnStop, 1);
    expect(ctx.prediction, isNull);
    expect(ctx.expectedRow, isNull);
    expect(ctx.facePlacaParity, isNull);
    expect(ctx.endOfFace, isFalse);
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

  group('previewFor (address-profiles AP.1–AP.5: cardinal)', () {
    Parada parada({String? cardinal, String? cardinalPosicion}) => Parada(
          stopId: 's1',
          routeId: routeId,
          faceSequence: 1,
          tipoVia: 'CALLE',
          numVia: '11',
          numCruce: '3A',
          cardinal: cardinal,
          cardinalPosicion: cardinalPosicion,
          swept: false,
          sweptSynced: true,
          updatedAt: DateTime.now(),
        );

    test('no cardinal: preview unchanged', () {
      final ctx = ParadaCaptureContext(parada: parada(), capturedOnStop: 0);
      expect(ctx.previewFor('15'), 'CALLE 11 # 3A-15');
      expect(ctx.previewFor(''), 'CALLE 11 # 3A-__');
    });

    test("cardinal_posicion 'via': sits after num_via, before the #", () {
      final ctx = ParadaCaptureContext(
        parada: parada(cardinal: 'SUR', cardinalPosicion: 'via'),
        capturedOnStop: 0,
      );
      expect(ctx.previewFor('15'), 'CALLE 11 SUR # 3A-15');
    });

    test("cardinal_posicion 'placa': sits at the very end", () {
      final ctx = ParadaCaptureContext(
        parada: parada(cardinal: 'SUR', cardinalPosicion: 'placa'),
        capturedOnStop: 0,
      );
      expect(ctx.previewFor('15'), 'CALLE 11 # 3A-15 SUR');
    });
  });
}

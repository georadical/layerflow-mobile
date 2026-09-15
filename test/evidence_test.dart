import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/data/api/api_client.dart';
import 'package:layerflow_capture/data/api/dtos.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/capture_repository.dart';
import 'package:layerflow_capture/data/repositories/evidence_repository.dart';
import 'package:layerflow_capture/data/sync/sync_service.dart';

import 'support/sqlite3.dart';

class _FakeEvidenceApi implements ApiClient {
  /// clientId → verdict; absent = 2xx. ApiException(statusCode:null)
  /// simulates transport death.
  final Map<String, ApiException> verdicts = {};
  final List<String> uploadedIds = [];

  @override
  Future<void> uploadEvidence({
    required String clientId,
    required String soporte,
    required String filePath,
  }) async {
    final verdict = verdicts[clientId];
    if (verdict != null) throw verdict;
    uploadedIds.add(clientId);
  }

  @override
  dynamic noSuchMethod(Invocation inv) => super.noSuchMethod(inv);
}

void main() {
  const routeId = 'route-1';

  group('classifySoporte (CL-R3 triggers)', () {
    test('happy case is rutina: typed matches the linked address', () {
      expect(
        EvidenceRepository.classifySoporte(
          notInList: false,
          duplicateNpn: false,
          typedPlaca: 'C 5 2 06',
          linkedDireccionNorm: 'CALLE 5 # 2-06',
        ),
        AppConfig.soporteRutina,
      );
    });

    test('unlinked with a readable placa is rutina too (classic path)', () {
      expect(
        EvidenceRepository.classifySoporte(
          notInList: false,
          duplicateNpn: false,
          typedPlaca: 'C 5 2 06',
          linkedDireccionNorm: null,
        ),
        AppConfig.soporteRutina,
      );
    });

    test('trigger 1: not in the list', () {
      expect(
        EvidenceRepository.classifySoporte(
          notInList: true,
          duplicateNpn: false,
          typedPlaca: 'C 5 2 06',
          linkedDireccionNorm: null,
        ),
        AppConfig.soporteDivergencia,
      );
    });

    test('trigger 2: selected R1 differs from the observed placa', () {
      expect(
        EvidenceRepository.classifySoporte(
          notInList: false,
          duplicateNpn: false,
          typedPlaca: 'C 5 2 08',
          linkedDireccionNorm: 'CALLE 5 # 2-06',
        ),
        AppConfig.soporteDivergencia,
      );
    });

    test('triggers 3/4: blank placa — with or without a context link', () {
      for (final linked in [null, 'CALLE 5 # 2-06']) {
        expect(
          EvidenceRepository.classifySoporte(
            notInList: false,
            duplicateNpn: false,
            typedPlaca: '  ',
            linkedDireccionNorm: linked,
          ),
          AppConfig.soporteDivergencia,
          reason: 'the context link (4) is the most fragile of all',
        );
      }
    });

    test('v1.2: the cruce-placa part alone counts as coincidente (rutina)', () {
      expect(
        EvidenceRepository.classifySoporte(
          notInList: false,
          duplicateNpn: false,
          typedPlaca: '3A 08',
          linkedDireccionNorm: 'CALLE 13 # 3A-08',
        ),
        AppConfig.soporteRutina,
        reason: 'door plates usually show only the part — honest match',
      );
    });

    test('trigger 5: duplicate NPN in the route', () {
      expect(
        EvidenceRepository.classifySoporte(
          notInList: false,
          duplicateNpn: true,
          typedPlaca: 'C 5 2 06',
          linkedDireccionNorm: 'CALLE 5 # 2-06',
        ),
        AppConfig.soporteDivergencia,
      );
    });
  });

  group('needsDeliberateShot (CL-R3 v1.1)', () {
    test('divergence always demands the aimed shot (camera alive)', () {
      for (var roll = 0; roll < 10; roll++) {
        expect(
          EvidenceRepository.needsDeliberateShot(
            soporte: AppConfig.soporteDivergencia,
            cameraReady: true,
            alreadyDeliberate: false,
            lotteryRoll: roll,
          ),
          isTrue,
          reason: 'the photo IS the product there — no lottery escape',
        );
      }
    });

    test('routine only when the lottery hits (roll 0)', () {
      expect(
        EvidenceRepository.needsDeliberateShot(
          soporte: AppConfig.soporteRutina,
          cameraReady: true,
          alreadyDeliberate: false,
          lotteryRoll: 0,
        ),
        isTrue,
      );
      expect(
        EvidenceRepository.needsDeliberateShot(
          soporte: AppConfig.soporteRutina,
          cameraReady: true,
          alreadyDeliberate: false,
          lotteryRoll: 7,
        ),
        isFalse,
      );
    });

    test('a CTA shot already taken satisfies everything', () {
      expect(
        EvidenceRepository.needsDeliberateShot(
          soporte: AppConfig.soporteDivergencia,
          cameraReady: true,
          alreadyDeliberate: true,
          lotteryRoll: 0,
        ),
        isFalse,
      );
    });

    test('hardware valve: a dead camera never blocks the capture', () {
      expect(
        EvidenceRepository.needsDeliberateShot(
          soporte: AppConfig.soporteDivergencia,
          cameraReady: false,
          alreadyDeliberate: false,
          lotteryRoll: 0,
        ),
        isFalse,
        reason: 'the ABSENT expected photo is itself the QA signal',
      );
    });
  });

  group('evidence queue + CL-R5 chain', () {
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

    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('evidence_test');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<String> photo(String name) async {
      final f = File('${tmp.path}/$name.jpg');
      await f.writeAsBytes(List.filled(100, 0xAB));
      return f.path;
    }

    test('re-capturing replaces the row and removes the old file', () async {
      final db = await memoryDb();
      if (db == null) {
        markTestSkipped('native sqlite3 not available on the host');
        return;
      }
      addTearDown(db.close);
      final repo = EvidenceRepository(db);
      final first = await photo('first');
      final second = await photo('second');

      await repo.enqueue(
          clientId: 'u1',
          routeId: routeId,
          filePath: first,
          soporte: AppConfig.soporteRutina);
      await repo.enqueue(
          clientId: 'u1',
          routeId: routeId,
          filePath: second,
          soporte: AppConfig.soporteDivergencia);

      final rows = await repo.pendingForRoute(routeId);
      expect(rows.single.filePath, second);
      expect(rows.single.soporte, AppConfig.soporteDivergencia);
      expect(await File(first).exists(), isFalse,
          reason: 're-shots must not accumulate on disk');
    });

    test(
        'CL-R5: divergence ships on any network; routine waits for WiFi; '
        'uploads purge row and file', () async {
      final db = await memoryDb();
      if (db == null) {
        markTestSkipped('native sqlite3 not available on the host');
        return;
      }
      addTearDown(db.close);
      final captures = CaptureRepository(db);
      final evidence = EvidenceRepository(db);
      final api = _FakeEvidenceApi();
      final sync = SyncService(api, captures, evidence: evidence);

      // Two synced units, one photo each.
      for (final (id, soporte) in [
        ('u-div', AppConfig.soporteDivergencia),
        ('u-rut', AppConfig.soporteRutina),
      ]) {
        await captures.mergeFrame(RouteFrame(routeId: routeId, items: [
          RouteFrameItem(clientId: id, posicion: id == 'u-div' ? 1 : 2, loc: 5),
        ]));
        await evidence.enqueue(
            clientId: id,
            routeId: routeId,
            filePath: await photo(id),
            soporte: soporte);
      }

      // No WiFi: only the divergence photo travels.
      var res = await sync.pushEvidence(routeId, wifiAvailable: false);
      expect(res.uploaded, 1);
      expect(res.held, 1);
      expect(api.uploadedIds, ['u-div']);
      expect(
          (await evidence.pendingForRoute(routeId)).single.clientId, 'u-rut');

      // WiFi: the routine one follows; everything purged.
      res = await sync.pushEvidence(routeId, wifiAvailable: true);
      expect(res.uploaded, 1);
      expect(await evidence.pendingForRoute(routeId), isEmpty);
      final files = tmp.listSync().whereType<File>();
      expect(files, isEmpty, reason: 'confirmed photos purge their files');
    });

    test('REGRESSION: a held photo outlives its queue row and stays visible',
        () async {
      final db = await memoryDb();
      if (db == null) {
        markTestSkipped('native sqlite3 not available on the host');
        return;
      }
      addTearDown(db.close);
      final captures = CaptureRepository(db);
      final evidence = EvidenceRepository(db);

      // A fully SYNCED unit whose routine photo still waits for WiFi —
      // exactly the E2E state where the send bar vanished and the photo
      // had no way to travel.
      await captures.mergeFrame(const RouteFrame(routeId: routeId, items: [
        RouteFrameItem(clientId: 'u1', posicion: 1, loc: 5),
      ]));
      await evidence.enqueue(
          clientId: 'u1',
          routeId: routeId,
          filePath: await photo('held'),
          soporte: AppConfig.soporteRutina);

      expect(await captures.pending(routeId), isEmpty,
          reason: 'the capture queue is empty…');
      expect(await evidence.watchPendingCount(routeId).first, 1,
          reason: '…but the bar must still have a reason to exist');
    });

    test('a photo whose unit has not synced is held (would 404)', () async {
      final db = await memoryDb();
      if (db == null) {
        markTestSkipped('native sqlite3 not available on the host');
        return;
      }
      addTearDown(db.close);
      final captures = CaptureRepository(db);
      final evidence = EvidenceRepository(db);
      final api = _FakeEvidenceApi();
      final sync = SyncService(api, captures, evidence: evidence);

      final id = await captures.appendCapture(routeId: routeId, placa: 'X');
      await evidence.enqueue(
          clientId: id,
          routeId: routeId,
          filePath: await photo('unsynced'),
          soporte: AppConfig.soporteDivergencia);

      final res = await sync.pushEvidence(routeId, wifiAvailable: true);
      expect(res.uploaded, 0);
      expect(res.held, 1);
      expect(api.uploadedIds, isEmpty);
    });

    test('a server verdict (413) is recorded; transport death holds all',
        () async {
      final db = await memoryDb();
      if (db == null) {
        markTestSkipped('native sqlite3 not available on the host');
        return;
      }
      addTearDown(db.close);
      final captures = CaptureRepository(db);
      final evidence = EvidenceRepository(db);
      final api = _FakeEvidenceApi();
      final sync = SyncService(api, captures, evidence: evidence);

      await captures.mergeFrame(const RouteFrame(routeId: routeId, items: [
        RouteFrameItem(clientId: 'u1', posicion: 1, loc: 5),
      ]));
      await evidence.enqueue(
          clientId: 'u1',
          routeId: routeId,
          filePath: await photo('big'),
          soporte: AppConfig.soporteDivergencia);

      // Verdict: too big.
      api.verdicts['u1'] = ApiException('muy grande', statusCode: 413);
      var res = await sync.pushEvidence(routeId, wifiAvailable: true);
      expect(res.failed, 1);
      final row = (await evidence.pendingForRoute(routeId)).single;
      expect(row.syncStatus, AppConfig.syncError);
      expect(row.syncError, 'muy grande');

      // Transport death: no verdict, no change — row back to waiting.
      api.verdicts['u1'] = ApiException('sin conexión');
      res = await sync.pushEvidence(routeId, wifiAvailable: true);
      expect(res.failed, 0);
      expect(res.held, 1);
      expect((await evidence.pendingForRoute(routeId)).length, 1);
    });
  });
}

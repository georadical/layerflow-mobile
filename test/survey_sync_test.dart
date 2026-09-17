import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/core/survey/survey_pyramid.dart';
import 'package:layerflow_capture/data/api/api_client.dart';
import 'package:layerflow_capture/data/api/sync_dtos.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/capture_repository.dart';
import 'package:layerflow_capture/data/repositories/survey_repository.dart';
import 'package:layerflow_capture/data/sync/sync_service.dart';

import 'support/sqlite3.dart';

/// Fake /sync/push: builds a response from the request, or throws.
class _FakeSyncApi implements ApiClient {
  _FakeSyncApi({this.response, this.throwing});

  final SyncPushResponse Function(SyncPushRequest)? response;
  final ApiException? throwing;
  SyncPushRequest? lastReq;

  @override
  Future<SyncPushResponse> pushSync(SyncPushRequest req) async {
    lastReq = req;
    if (throwing != null) throw throwing!;
    return response!(req);
  }

  @override
  dynamic noSuchMethod(Invocation inv) => super.noSuchMethod(inv);
}

SyncPushResponse _allApplied(SyncPushRequest req) => SyncPushResponse.fromJson({
      'batch_id': req.batchId,
      'operaciones': [
        for (final o in req.operations) {'id': o.id, 'resultado': 'aplicada'},
      ],
    });

/// The visit-create is refused with the CL-E8 lock code; children error too.
SyncPushResponse _surveyLocked(SyncPushRequest req) =>
    SyncPushResponse.fromJson({
      'batch_id': req.batchId,
      'operaciones': [
        for (final o in req.operations)
          o.entidad == SyncEntidad.visit
              ? {
                  'id': o.id,
                  'resultado': 'error',
                  'codigo': 'survey_no_autorizado',
                  'motivo': 'no habilitado',
                }
              : {'id': o.id, 'resultado': 'error'},
      ],
    });

const _answered = SurveyAnswers(
  acceso: AccesoIndependiente.si,
  tipoAcceso: TipoAcceso.calle,
  medicion: Medicion.individual,
  uso: Uso.vivienda,
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

  /// A synced anchor (its census_code exists) with a saved survey.
  Future<(AppDatabase, CaptureRepository, SurveyRepository, String)?> seed({
    bool anchorSynced = true,
  }) async {
    final db = await _memoryDb();
    if (db == null) return null;
    final captureRepo = CaptureRepository(db);
    final surveyRepo = SurveyRepository(db);
    final anchor = await captureRepo.appendCapture(routeId: routeId, placa: 'A');
    if (anchorSynced) {
      await captureRepo.markSynced(
          clientId: anchor, loc: 5, remoteId: 'census-1');
    }
    await surveyRepo.saveSurvey(
      anchorClientId: anchor,
      routeId: routeId,
      structure: SurveyStructure.unifamiliar(_answered),
    );
    return (db, captureRepo, surveyRepo, anchor);
  }

  test('a synced anchor: the survey pushes and is marked synced', () async {
    final s = await seed();
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, captureRepo, surveyRepo, anchor) = s;
    addTearDown(db.close);
    final api = _FakeSyncApi(response: _allApplied);
    final sync = SyncService(api, captureRepo, survey: surveyRepo);

    final res = await sync.pushSurveys(routeId, fieldWorkerId: 'fw-1');
    expect(res.synced, 1);
    expect(res.held, 0);
    expect(res.failed, 0);

    // The visit carried the derived-route contract: census_code_id + worker,
    // and NO assignment_id (the backend derives it).
    final visit = api.lastReq!.operations
        .firstWhere((o) => o.entidad == SyncEntidad.visit);
    expect(visit.data['census_code_id'], 'census-1');
    expect(visit.data['field_worker_id'], 'fw-1');
    expect(visit.data.containsKey('assignment_id'), isFalse);

    expect((await surveyRepo.getSurvey(anchor))!.syncStatus,
        AppConfig.syncSynced);
    expect(await surveyRepo.pending(routeId), isEmpty);
  });

  test('an unsynced anchor holds the survey (its census_code does not exist)',
      () async {
    final s = await seed(anchorSynced: false);
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, captureRepo, surveyRepo, anchor) = s;
    addTearDown(db.close);
    final api = _FakeSyncApi(response: _allApplied);
    final sync = SyncService(api, captureRepo, survey: surveyRepo);

    final res = await sync.pushSurveys(routeId, fieldWorkerId: 'fw-1');
    expect(res.held, 1);
    expect(res.synced, 0);
    expect(api.lastReq, isNull, reason: 'nothing was sent');
    expect((await surveyRepo.getSurvey(anchor))!.syncStatus,
        AppConfig.syncPending);
  });

  test('CL-E8: a survey_no_autorizado marks the survey error, with a reason',
      () async {
    final s = await seed();
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, captureRepo, surveyRepo, anchor) = s;
    addTearDown(db.close);
    final api = _FakeSyncApi(response: _surveyLocked);
    final sync = SyncService(api, captureRepo, survey: surveyRepo);

    final res = await sync.pushSurveys(routeId, fieldWorkerId: 'fw-1');
    expect(res.failed, 1);
    final row = await surveyRepo.getSurvey(anchor);
    expect(row!.syncStatus, AppConfig.syncError);
    expect(row.syncError, contains('habilit'));
  });

  test('a transport failure holds the survey — no verdict, no change',
      () async {
    final s = await seed();
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, captureRepo, surveyRepo, anchor) = s;
    addTearDown(db.close);
    final api = _FakeSyncApi(throwing: ApiException('sin red'));
    final sync = SyncService(api, captureRepo, survey: surveyRepo);

    final res = await sync.pushSurveys(routeId, fieldWorkerId: 'fw-1');
    expect(res.held, 1);
    expect(res.failed, 0);
    expect((await surveyRepo.getSurvey(anchor))!.syncStatus,
        AppConfig.syncPending);
  });
}

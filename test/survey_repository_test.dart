import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/core/survey/survey_pyramid.dart';
import 'package:layerflow_capture/data/api/sync_dtos.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/survey_repository.dart';
import 'package:layerflow_capture/data/sync/survey_operations.dart';

import 'support/sqlite3.dart';

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

const _answered = SurveyAnswers(
  acceso: AccesoIndependiente.si,
  tipoAcceso: TipoAcceso.calle,
  medicion: Medicion.individual,
  uso: Uso.vivienda,
);

void main() {
  const anchor = 'anchor-1';
  const routeId = 'route-1';

  Future<(AppDatabase, SurveyRepository)?> setup() async {
    final db = await _tryMemoryDb();
    if (db == null) return null;
    return (db, SurveyRepository(db));
  }

  test('save then load round-trips the structure', () async {
    final s = await setup();
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, repo) = s;
    addTearDown(db.close);

    await repo.saveSurvey(
      anchorClientId: anchor,
      routeId: routeId,
      structure: SurveyStructure.unifamiliar(_answered).addFloor(),
    );
    final back = await repo.loadStructure(anchor);
    expect(back, isNotNull);
    expect(back!.generate().length, 2); // 01/01 + 02/01
    expect(back.generate().first.answers, _answered);
  });

  test('no survey saved → loadStructure is null, estado is sinEncuesta',
      () async {
    final s = await setup();
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, repo) = s;
    addTearDown(db.close);

    expect(await repo.loadStructure(anchor), isNull);
    expect(repo.estadoOf(null), SurveyEstado.sinEncuesta);
  });

  test('the stable ids are assigned once and preserved across saves',
      () async {
    final s = await setup();
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, repo) = s;
    addTearDown(db.close);

    await repo.saveSurvey(
      anchorClientId: anchor,
      routeId: routeId,
      structure: SurveyStructure.unifamiliar(_answered),
    );
    final first = await repo.getSurvey(anchor);
    // Edit and save again.
    await repo.saveSurvey(
      anchorClientId: anchor,
      routeId: routeId,
      structure: SurveyStructure.unifamiliar(_answered).addUnit(0),
    );
    final second = await repo.getSurvey(anchor);

    expect(second!.visitId, first!.visitId);
    expect(second.observationSetId, first.observationSetId);
    expect(second.createdAt, first.createdAt);
  });

  test('estado moves partial → aMedias, full → completa', () async {
    final s = await setup();
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, repo) = s;
    addTearDown(db.close);

    await repo.saveSurvey(
      anchorClientId: anchor,
      routeId: routeId,
      structure: SurveyStructure.unifamiliar(), // blank
    );
    expect(repo.estadoOf(await repo.getSurvey(anchor)), SurveyEstado.aMedias);

    await repo.saveSurvey(
      anchorClientId: anchor,
      routeId: routeId,
      structure: SurveyStructure.unifamiliar(_answered), // complete
    );
    expect(repo.estadoOf(await repo.getSurvey(anchor)), SurveyEstado.completa);
  });

  test('a saved survey is pending; markSynced clears it from the queue',
      () async {
    final s = await setup();
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, repo) = s;
    addTearDown(db.close);

    await repo.saveSurvey(
      anchorClientId: anchor,
      routeId: routeId,
      structure: SurveyStructure.unifamiliar(_answered),
    );
    expect((await repo.pending(routeId)).length, 1);

    await repo.markSynced(anchor);
    expect((await repo.pending(routeId)), isEmpty);
    expect((await repo.getSurvey(anchor))!.syncStatus, AppConfig.syncSynced);
  });

  test('CL4: another person\'s unsent survey is neither listed nor pushed',
      () async {
    final s = await setup();
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, repo) = s;
    addTearDown(db.close);

    await repo.saveSurvey(
      anchorClientId: anchor,
      routeId: routeId,
      structure: SurveyStructure.unifamiliar(_answered),
      owner: 'ana@x.com',
    );
    expect(await repo.pending(routeId, owner: 'bob@x.com'), isEmpty);
    expect((await repo.pending(routeId, owner: 'ana@x.com')).length, 1);
  });

  test('operationsFor uses the persisted ids and builds the chain', () async {
    final s = await setup();
    if (s == null) return markTestSkipped('native sqlite3 not available');
    final (db, repo) = s;
    addTearDown(db.close);

    await repo.saveSurvey(
      anchorClientId: anchor,
      routeId: routeId,
      structure: SurveyStructure.unifamiliar(_answered),
    );
    final row = await repo.getSurvey(anchor);
    final ops = repo.operationsFor(
      row!,
      const SurveyContext(censusCodeId: 'cc', fieldWorkerId: 'fw'),
    );

    expect(ops[0].entidad, SyncEntidad.visit);
    expect(ops[0].id, row.visitId);
    expect(ops[0].data['census_code_id'], 'cc');
    expect(ops[1].entidad, SyncEntidad.observationSet);
    expect(ops[1].data['visit_id'], row.visitId);
    // one unit, fully answered → ph, pv + four answers = 6 field_responses
    expect(
        ops.where((o) => o.entidad == SyncEntidad.fieldResponse).length, 6);
  });
}

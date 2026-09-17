import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/survey/survey_pyramid.dart';
import 'package:layerflow_capture/data/api/sync_dtos.dart';
import 'package:layerflow_capture/data/sync/survey_operations.dart';

const _ctx = SurveyContext(
  censusCodeId: 'cc-1',
  fieldWorkerId: 'fw-1',
);

const _answered = SurveyAnswers(
  acceso: AccesoIndependiente.si,
  tipoAcceso: TipoAcceso.calle,
  medicion: Medicion.individual,
  uso: Uso.vivienda,
);

/// Deterministic stub id, readable in assertions.
String _frId(int instancia, String campo) => 'fr-$instancia-$campo';

List<SyncOperation> _build(SurveyStructure s) => buildSurveyOperations(
      visitId: 'visit-1',
      observationSetId: 'os-1',
      context: _ctx,
      structure: s,
      fieldResponseId: _frId,
    );

void main() {
  group('the chain — parents before children', () {
    test('a unifamiliar predio still emits visit + set + one 01/01 (Q1=B)', () {
      final ops = _build(SurveyStructure.unifamiliar(_answered));
      expect(ops[0].entidad, SyncEntidad.visit);
      expect(ops[1].entidad, SyncEntidad.observationSet);
      // one unit: ph, pv + four answers = 6 field_responses
      final frs = ops.where((o) => o.entidad == SyncEntidad.fieldResponse);
      expect(frs.length, 6);
      expect(frs.every((o) => o.data['instancia'] == 1), isTrue);
    });

    test('output is already ordered — ordered() does not move anything', () {
      final ops = _build(SurveyStructure.unifamiliar(_answered));
      final reordered =
          SyncPushRequest(batchId: 'b', operations: ops).ordered().operations;
      expect(reordered.map((o) => o.id).toList(),
          ops.map((o) => o.id).toList());
    });

    test('every op is a create (a survey is immutable from the app once sent)',
        () {
      final ops = _build(SurveyStructure.unifamiliar().addUnit(0));
      expect(ops.every((o) => o.op == SyncOp.create), isTrue);
    });
  });

  group('field_responses per unit (Q2 data shape)', () {
    test('ph/pv always ride; only answered CL-E3 questions do', () {
      // Unit 1 fully answered, unit 2 blank.
      final s = SurveyStructure.unifamiliar(_answered).addUnit(0);
      final ops = _build(s);
      final u1 = ops
          .where((o) =>
              o.entidad == SyncEntidad.fieldResponse &&
              o.data['instancia'] == 1)
          .map((o) => o.data['campo'])
          .toList();
      final u2 = ops
          .where((o) =>
              o.entidad == SyncEntidad.fieldResponse &&
              o.data['instancia'] == 2)
          .map((o) => o.data['campo'])
          .toList();
      expect(u1, containsAll([campoPh, campoPv, campoAcceso, campoUso]));
      expect(u1.length, 6);
      expect(u2, [campoPh, campoPv]); // blank unit: only structure
    });

    test('field_response.data carries the pinned tuple + FK', () {
      final ops = _build(SurveyStructure.unifamiliar(_answered));
      final ph = ops.firstWhere((o) =>
          o.entidad == SyncEntidad.fieldResponse && o.data['campo'] == campoPh);
      expect(ph.data['observation_set_id'], 'os-1');
      expect(ph.data['entidad_objetivo'], entidadUnidad);
      expect(ph.data['instancia'], 1);
      expect(ph.data['valor'], '01');
      expect(ph.id, 'fr-1-ph');
    });

    test('answer valor uses the contract wire values', () {
      final ops = _build(SurveyStructure.unifamiliar(_answered));
      final uso = ops.firstWhere((o) =>
          o.entidad == SyncEntidad.fieldResponse &&
          o.data['campo'] == campoUso);
      expect(uso.data['valor'], 'vivienda');
    });

    test('visit.data and observation_set.data match Q2 (no assignment_id)', () {
      final ops = _build(SurveyStructure.unifamiliar(_answered));
      expect(ops[0].data, {
        'census_code_id': 'cc-1',
        'field_worker_id': 'fw-1',
      });
      expect(ops[0].data.containsKey('assignment_id'), isFalse);
      expect(ops[1].data, {'visit_id': 'visit-1'});
    });
  });

  group('multi-unit walk order', () {
    test('instancia/ph/pv follow the pyramid (01/01, 01/02, 02/01)', () {
      final s = SurveyStructure.unifamiliar().addUnit(0).addFloor();
      final ops = _build(s);
      final phpv = <String>[];
      for (final o in ops.where((o) =>
          o.entidad == SyncEntidad.fieldResponse &&
          (o.data['campo'] == campoPh))) {
        final inst = o.data['instancia'];
        final pv = ops.firstWhere((x) =>
            x.entidad == SyncEntidad.fieldResponse &&
            x.data['instancia'] == inst &&
            x.data['campo'] == campoPv);
        phpv.add('${o.data['valor']}/${pv.data['valor']}');
      }
      expect(phpv, ['01/01', '01/02', '02/01']);
    });
  });

  group('totalizador', () {
    test('emits a 99/99 unidad row with ph/pv only — and NO media op', () {
      final s = SurveyStructure.unifamiliar(_answered)
          .declareTotalizador(photo: '/tmp/t.jpg');
      final ops = _build(s);
      expect(ops.any((o) => o.entidad == SyncEntidad.mediaAsset), isFalse,
          reason: 'the totalizador photo ships via /field/capture/evidence');
      final tot = ops
          .where((o) =>
              o.entidad == SyncEntidad.fieldResponse &&
              o.data['instancia'] == 99)
          .map((o) => o.data['campo'])
          .toList();
      expect(tot, [campoPh, campoPv]);
      final totPh = ops.firstWhere((o) =>
          o.data['instancia'] == 99 && o.data['campo'] == campoPh);
      expect(totPh.data['valor'], '99');
    });
  });

  group('INVARIANT: coordinate-free', () {
    test('no op data carries coordinates', () {
      final ops = _build(SurveyStructure.unifamiliar(_answered).addFloor());
      for (final o in ops) {
        for (final k in o.data.keys) {
          expect(k,
              isNot(anyOf('lat', 'lon', 'latitude', 'longitude', 'geom')));
        }
      }
    });
  });

  group('surveyFieldResponseId — deterministic stable id', () {
    test('same natural key → same id; different key → different id', () {
      final a = surveyFieldResponseId('os-1', 1, campoPh);
      final b = surveyFieldResponseId('os-1', 1, campoPh);
      final c = surveyFieldResponseId('os-1', 1, campoPv);
      final d = surveyFieldResponseId('os-2', 1, campoPh);
      expect(a, b);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(a, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });
  });
}

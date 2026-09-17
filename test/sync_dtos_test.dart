import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/api/sync_dtos.dart';

SyncOperation _op(SyncEntidad e, String id) =>
    SyncOperation(entidad: e, op: SyncOp.create, id: id, data: const {});

void main() {
  group('SyncOperation.toJson — the pinned envelope', () {
    test('serialises entidad/op/id/data with contract wire values', () {
      final json = const SyncOperation(
        entidad: SyncEntidad.fieldResponse,
        op: SyncOp.create,
        id: 'row-1',
        data: {'campo': 'ph', 'valor': '01'},
      ).toJson();
      expect(json['entidad'], 'field_response');
      expect(json['op'], 'create');
      expect(json['id'], 'row-1');
      expect(json['data'], {'campo': 'ph', 'valor': '01'});
    });

    test('INVARIANT: no coordinates leak through data keys we control', () {
      final json = _op(SyncEntidad.visit, 'v1').toJson();
      for (final key in json.keys) {
        expect(key,
            isNot(anyOf('lat', 'lon', 'latitude', 'longitude', 'geom')));
      }
    });
  });

  group('orderOperations — parents strictly before children', () {
    test('reorders a scrambled batch into visit→set→field→media', () {
      final scrambled = [
        _op(SyncEntidad.mediaAsset, 'm1'),
        _op(SyncEntidad.fieldResponse, 'f1'),
        _op(SyncEntidad.observationSet, 's1'),
        _op(SyncEntidad.visit, 'v1'),
      ];
      final ordered = orderOperations(scrambled).map((o) => o.entidad).toList();
      expect(ordered, [
        SyncEntidad.visit,
        SyncEntidad.observationSet,
        SyncEntidad.fieldResponse,
        SyncEntidad.mediaAsset,
      ]);
    });

    test('is stable within a rank — declaration order survives', () {
      final ops = [
        _op(SyncEntidad.fieldResponse, 'f1'),
        _op(SyncEntidad.fieldResponse, 'f2'),
        _op(SyncEntidad.fieldResponse, 'f3'),
      ];
      expect(orderOperations(ops).map((o) => o.id).toList(),
          ['f1', 'f2', 'f3']);
    });

    test('visit_attempt sorts after visit, before observation_set', () {
      final ops = [
        _op(SyncEntidad.observationSet, 's1'),
        _op(SyncEntidad.visitAttempt, 'a1'),
        _op(SyncEntidad.visit, 'v1'),
      ];
      expect(orderOperations(ops).map((o) => o.entidad).toList(), [
        SyncEntidad.visit,
        SyncEntidad.visitAttempt,
        SyncEntidad.observationSet,
      ]);
    });
  });

  group('SyncPushRequest', () {
    test('ordered() serialises operations parents-first', () {
      final req = SyncPushRequest(
        batchId: 'b1',
        operations: [
          _op(SyncEntidad.fieldResponse, 'f1'),
          _op(SyncEntidad.visit, 'v1'),
        ],
      ).ordered();
      final json = req.toJson();
      final ents =
          (json['operations'] as List).map((o) => o['entidad']).toList();
      expect(ents, ['visit', 'field_response']);
      expect(json['batch_id'], 'b1');
      expect(json.containsKey('device_id'), isFalse);
    });

    test('device_id is serialised only when present', () {
      final json = SyncPushRequest(
        batchId: 'b1',
        deviceId: 'dev-9',
        operations: [_op(SyncEntidad.visit, 'v1')],
      ).toJson();
      expect(json['device_id'], 'dev-9');
    });
  });

  group('SyncOpResult — per-op verdict', () {
    test('aplicada and duplicada both count as OK (idempotent re-send)', () {
      expect(SyncOpResult.fromJson({'id': 'x', 'resultado': 'aplicada'}).isOk,
          isTrue);
      expect(SyncOpResult.fromJson({'id': 'x', 'resultado': 'duplicada'}).isOk,
          isTrue);
      expect(SyncOpResult.fromJson({'id': 'x', 'resultado': 'error'}).isOk,
          isFalse);
      expect(SyncOpResult.fromJson({'id': 'x', 'resultado': 'conflicto'}).isOk,
          isFalse);
    });

    test('CL-E8 survey lock is recognised by its stable code', () {
      final r = SyncOpResult.fromJson({
        'id': 'v1',
        'resultado': 'error',
        'codigo': 'survey_no_autorizado',
        'motivo': 'El encuestador no tiene la encuesta habilitada.',
      });
      expect(r.isError, isTrue);
      expect(r.isSurveyLocked, isTrue);
      expect(r.motivo, isNotNull);
    });

    test('a plain error is not a survey lock', () {
      final r = SyncOpResult.fromJson({'id': 'v1', 'resultado': 'error'});
      expect(r.isError, isTrue);
      expect(r.isSurveyLocked, isFalse);
    });

    test('a missing resultado is treated as an error, never a silent OK', () {
      expect(SyncOpResult.fromJson({'id': 'x'}).isOk, isFalse);
    });
  });

  group('SyncPushResponse — operaciones + resumen (pinned Q3)', () {
    test('parses the operaciones array and reads the resumen counters', () {
      final res = SyncPushResponse.fromJson({
        'batch_id': 'b1',
        'resumen': {
          'total': 4,
          'aplicadas': 1,
          'duplicadas': 1,
          'conflictos': 1,
          'errores': 1,
        },
        'operaciones': [
          {'id': 'v1', 'resultado': 'aplicada'},
          {'id': 's1', 'resultado': 'duplicada'},
          {'id': 'f1', 'resultado': 'conflicto'},
          {'id': 'm1', 'resultado': 'error'},
        ],
      });
      expect(res.batchId, 'b1');
      expect(res.total, 4);
      expect(res.aplicadas, 1);
      expect(res.duplicadas, 1);
      expect(res.conflictos, 1);
      expect(res.errores, 1);
      expect(res.isOk, isFalse);
    });

    test('resumen is authoritative, not re-derived from the ops', () {
      final res = SyncPushResponse.fromJson({
        'batch_id': 'b1',
        'resumen': {'total': 99, 'aplicadas': 99},
        'operaciones': [
          {'id': 'v1', 'resultado': 'aplicada'}
        ],
      });
      expect(res.total, 99);
      expect(res.aplicadas, 99);
    });

    test('counters fall back to deriving when resumen is absent', () {
      final res = SyncPushResponse.fromJson({
        'operaciones': [
          {'id': 'v1', 'resultado': 'aplicada'},
          {'id': 'f1', 'resultado': 'duplicada'},
        ],
      });
      expect(res.total, 2);
      expect(res.aplicadas, 1);
      expect(res.duplicadas, 1);
      expect(res.isOk, isTrue);
    });

    test('surfaces a survey lock anywhere in the batch (CL-E8)', () {
      final res = SyncPushResponse.fromJson({
        'batch_id': 'b1',
        'operaciones': [
          {'id': 'v1', 'resultado': 'error', 'codigo': 'survey_no_autorizado'},
          {'id': 'f1', 'resultado': 'error'},
        ],
      });
      expect(res.hasSurveyLock, isTrue);
    });

    test('falls back to results/items keys so an older shape never crashes',
        () {
      final a = SyncPushResponse.fromJson({
        'results': [
          {'id': 'v1', 'resultado': 'aplicada'}
        ],
      });
      final b = SyncPushResponse.fromJson({
        'items': [
          {'id': 'v1', 'resultado': 'aplicada'}
        ],
      });
      expect(a.aplicadas, 1);
      expect(b.aplicadas, 1);
    });
  });
}

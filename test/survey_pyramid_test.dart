import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/survey/survey_pyramid.dart';

/// Compact assertion helper: a generated unit as (instancia, "ph/pv").
(int, String) _code(GeneratedUnit u) => (u.instancia, '${u.ph}/${u.pv}');

const _answered = SurveyAnswers(
  acceso: AccesoIndependiente.si,
  tipoAcceso: TipoAcceso.calle,
  medicion: Medicion.individual,
  uso: Uso.vivienda,
);

void main() {
  group('unifamiliar — the common predio still emits one 01/01 (Q1=B)', () {
    test('a lone unit emits one 01/01 with its answers', () {
      final s = SurveyStructure.unifamiliar(_answered);
      expect(s.isUnifamiliar, isTrue);
      final g = s.generate();
      expect(g.map(_code).toList(), [(1, '01/01')]);
      expect(g.single.answers, _answered);
    });

    test('its answers are held, not lost', () {
      final s = SurveyStructure.unifamiliar(_answered);
      expect(s.single, _answered);
    });
  });

  group('the pinned gestures (§"PH/PV generation")', () {
    test('first "agregar unidad" materialises 01/01 and adds 01/02', () {
      // The implicit unit is already floor 0 / unit 0, so it stays 01/01 and
      // keeps its answers; the new one is 01/02 (CL-E2).
      final s = SurveyStructure.unifamiliar(_answered).addUnit(0);
      expect(s.isUnifamiliar, isFalse);
      final g = s.generate();
      expect(g.map(_code).toList(), [(1, '01/01'), (2, '01/02')]);
      expect(g[0].answers, _answered, reason: 'the implicit unit is preserved');
      expect(g[1].answers, const SurveyAnswers());
    });

    test('first "agregar piso" materialises 01/01 and adds 02/01', () {
      final s = SurveyStructure.unifamiliar(_answered).addFloor();
      final g = s.generate();
      expect(g.map(_code).toList(), [(1, '01/01'), (2, '02/01')]);
      expect(g[0].answers, _answered);
    });

    test('PH is floor order, PV is walk order within the floor', () {
      // The acceptance-criteria structure: 01/01, 01/02, 02/01.
      final s = SurveyStructure.unifamiliar()
          .addUnit(0) // floor 1: two units
          .addFloor(); // floor 2: one unit
      final g = s.generate();
      expect(g.map(_code).toList(), [
        (1, '01/01'),
        (2, '01/02'),
        (3, '02/01'),
      ]);
    });

    test('instancia is a flat 1..N over the whole predio, in walk order', () {
      final s = SurveyStructure.unifamiliar()
          .addUnit(0) // floor 1: two units
          .addFloor() // floor 2: one unit
          .addUnit(1) // floor 2: second unit
          .addFloor(); // floor 3: one unit
      expect(s.totalUnits, 5);
      expect(s.generate().map((u) => u.instancia).toList(), [1, 2, 3, 4, 5]);
      expect(s.generate().map(_code).toList(), [
        (1, '01/01'),
        (2, '01/02'),
        (3, '02/01'),
        (4, '02/02'),
        (5, '03/01'),
      ]);
    });
  });

  group('deletion before sending compacts for free', () {
    test('removing a unit closes the PV gap in its floor', () {
      final s = SurveyStructure.unifamiliar()
          .addUnit(0)
          .addUnit(0); // floor 1: 3 units
      expect(s.generate().length, 3);
      final after = s.removeUnit(0, 1); // drop the middle unit
      expect(after.generate().map(_code).toList(), [(1, '01/01'), (2, '01/02')]);
    });

    test('removing a floor renumbers the floors above down', () {
      final s = SurveyStructure.unifamiliar()
          .addFloor() // floor 2
          .addFloor(); // floor 3
      expect(s.generate().map(_code).toList(),
          [(1, '01/01'), (2, '02/01'), (3, '03/01')]);
      final after = s.removeFloor(1); // drop floor 2
      expect(after.generate().map(_code).toList(),
          [(1, '01/01'), (2, '02/01')]);
    });

    test('deleting back to one unit returns to a lone 01/01, answers kept',
        () {
      final s = SurveyStructure.unifamiliar(_answered).addUnit(0);
      final after = s.removeUnit(0, 1); // remove the added second unit
      expect(after.isUnifamiliar, isTrue);
      expect(after.generate().map(_code).toList(), [(1, '01/01')]);
      expect(after.single, _answered, reason: 'the survivor keeps its answers');
    });
  });

  group('answers survive structural gestures', () {
    test('editing unit 1 then adding a floor leaves unit 1 answered', () {
      final s = SurveyStructure.unifamiliar()
          .addUnit(0)
          .setAnswers(0, 0, _answered)
          .addFloor();
      expect(s.generate()[0].answers, _answered);
    });
  });

  group('totalizador (99/99) — a gesture apart', () {
    test('declared with a photo generates the 99/99 instance last', () {
      final s = SurveyStructure.unifamiliar()
          .addUnit(0)
          .declareTotalizador(photo: '/tmp/tot.jpg');
      final g = s.generate();
      expect(g.last.isTotalizador, isTrue);
      expect(_code(g.last), (99, '99/99'));
      expect(s.canSend(), isTrue);
    });

    test('declared WITHOUT its photo is refused (CL-E7)', () {
      final s = SurveyStructure.unifamiliar().addUnit(0).declareTotalizador();
      final v = s.validate();
      expect(v.map((e) => e.kind), contains(SurveyViolation.totalizadorSinFoto));
      expect(s.canSend(), isFalse);
    });

    test('attaching the photo afterwards clears the violation', () {
      final s = SurveyStructure.unifamiliar()
          .addUnit(0)
          .declareTotalizador()
          .attachTotalizadorPhoto('/tmp/tot.jpg');
      expect(s.canSend(), isTrue);
    });

    test('clearing the totalizador drops its instance and any violation', () {
      final s = SurveyStructure.unifamiliar()
          .addUnit(0)
          .declareTotalizador()
          .clearTotalizador();
      expect(s.generate().any((u) => u.isTotalizador), isFalse);
      expect(s.canSend(), isTrue);
    });
  });

  group('CL-E7 convention guard', () {
    test('a clean multi-unit structure is sendable', () {
      final s = SurveyStructure.unifamiliar().addUnit(0).addFloor();
      expect(s.validate(), isEmpty);
    });

    test('unidad instances on a lote anchor are refused', () {
      final s = SurveyStructure.unifamiliar().addUnit(0);
      final v = s.validate(anchorIsLote: true);
      expect(v.map((e) => e.kind), contains(SurveyViolation.ancoraEsLote));
    });

    test('a lote is refused even when unifamiliar (it still emits a unit)', () {
      final s = SurveyStructure.unifamiliar(_answered);
      expect(s.validate(anchorIsLote: true).map((e) => e.kind),
          contains(SurveyViolation.ancoraEsLote));
    });

    test('codes never spill into the 99 reservation for real structures', () {
      // 98 units on one floor: max real code is exactly 98, still valid.
      var s = SurveyStructure.unifamiliar();
      for (var i = 0; i < 97; i++) {
        s = s.addUnit(0);
      }
      expect(s.totalUnits, 98);
      expect(s.validate(), isEmpty);
      // The 99th real unit spills past 98 → refused.
      s = s.addUnit(0);
      expect(s.totalUnits, 99);
      expect(
          s.validate().map((e) => e.kind), contains(SurveyViolation.fueraDeRango));
    });
  });

  group('contract wire values (pinned in the spec model)', () {
    test('answer enums map to their contract strings', () {
      expect(AccesoIndependiente.si.wire, 'si');
      expect(AccesoIndependiente.no.wire, 'no');
      expect(TipoAcceso.zonaComun.wire, 'zona_comun');
      expect(Medicion.general.wire, 'general');
      expect(Uso.oficina.wire, 'oficina');
    });
  });

  group('isComplete — the completa chip', () {
    test('true only when every real unit is fully answered', () {
      expect(SurveyStructure.unifamiliar().isComplete, isFalse);
      expect(SurveyStructure.unifamiliar(_answered).isComplete, isTrue);
      // a blank second unit drops it back to incomplete
      expect(SurveyStructure.unifamiliar(_answered).addUnit(0).isComplete,
          isFalse);
    });

    test('the totalizador (no answers) does not block completeness', () {
      final s = SurveyStructure.unifamiliar(_answered)
          .declareTotalizador(photo: '/t.jpg');
      expect(s.isComplete, isTrue);
    });
  });

  group('JSON round-trip (drift persistence)', () {
    test('a multi-floor structure with answers survives a round-trip', () {
      final s = SurveyStructure.unifamiliar(_answered)
          .addUnit(0)
          .setAnswers(0, 1, const SurveyAnswers(uso: Uso.local))
          .addFloor()
          .declareTotalizador(photo: '/tmp/t.jpg');
      final back = SurveyStructure.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.generate(), s.generate());
      expect(back.totalizador, isTrue);
      expect(back.totalizadorPhoto, '/tmp/t.jpg');
    });

    test('a blank unifamiliar round-trips to a blank unifamiliar', () {
      final s = SurveyStructure.unifamiliar();
      final back = SurveyStructure.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.isUnifamiliar, isTrue);
      expect(back.generate(), s.generate());
    });
  });
}

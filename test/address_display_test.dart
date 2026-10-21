import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/parada/address_display.dart';

/// AD.2 — Spec 19: compose only a bare distance; a full address or a cruce is
/// shown as stored.
const _calle20a3 =
    AddressPrefix(tipoVia: 'CALLE', numVia: '20A', numCruce: '3');

void main() {
  group('displayPlaca (Spec 19)', () {
    test('AC1: a bare distance is composed with the prefix', () {
      expect(displayPlaca('28', prefix: _calle20a3), 'CALLE 20A # 3-28');
    });

    test('AC2: a full address is shown once, never composed', () {
      expect(displayPlaca('CALLE 20A # 3-11', prefix: _calle20a3),
          'CALLE 20A # 3-11');
    });

    test('AC3: a cruce is shown as stored', () {
      expect(displayPlaca('CALLE 20A CON CARRERA 4', prefix: _calle20a3),
          'CALLE 20A CON CARRERA 4');
    });

    test('AC4: the anchor face composes like any prefix', () {
      const anchorFace =
          AddressPrefix(tipoVia: 'CALLE', numVia: '13', numCruce: '3');
      expect(displayPlaca('28', prefix: anchorFace), 'CALLE 13 # 3-28');
    });

    test('AC5: no prefix keeps the distance as stored', () {
      expect(displayPlaca('28'), '28');
    });

    test('nothing stored → null (each screen keeps its empty states, BR6)', () {
      expect(displayPlaca(null, prefix: _calle20a3), isNull);
      expect(displayPlaca('   ', prefix: _calle20a3), isNull);
    });

    test('BR10: a distance with a letter or BIS is still a distance', () {
      expect(displayPlaca('28A', prefix: _calle20a3), 'CALLE 20A # 3-28A');
      expect(
          displayPlaca('28 BIS', prefix: _calle20a3), 'CALLE 20A # 3-28 BIS');
    });

    test('abbreviated, lowercase or padded vias read as full addresses', () {
      expect(
          displayPlaca('CL 20A # 3-11', prefix: _calle20a3), 'CL 20A # 3-11');
      expect(displayPlaca('KR 4 # 20-05', prefix: _calle20a3), 'KR 4 # 20-05');
      expect(displayPlaca('  calle 20a # 3-11 ', prefix: _calle20a3),
          'calle 20a # 3-11');
    });

    test('a typo without via is composed as typed (edge case, accepted)', () {
      expect(displayPlaca('3-11', prefix: _calle20a3), 'CALLE 20A # 3-3-11');
    });

    test('BR7: a place name with no prefix is shown as is', () {
      expect(displayPlaca('FINCA CANAÁN'), 'FINCA CANAÁN');
    });

    test('the face cardinal lands where composeParadaAddress places it', () {
      const sur = AddressPrefix(
          tipoVia: 'CALLE',
          numVia: '11',
          numCruce: '3A',
          cardinal: 'SUR',
          cardinalPosicion: 'via');
      expect(displayPlaca('15', prefix: sur), 'CALLE 11 SUR # 3A-15');
    });
  });

  group('startsWithVia (Spec 19 BR1)', () {
    test('via types, abbreviations and accents', () {
      for (final t in [
        'CALLE 5',
        'CARRERA 3',
        'AV 7',
        'DIAGONAL 2',
        'TRANSVERSAL 9',
        'cll 4',
      ]) {
        expect(startsWithVia(t), isTrue, reason: t);
      }
    });

    test('distances, place names and empty text are not', () {
      for (final t in ['28', '28A', '28 BIS', 'FINCA CANAÁN', '', '   ']) {
        expect(startsWithVia(t), isFalse, reason: t);
      }
    });
  });
}

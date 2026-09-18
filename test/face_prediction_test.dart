import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/parada/face_prediction.dart';

// A face on the odd acera (parity 1): CARRERA 2, generadora 4.
const _odd = [
  'CARRERA 2 # 4-09',
  'CARRERA 2 # 4-15',
  'CARRERA 2 # 4-23',
  'CARRERA 2 # 4-41',
];
// The even acera (parity 0) of the SAME vía+generadora — a different face.
const _even = [
  'CARRERA 2 # 4-04',
  'CARRERA 2 # 4-08',
  'CARRERA 2 # 4-16',
  'CARRERA 2 # 4-74',
];

void main() {
  group('parseFaceAddress', () {
    test('parses via / num_via / num_cruce / placa + parity', () {
      final f = parseFaceAddress('CALLE 5 # 2-06')!;
      expect(f.via, 'CALLE');
      expect(f.numVia, '5');
      expect(f.numCruce, '2');
      expect(f.placa, '06');
      expect(f.placaNum, 6);
      expect(f.parity, 0);
    });

    test('a lettered generadora keeps the placa numeric', () {
      final f = parseFaceAddress('CALLE 13 # 3A-08')!;
      expect(f.numCruce, '3A');
      expect(f.placaNum, 8);
      expect(f.faceKey, 'CALLE|13|3A|0');
    });

    test('a non-structured address is null (rural / unparseable)', () {
      expect(parseFaceAddress('SAMARIA'), isNull);
      expect(parseFaceAddress('CALLE 5 2 06'), isNull); // no " # "
    });
  });

  group('prediction — the pinned BDD examples (PS5–PS7)', () {
    test('ascending: anchor at the minimum → next entry', () {
      final p = predictNext(anchorDireccionNorm: 'CARRERA 2 # 4-09',
          manzanaR1: _odd);
      expect(p.direction, FaceDirection.ascendente);
      expect(p.expectedDireccion, 'CARRERA 2 # 4-15');
    });

    test('descending: anchor at the maximum → previous entry', () {
      final p = predictNext(anchorDireccionNorm: 'CARRERA 2 # 4-74',
          manzanaR1: _even);
      expect(p.direction, FaceDirection.descendente);
      expect(p.expectedDireccion, 'CARRERA 2 # 4-16');
    });

    test('middle start warns and leaves direction unresolved', () {
      final p = predictNext(anchorDireccionNorm: 'CARRERA 2 # 4-23',
          manzanaR1: _odd);
      expect(p.direction, FaceDirection.indeterminada);
      expect(p.warning, 'esta placa no inicia la cara');
      expect(p.expectedDireccion, isNull);
    });
  });

  group('parity separates the two aceras', () {
    test('an odd anchor never predicts an even placa', () {
      // The manzana carries BOTH aceras; the face list must stay odd-only.
      final p = predictNext(
        anchorDireccionNorm: 'CARRERA 2 # 4-09',
        manzanaR1: [..._odd, ..._even],
      );
      expect(p.direction, FaceDirection.ascendente);
      expect(p.expectedDireccion, 'CARRERA 2 # 4-15'); // not 4-04/4-08
    });
  });

  group('stored direction is honoured (no re-flip)', () {
    test('a middle anchor WITH a stored direction predicts, no warning', () {
      final p = predictNext(
        anchorDireccionNorm: 'CARRERA 2 # 4-15',
        manzanaR1: _odd,
        direction: FaceDirection.ascendente,
      );
      expect(p.direction, FaceDirection.ascendente);
      expect(p.expectedDireccion, 'CARRERA 2 # 4-23');
      expect(p.warning, isNull);
    });
  });

  group('end of face', () {
    test('ascending past the last entry → null, endOfFace', () {
      final p = predictNext(
        anchorDireccionNorm: 'CARRERA 2 # 4-41',
        manzanaR1: _odd,
        direction: FaceDirection.ascendente,
      );
      expect(p.expectedDireccion, isNull);
      expect(p.endOfFace, isTrue);
    });

    test('descending past the first entry → null, endOfFace', () {
      final p = predictNext(
        anchorDireccionNorm: 'CARRERA 2 # 4-04',
        manzanaR1: _even,
        direction: FaceDirection.descendente,
      );
      expect(p.expectedDireccion, isNull);
      expect(p.endOfFace, isTrue);
    });
  });

  group('degrades, never crashes', () {
    test('a rural anchor yields no prediction (indeterminada)', () {
      final p = predictNext(anchorDireccionNorm: 'VEREDA X', manzanaR1: _odd);
      expect(p.direction, FaceDirection.indeterminada);
      expect(p.expectedDireccion, isNull);
    });

    test('a lone placa on the face is an immediate end', () {
      final p = predictNext(
          anchorDireccionNorm: 'CARRERA 2 # 4-09',
          manzanaR1: const ['CARRERA 2 # 4-09']);
      expect(p.expectedDireccion, isNull);
      expect(p.endOfFace, isTrue);
    });
  });
}

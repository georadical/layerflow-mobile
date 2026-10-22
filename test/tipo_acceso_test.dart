import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/address/tipo_acceso.dart';

/// TA.2 — Spec 20: the built-corner rule and the shared option list.
void main() {
  group('isBuiltCorner (Spec 20 BR1)', () {
    test('Construido + cruce is a built corner', () {
      expect(
          isBuiltCorner(
              esLote: false, placa: 'CALLE 13 CON CARRERA 3', sinPlaca: false),
          isTrue);
    });

    test('lowercase / abbreviated cruce still counts', () {
      expect(
          isBuiltCorner(
              esLote: false, placa: 'calle 13 con kr 3', sinPlaca: false),
          isTrue);
    });

    test('Construido + "sin placa a la vista" is a built corner', () {
      expect(isBuiltCorner(esLote: false, placa: '', sinPlaca: true), isTrue);
    });

    test('a lot is never one, cruce or not (BR4)', () {
      expect(
          isBuiltCorner(
              esLote: true, placa: 'CALLE 13 CON CARRERA 3', sinPlaca: false),
          isFalse);
      expect(isBuiltCorner(esLote: true, placa: '', sinPlaca: true), isFalse);
    });

    test('a normal placa, a distance or an empty field is not (BR3)', () {
      for (final p in ['CALLE 13 # 3-20', '28', '']) {
        expect(isBuiltCorner(esLote: false, placa: p, sinPlaca: false), isFalse,
            reason: p);
      }
    });

    test('CON without a via after it is not a cruce', () {
      expect(
          isBuiltCorner(esLote: false, placa: 'CALLE 13 CON', sinPlaca: false),
          isFalse);
    });
  });

  group('tipoAccesoMissing (Spec 20 BR2/BR7)', () {
    test('a built corner without access type must not save', () {
      expect(tipoAccesoMissing(builtCorner: true), isTrue);
      expect(tipoAccesoMissing(builtCorner: true, tipoAcceso: ''), isTrue);
    });

    test('any option satisfies it, "otro" included', () {
      for (final key in tipoAccesoOptions.keys) {
        expect(tipoAccesoMissing(builtCorner: true, tipoAcceso: key), isFalse,
            reason: key);
      }
    });

    test('not a built corner → never missing', () {
      expect(tipoAccesoMissing(builtCorner: false), isFalse);
    });
  });

  test(
      'the shared list: four options, in order, with sin_entrada_visible '
      '(BR5/BR6/BR13)', () {
    expect(tipoAccesoOptions.keys,
        ['puerta_calle', 'area_comun', 'sin_entrada_visible', 'otro']);
    expect(tipoAccesoOptions['sin_entrada_visible'], 'Sin entrada visible');
    expect(tipoAccesoOptions['area_comun'], 'Área común (hall/escalera/patio)');
  });
}

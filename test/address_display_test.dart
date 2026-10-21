import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/core/parada/address_display.dart';
import 'package:layerflow_capture/core/parada/face_prediction.dart';
import 'package:layerflow_capture/data/db/database.dart';

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

  group('prefixesForParada (Spec 19 BR3, AD.3)', () {
    // R1 rows of the manzana, by npn.
    final r1 = <String, FaceAddress>{
      'n303': _face('CALLE', '13', '3', '03'),
      'n405': _face('CALLE', '13', '4', '05'),
    };
    Future<FaceAddress?> lookup(Capture c) async => r1[c.npn];

    test('the parada terna applies to every capture', () async {
      final caps = [
        _cap('a', 1, placa: 'CALLE 20A # 3-03', npn: 'n303'),
        _cap('b', 2, placa: '28'),
        _cap('c', 3, placa: 'CALLE 20A CON CARRERA 4'),
      ];
      final p = await prefixesForParada(
          onStop: caps,
          tipoVia: 'CALLE',
          numVia: '20A',
          numCruce: '3',
          r1FaceOf: lookup);
      expect(caps.map((c) => _shown(p, c)), [
        'CALLE 20A # 3-03',
        'CALLE 20A # 3-28',
        'CALLE 20A CON CARRERA 4',
      ]);
    });

    test('no terna: a distance composes from the anchor face in force',
        () async {
      final caps = [
        _cap('a', 1, placa: 'CALLE 13 # 3-03', npn: 'n303'),
        _cap('b', 2, placa: '28'),
        _cap('c', 3, placa: 'CALLE 13 # 4-05', npn: 'n405'), // Coincide on 4-05
        _cap('d', 4, placa: '12'),
      ];
      final p = await prefixesForParada(onStop: caps, r1FaceOf: lookup);
      expect(p.containsKey('a'), isFalse,
          reason: 'the first capture is the anchor itself');
      expect(caps.map((c) => _shown(p, c)), [
        'CALLE 13 # 3-03',
        'CALLE 13 # 3-28',
        'CALLE 13 # 4-05',
        'CALLE 13 # 4-12', // the face moved with the new anchor
      ]);
    });

    test('a "sin placa a la vista" anchor gives its R1 face', () async {
      final caps = [
        _cap('a', 1, npn: 'n303'), // placa null + link
        _cap('b', 2, placa: '28'),
      ];
      final p = await prefixesForParada(onStop: caps, r1FaceOf: lookup);
      expect(_shown(p, caps[1]), 'CALLE 13 # 3-28');
    });

    test('a hallazgo anchor (no R1 link) is parsed from its placa', () async {
      final caps = [
        _cap('a', 1, placa: 'CALLE 13 # 3-01'), // not in R1
        _cap('b', 2, placa: '28'),
      ];
      final p = await prefixesForParada(onStop: caps, r1FaceOf: lookup);
      expect(_shown(p, caps[1]), 'CALLE 13 # 3-28');
    });

    test('a linked anchor wins over a later unlinked capture', () async {
      final caps = [
        _cap('a', 1, placa: 'CALLE 13 # 3-03', npn: 'n303'),
        _cap('b', 2, placa: 'CALLE 20 # 9-99'), // hallazgo, not an anchor
        _cap('c', 3, placa: '28'),
      ];
      final p = await prefixesForParada(onStop: caps, r1FaceOf: lookup);
      expect(_shown(p, caps[2]), 'CALLE 13 # 3-28');
    });

    test('no anchor face available → shown as stored (BR4)', () async {
      final caps = [
        _cap('a', 1, placa: 'FINCA CANAÁN'),
        _cap('b', 2, placa: '28'),
      ];
      expect(
          _shown(
              await prefixesForParada(onStop: caps, r1FaceOf: lookup), caps[1]),
          '28');
      // No manzana / tenant: the anchor path is skipped altogether.
      final linked = [
        _cap('a', 1, placa: 'CALLE 13 # 3-03', npn: 'n303'),
        _cap('b', 2, placa: '28'),
      ];
      expect(_shown(await prefixesForParada(onStop: linked), linked[1]), '28');
    });

    test('the parada cardinal rides on the anchor face', () async {
      final caps = [
        _cap('a', 1, placa: 'CALLE 13 # 3-03', npn: 'n303'),
        _cap('b', 2, placa: '28'),
      ];
      final p = await prefixesForParada(
          onStop: caps,
          cardinal: 'SUR',
          cardinalPosicion: 'placa',
          r1FaceOf: lookup);
      expect(_shown(p, caps[1]), 'CALLE 13 # 3-28 SUR');
    });
  });
}

Capture _cap(String id, int pos,
        {String? placa, String? npn, String? direccionNorm}) =>
    Capture(
      clientId: id,
      routeId: 'r',
      posicion: pos,
      stopId: 's',
      placa: placa,
      npn: npn,
      direccionNorm: direccionNorm,
      sinR1: false,
      esLote: false,
      syncStatus: AppConfig.syncPending,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

FaceAddress _face(String via, String numVia, String numCruce, String placa) =>
    FaceAddress(
      direccionNorm: '$via $numVia # $numCruce-$placa',
      via: via,
      numVia: numVia,
      numCruce: numCruce,
      placa: placa,
      placaNum: int.parse(placa.replaceAll(RegExp(r'\D'), '')),
    );

String? _shown(Map<String, AddressPrefix> p, Capture c) =>
    displayPlaca(c.placa, prefix: p[c.clientId]);

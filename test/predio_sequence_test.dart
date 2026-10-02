import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/core/parada/predio_sequence.dart';
import 'package:layerflow_capture/data/db/database.dart';

Capture _cap({
  required String clientId,
  required int posicion,
  String? stopId,
  int? secuenciaParada,
}) =>
    Capture(
      clientId: clientId,
      routeId: 'r1',
      posicion: posicion,
      stopId: stopId,
      secuenciaParada: secuenciaParada,
      sinR1: false,
      syncStatus: AppConfig.syncPending,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('predioDisplayFor (Spec 11, SP.5)', () {
    test('no stop_id → legacy ("predio —")', () {
      final c = _cap(clientId: 'a', posicion: 1);
      final d = predioDisplayFor(c, [c]);
      expect(d.legacy, isTrue);
    });

    test('a synced secuencia_parada shows verbatim (definitive)', () {
      final c =
          _cap(clientId: 'a', posicion: 1, stopId: 's1', secuenciaParada: 4);
      final d = predioDisplayFor(c, [c]);
      expect(d.legacy, isFalse);
      expect(d.provisional, isFalse);
      expect(d.number, 4); // gap-verbatim: shows 4 even if alone
    });

    test('provisional: +1 ordering within a parada, in capture order', () {
      final all = [
        _cap(clientId: 'a', posicion: 1, stopId: 's1'),
        _cap(clientId: 'b', posicion: 2, stopId: 's1'),
        _cap(clientId: 'c', posicion: 3, stopId: 's1'),
      ];
      expect(predioDisplayFor(all[0], all).number, 1);
      expect(predioDisplayFor(all[1], all).number, 2);
      expect(predioDisplayFor(all[2], all).number, 3);
      expect(all.every((c) => predioDisplayFor(c, all).provisional), isTrue);
    });

    test('restarts at 1 on each parada', () {
      final all = [
        _cap(clientId: 'a', posicion: 1, stopId: 'sA'),
        _cap(clientId: 'b', posicion: 2, stopId: 'sA'),
        _cap(clientId: 'c', posicion: 3, stopId: 'sB'), // next parada
        _cap(clientId: 'd', posicion: 4, stopId: 'sB'),
      ];
      expect(predioDisplayFor(all[0], all).number, 1);
      expect(predioDisplayFor(all[1], all).number, 2);
      expect(predioDisplayFor(all[2], all).number, 1); // restart
      expect(predioDisplayFor(all[3], all).number, 2);
    });

    test('provisional rank continues past already-synced predios on the parada',
        () {
      final all = [
        _cap(clientId: 'a', posicion: 1, stopId: 's1', secuenciaParada: 1),
        _cap(clientId: 'b', posicion: 2, stopId: 's1', secuenciaParada: 2),
        _cap(clientId: 'c', posicion: 3, stopId: 's1'), // new, unsynced
      ];
      final d = predioDisplayFor(all[2], all);
      expect(d.provisional, isTrue);
      expect(d.number, 3); // continues the local count, not restart
    });
  });
}

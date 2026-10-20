import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/ui/widgets/sin_placa.dart';

/// SE.5 — Spec 18 BR1: "sin placa a la vista" ≡ no placa + an R1 link (not a lot).
Capture _c(
        {String? placa,
        String? npn,
        String? direccionNorm,
        bool lote = false}) =>
    Capture(
      clientId: 'c',
      routeId: 'r',
      posicion: 1,
      placa: placa,
      npn: npn,
      direccionNorm: direccionNorm,
      sinR1: false,
      esLote: lote,
      syncStatus: AppConfig.syncPending,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('isSinPlaca (Spec 18 BR1)', () {
    test('no placa + npn link → sin placa a la vista', () {
      expect(isSinPlaca(_c(npn: '4155')), isTrue);
      expect(isSinPlaca(_c(placa: '   ', npn: '4155')), isTrue);
    });

    test('no placa + multi-unit link (direccion_norm) → sin placa a la vista',
        () {
      expect(isSinPlaca(_c(direccionNorm: 'CALLE 20A # 3-03')), isTrue);
    });

    test('a placa read on the door is not "sin placa"', () {
      expect(isSinPlaca(_c(placa: 'CALLE 20A # 3-03', npn: '4155')), isFalse);
    });

    test('no placa and no link is a plain missing address', () {
      expect(isSinPlaca(_c()), isFalse);
    });

    test('a lot never reads as "sin placa a la vista"', () {
      expect(isSinPlaca(_c(npn: '4155', lote: true)), isFalse);
    });
  });
}

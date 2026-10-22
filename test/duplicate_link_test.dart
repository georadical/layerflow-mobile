import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/core/parada/duplicate_link.dart';
import 'package:layerflow_capture/data/db/database.dart';

/// DUP.2 — the other capture holding the same R1 link, and the located text.
Capture _c(
  String id,
  int posicion, {
  String? npn,
  String? direccionNorm,
  String? stopId = 's1',
  int? secuenciaParada,
}) =>
    Capture(
      clientId: id,
      routeId: 'r',
      posicion: posicion,
      stopId: stopId,
      npn: npn,
      direccionNorm: direccionNorm,
      secuenciaParada: secuenciaParada,
      sinR1: false,
      esLote: false,
      syncStatus: AppConfig.syncPending,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  final route = [
    _c('a', 1, npn: 'n303'),
    _c('b', 2, direccionNorm: 'CALLE 14 # 2-104'),
    _c('c', 3, npn: 'n311', direccionNorm: null),
  ];

  group('duplicateLinkOf (DR1)', () {
    test('the same npn elsewhere in the route', () {
      expect(duplicateLinkOf(routeCaptures: route, npn: 'n303')?.clientId, 'a');
    });

    test('the same placa-level link (direccion_norm, npn null)', () {
      expect(
          duplicateLinkOf(
                  routeCaptures: route, direccionNorm: 'CALLE 14 # 2-104')
              ?.clientId,
          'b');
    });

    test('an npn link never matches a placa-level one and vice versa', () {
      expect(duplicateLinkOf(routeCaptures: route, npn: 'n104'), isNull);
      // 'c' has an npn: a placa-level lookup must not match it by address.
      final withBoth = [
        _c('x', 1, npn: 'n1', direccionNorm: 'CALLE 1 # 1-01'),
      ];
      expect(
          duplicateLinkOf(
              routeCaptures: withBoth, direccionNorm: 'CALLE 1 # 1-01'),
          isNull);
    });

    test('AC-D3: the capture being edited never counts', () {
      expect(
          duplicateLinkOf(
              routeCaptures: route, npn: 'n303', excludeClientId: 'a'),
          isNull);
    });

    test('no link → nothing to compare', () {
      expect(duplicateLinkOf(routeCaptures: route), isNull);
    });
  });

  group('duplicateLinkMessage (DR2)', () {
    test('names the parada and the provisional predio', () {
      expect(
          duplicateLinkMessage(route[0], route, faceSequence: 1),
          'Esa placa de R1 ya está enlazada en la parada 1 · predio ~1. '
          'Revisa que sea otra puerta.');
    });

    test('a synced predio shows its definitive number', () {
      final synced = _c('s', 9, npn: 'n9', secuenciaParada: 4);
      expect(duplicateLinkMessage(synced, [synced], faceSequence: 2),
          contains('la parada 2 · predio 4.'));
    });

    test('no parada → "otro predio de esta ruta"', () {
      final loose = _c('l', 1, npn: 'n1', stopId: null);
      expect(duplicateLinkMessage(loose, [loose]),
          contains('en otro predio de esta ruta.'));
    });
  });
}

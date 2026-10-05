import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/ui/providers.dart';
import 'package:layerflow_capture/ui/screens/parada_list_screen.dart';

/// PL.2 gate — the real ParadaListScreen renders the correct states
/// (barrida / en curso / pendiente) and per-parada counts from the providers,
/// for a multi-parada route (Ruta 10 shape) and a single-parada one (Ruta 20).
Parada _parada(String stopId, int seq, {required bool swept, String? manzana}) =>
    Parada(
      stopId: stopId,
      routeId: 'r1',
      faceSequence: seq,
      swept: swept,
      sweptSynced: true,
      updatedAt: DateTime(2026),
      manzana: manzana,
    );

Capture _cap(String id, String stopId, String sync) => Capture(
      clientId: id,
      routeId: 'r1',
      posicion: 1,
      stopId: stopId,
      sinR1: false,
      esLote: false,
      syncStatus: sync,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Widget _host(List<Parada> stops, List<Capture> caps) => ProviderScope(
      overrides: [
        routeStopsProvider.overrideWith((ref, routeId) => Stream.value(stops)),
        capturesProvider.overrideWith((ref, routeId) => Stream.value(caps)),
        espNameProvider.overrideWith((ref) => Future.value('ESP test')),
      ],
      child:
          const MaterialApp(home: ParadaListScreen(routeId: 'r1', codigo: '10')),
    );

void main() {
  group('ParadaListScreen (Spec 16, PL.2)', () {
    testWidgets('multi-parada: one en curso, earlier barrida, counts right',
        (tester) async {
      final stops = [
        _parada('s1', 1, swept: true, manzana: '41551010100000005'),
        _parada('s2', 2, swept: false, manzana: '41551010100000005'),
        _parada('s3', 3, swept: false, manzana: '41551010100000327'),
      ];
      final caps = [
        _cap('c1', 's1', AppConfig.syncSynced),
        _cap('c2', 's1', AppConfig.syncSynced),
        _cap('c3', 's2', AppConfig.syncPending),
      ];
      await tester.pumpWidget(_host(stops, caps));
      await tester.pumpAndSettle();

      // BR1: exactly one current (s2, the lowest unswept); s1 swept; s3 locked.
      expect(find.text('en curso'), findsOneWidget);
      expect(find.text('barrida'), findsOneWidget);
      expect(find.text('Parada 2'), findsOneWidget);
      // Progress header.
      expect(find.text('1 / 3 barridas'), findsOneWidget);
      // Per-parada counts.
      expect(find.textContaining('2 placas'), findsOneWidget); // s1
      expect(find.textContaining('1 placa · 1 sin enviar'),
          findsOneWidget); // s2
      expect(find.textContaining('pendiente'), findsOneWidget); // s3
    });

    testWidgets('single parada (Ruta 20 shape)', (tester) async {
      final stops = [
        _parada('s1', 1, swept: false, manzana: '41551010100000005'),
      ];
      await tester.pumpWidget(_host(stops, const []));
      await tester.pumpAndSettle();
      expect(find.text('en curso'), findsOneWidget);
      expect(find.text('0 / 1 barridas'), findsOneWidget);
    });

    testWidgets('all swept → Ruta barrida, nothing en curso', (tester) async {
      final stops = [
        _parada('s1', 1, swept: true, manzana: '41551010100000005'),
        _parada('s2', 2, swept: true, manzana: '41551010100000005'),
      ];
      await tester.pumpWidget(_host(stops, const []));
      await tester.pumpAndSettle();
      expect(find.text('Ruta barrida'), findsOneWidget);
      expect(find.text('en curso'), findsNothing);
      expect(find.text('2 / 2 barridas'), findsOneWidget);
    });
  });
}

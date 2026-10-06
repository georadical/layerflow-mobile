import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/config/app_config.dart';
import 'package:layerflow_capture/data/db/database.dart' hide Route;
import 'package:layerflow_capture/ui/providers.dart';
import 'package:layerflow_capture/ui/screens/parada_list_screen.dart';

/// PL.2 — the real ParadaListScreen renders the correct states
/// (barrida / en curso / pendiente) and per-parada counts from the providers.
/// PL.3 — the hard-lock navigation: a locked parada is inert (hint, no nav),
/// a done parada opens read-only (never capture).
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

Capture _cap(
  String id,
  String stopId,
  String sync, {
  String? placa,
  int posicion = 1,
}) =>
    Capture(
      clientId: id,
      routeId: 'r1',
      posicion: posicion,
      stopId: stopId,
      placa: placa,
      sinR1: false,
      esLote: false,
      syncStatus: sync,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class _PushCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushes++;
}

Widget _host(
  List<Parada> stops,
  List<Capture> caps, {
  NavigatorObserver? observer,
}) =>
    ProviderScope(
      overrides: [
        routeStopsProvider.overrideWith((ref, routeId) => Stream.value(stops)),
        capturesProvider.overrideWith((ref, routeId) => Stream.value(caps)),
        espNameProvider.overrideWith((ref) => Future.value('ESP test')),
      ],
      child: MaterialApp(
        home: const ParadaListScreen(routeId: 'r1', codigo: '10'),
        navigatorObservers: observer != null ? [observer] : const [],
      ),
    );

void main() {
  final threeStops = [
    _parada('s1', 1, swept: true, manzana: '41551010100000005'),
    _parada('s2', 2, swept: false, manzana: '41551010100000005'),
    _parada('s3', 3, swept: false, manzana: '41551010100000327'),
  ];
  final caps = [
    _cap('c1', 's1', AppConfig.syncSynced, placa: 'CALLE 14 # 2-104'),
    _cap('c2', 's1', AppConfig.syncSynced, placa: 'CALLE 14 # 2-112', posicion: 2),
    _cap('c3', 's2', AppConfig.syncPending, placa: 'CARRERA 2 # 4-09'),
  ];

  group('ParadaListScreen render (Spec 16, PL.2)', () {
    testWidgets('multi-parada: one en curso, earlier barrida, counts right',
        (tester) async {
      await tester.pumpWidget(_host(threeStops, caps));
      await tester.pumpAndSettle();

      expect(find.text('en curso'), findsOneWidget); // s2, lowest unswept
      expect(find.text('barrida'), findsOneWidget); // s1
      expect(find.text('Parada 2'), findsOneWidget);
      expect(find.text('1 / 3 barridas'), findsOneWidget);
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

  group('ParadaListScreen hard-lock navigation (Spec 16, PL.3)', () {
    testWidgets('tapping a locked parada is inert: hint, no navigation',
        (tester) async {
      final obs = _PushCounter();
      await tester.pumpWidget(_host(threeStops, caps, observer: obs));
      await tester.pumpAndSettle();
      final before = obs.pushes;

      await tester.tap(find.text('Parada 3')); // pending (locked)
      await tester.pump(); // let the SnackBar appear

      expect(find.text('Se desbloquea al cerrar la parada anterior.'),
          findsOneWidget);
      expect(obs.pushes, before, reason: 'a locked parada must not navigate');
      // Still on the list.
      expect(find.text('1 / 3 barridas'), findsOneWidget);
    });

    testWidgets('tapping a done parada opens its captures read-only',
        (tester) async {
      await tester.pumpWidget(_host(threeStops, caps));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parada 1')); // done
      await tester.pumpAndSettle();

      // The read-only view, not the capture screen.
      expect(find.text('Parada 1 · barrida'), findsOneWidget);
      expect(find.text('CALLE 14 # 2-104'), findsOneWidget);
      expect(find.text('CALLE 14 # 2-112'), findsOneWidget);
      // No capture affordances on a read-only view.
      expect(find.text('Guardar y siguiente'), findsNothing);
    });
  });
}

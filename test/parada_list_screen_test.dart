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
Parada _parada(
  String stopId,
  int seq, {
  required bool swept,
  String? manzana,
  String? sweepError,
}) =>
    Parada(
      stopId: stopId,
      routeId: 'r1',
      faceSequence: seq,
      swept: swept,
      sweptSynced: true,
      updatedAt: DateTime(2026),
      manzana: manzana,
      sweepError: sweepError,
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

NoEncontrado _ne(
  String id,
  String stopId, {
  required String direccionNorm,
  String? observacion,
  String sync = AppConfig.syncPending,
}) =>
    NoEncontrado(
      clientId: id,
      routeId: 'r1',
      direccionNorm: direccionNorm,
      stopId: stopId,
      observacion: observacion,
      syncStatus: sync,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class _PushCounter extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

Widget _host(
  List<Parada> stops,
  List<Capture> caps, {
  NavigatorObserver? observer,
  bool online = true,
  void Function(BuildContext context, String routeId)? onNoParadas,
  List<NoEncontrado> notFound = const [],
}) =>
    ProviderScope(
      overrides: [
        routeStopsProvider.overrideWith((ref, routeId) => Stream.value(stops)),
        capturesProvider.overrideWith((ref, routeId) => Stream.value(caps)),
        noEncontradosProvider
            .overrideWith((ref, routeId) => Stream.value(notFound)),
        espNameProvider.overrideWith((ref) => Future.value('ESP test')),
        // PL.4: the list is the route home — it fires the sync moment and
        // carries the SendBar. Stub the sync + the send-bar's DB-backed
        // providers so the widget test stays DB-free and deterministic.
        routeFrameProvider.overrideWith((ref, routeId) async {}),
        isOnlineProvider.overrideWithValue(online),
        isOnWifiProvider.overrideWithValue(true),
        pendingEvidenceCountProvider
            .overrideWith((ref, routeId) => Stream.value(0)),
        pendingSurveyCountProvider
            .overrideWith((ref, routeId) => Stream.value(0)),
        routeRowProvider.overrideWith((ref, routeId) => Stream.value(null)),
      ],
      child: MaterialApp(
        home: ParadaListScreen(
          routeId: 'r1',
          codigo: '10',
          onNoParadas: onNoParadas,
        ),
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
    _cap('c2', 's1', AppConfig.syncSynced,
        placa: 'CALLE 14 # 2-112', posicion: 2),
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
      expect(
          find.textContaining('1 placa · 1 sin enviar'), findsOneWidget); // s2
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

  group('ParadaListScreen route-home integration (Spec 16, PL.4)', () {
    testWidgets('SendBar + "Revisar / editar" on the route home',
        (tester) async {
      await tester.pumpWidget(_host(threeStops, caps)); // caps has one pending
      await tester.pumpAndSettle();
      // The queue's Enviar rides on the list header now (D1).
      expect(find.text('Enviar'), findsOneWidget);
      // The full captures view + editor are reachable (resume demoted).
      expect(find.byTooltip('Revisar / editar placas'), findsOneWidget);
    });

    testWidgets('no SendBar when everything is synced', (tester) async {
      final synced = [_cap('c1', 's1', AppConfig.syncSynced, placa: 'A')];
      final stops = [
        _parada('s1', 1, swept: true, manzana: '41551010100000005'),
        _parada('s2', 2, swept: false, manzana: '41551010100000005'),
      ];
      await tester.pumpWidget(_host(stops, synced));
      await tester.pumpAndSettle();
      expect(find.text('Enviar'), findsNothing); // nothing queued → no bar
    });
  });

  group('ParadaListScreen sweep-rejection banner (Spec 16, PL.6)', () {
    testWidgets('a server-rejected sweep surfaces the reopen banner',
        (tester) async {
      final stops = [
        _parada('s1', 1,
            swept: true,
            manzana: '41551010100000005',
            sweepError: 'foto_obligatoria_pendiente en loc 5'),
        _parada('s2', 2, swept: false, manzana: '41551010100000005'),
      ];
      await tester.pumpWidget(_host(stops, const []));
      await tester.pumpAndSettle();
      // The banner names the parada (not "cara"), the reason, and offers reopen.
      expect(find.text('Parada 1 no cerró en el servidor'), findsOneWidget);
      expect(find.textContaining('foto_obligatoria_pendiente'), findsOneWidget);
      expect(find.text('Reabrir'), findsOneWidget);
    });

    testWidgets('no banner when no sweep was rejected', (tester) async {
      await tester.pumpWidget(_host(threeStops, const []));
      await tester.pumpAndSettle();
      expect(find.text('Reabrir'), findsNothing);
    });
  });

  group('ParadaListScreen no-paradas fallback (Spec 16, PL.7)', () {
    testWidgets('online + synced + 0 paradas → auto-skips to classic capture',
        (tester) async {
      String? skippedRoute;
      await tester.pumpWidget(_host(
        const [],
        const [],
        onNoParadas: (_, routeId) => skippedRoute = routeId,
      ));
      // No pumpAndSettle: the auto-skip leaves a spinner (infinite animation).
      // The sync future (async {}) resolves, _NoParadasFallback sees AsyncData
      // and schedules the post-frame skip, which then fires.
      await tester.pump(); // frame resolves → rebuild schedules the post-frame
      await tester.pump(); // post-frame callback runs → onNoParadas

      expect(skippedRoute, 'r1');
      // The manual fallback is never shown for a confirmed no-paradas route.
      expect(find.text('Esta ruta no tiene paradas.'), findsNothing);
      expect(find.text('Capturar'), findsNothing);
    });

    testWidgets('offline + 0 paradas → manual fallback, no auto-skip',
        (tester) async {
      var skipped = false;
      await tester.pumpWidget(_host(
        const [],
        const [],
        online: false,
        onNoParadas: (_, __) => skipped = true,
      ));
      await tester.pumpAndSettle();

      // Can't tell "no paradas" from "not synced" offline → keep the manual
      // fallback; never silently bypass a route that may still have paradas.
      expect(skipped, isFalse);
      expect(find.text('Esta ruta no tiene paradas.'), findsOneWidget);
      expect(find.text('Capturar'), findsOneWidget);
    });
  });

  group('ParadaCapturesScreen not-found rows (Spec 14, NE.6)', () {
    final sweptStops = [
      _parada('s1', 1, swept: true, manzana: '41551010100000327'),
      _parada('s2', 2, swept: false, manzana: '41551010100000327'),
    ];

    testWidgets('a swept parada shows its not-found, distinct + undoable',
        (tester) async {
      final notFound = [
        _ne('n1', 's1',
            direccionNorm: 'CALLE 13 # 3-20',
            observacion: 'demolido, hoy parqueadero'),
      ];
      await tester.pumpWidget(_host(sweptStops, const [], notFound: notFound));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parada 1')); // done → read-only view
      await tester.pumpAndSettle();

      expect(find.text('CALLE 13 # 3-20'), findsOneWidget);
      expect(find.textContaining('No encontrada en campo'), findsOneWidget);
      expect(find.textContaining('demolido, hoy parqueadero'), findsOneWidget);
      expect(find.text('Deshacer'), findsOneWidget); // pending → reversible
    });

    testWidgets('a SENT not-found is not undoable (no Deshacer)',
        (tester) async {
      final notFound = [
        _ne('n1', 's1',
            direccionNorm: 'CALLE 13 # 3-20', sync: AppConfig.syncSynced),
      ];
      await tester.pumpWidget(_host(sweptStops, const [], notFound: notFound));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parada 1'));
      await tester.pumpAndSettle();

      expect(find.text('CALLE 13 # 3-20'), findsOneWidget);
      expect(find.text('Deshacer'), findsNothing); // sent → replacement-undo only
    });
  });
}

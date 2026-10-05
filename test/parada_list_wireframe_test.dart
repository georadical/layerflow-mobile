import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/ui/wireframes/parada_list_wireframe.dart';

/// PL.1 gate — the wireframe renders every UI state without throwing, and the
/// hard-lock layout reads correctly (one current parada, progress, send bar).
void main() {
  group('ParadaListWireframe (Spec 16, PL.1)', () {
    for (final state in ParadaListState.values) {
      testWidgets('renders state "${state.name}" without error', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ParadaListWireframe(
              state: state,
              paradas: wireframeDummyParadas,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('list: exactly one parada "en curso", progress + Enviar shown',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ParadaListWireframe(
            state: ParadaListState.list,
            paradas: wireframeDummyParadas,
          ),
        ),
      );
      // The hard lock: exactly one current parada.
      expect(find.text('en curso'), findsOneWidget);
      // Earlier paradas read as swept.
      expect(find.text('barrida'), findsWidgets);
      // The current parada in the dummy set is #4.
      expect(find.text('Parada 4'), findsOneWidget);
      // Route-level progress header + the send bar (dummy set has sin-enviar).
      expect(find.textContaining('barridas'), findsOneWidget);
      expect(find.text('Enviar'), findsOneWidget);
    });

    testWidgets('locked parada is inert: tapping shows the unlock hint',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ParadaListWireframe(
            state: ParadaListState.list,
            paradas: wireframeDummyParadas,
          ),
        ),
      );
      await tester.tap(find.text('Parada 5')); // a pending (locked) parada
      await tester.pump(); // let the SnackBar appear
      expect(
        find.text('Se desbloquea al cerrar la parada anterior.'),
        findsOneWidget,
      );
    });

    testWidgets('allDone: header reads "Ruta barrida"', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ParadaListWireframe(state: ParadaListState.allDone),
        ),
      );
      expect(find.text('Ruta barrida'), findsOneWidget);
      expect(find.text('en curso'), findsNothing); // nothing open anymore
    });

    testWidgets('emptyFallback: names the classic-capture fallback',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ParadaListWireframe(state: ParadaListState.emptyFallback),
        ),
      );
      expect(find.text('Esta ruta no tiene paradas.'), findsOneWidget);
    });
  });
}

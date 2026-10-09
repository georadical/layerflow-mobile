import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/ui/wireframes/no_encontrado_wireframe.dart';

/// NE.1 gate — the wireframe renders every UI state without throwing, and the
/// key elements read correctly (the not-found action on the prediction card, the
/// guardrail confirm, the sweep advance, and the distinct resume row).
void main() {
  group('NoEncontradoWireframe (Spec 14, NE.1)', () {
    for (final state in NoEncontradoState.values) {
      testWidgets('renders state "${state.name}" without error', (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: NoEncontradoWireframe(state: state)),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('card: the not-found action sits on the prediction card',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NoEncontradoWireframe(state: NoEncontradoState.card)),
      );
      expect(find.text('Siguiente esperada'), findsOneWidget);
      expect(find.text('CALLE 13 # 3-20'), findsWidgets); // card + field hint
      expect(find.text('Coincide'), findsOneWidget);
      expect(find.text('No coincide'), findsOneWidget);
      // NE.1 — the new action.
      expect(find.text('No encontrada en campo'), findsOneWidget);
    });

    testWidgets('confirm: guardrail reminds "Sin construir", two-way choice',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
            home: NoEncontradoWireframe(state: NoEncontradoState.confirm)),
      );
      expect(find.text('¿CALLE 13 # 3-20 no existe en campo?'), findsOneWidget);
      expect(find.textContaining('Sin construir'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Confirmar: no existe'), findsOneWidget);
    });

    testWidgets('advanced: the sweep moved past the not-found (BR4)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
            home: NoEncontradoWireframe(state: NoEncontradoState.advanced)),
      );
      // Prediction now points at the next door.
      expect(find.text('CALLE 13 # 3-22'), findsOneWidget);
      expect(find.textContaining('marcada como no encontrada'), findsOneWidget);
    });

    testWidgets('resume: a distinct, undoable not-found row', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
            home: NoEncontradoWireframe(state: NoEncontradoState.resume)),
      );
      expect(find.textContaining('No encontrada en campo'), findsOneWidget);
      expect(find.textContaining('demolido, hoy parqueadero'), findsOneWidget);
      expect(find.text('Deshacer'), findsOneWidget);
    });
  });
}

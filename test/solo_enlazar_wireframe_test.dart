import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/ui/wireframes/solo_enlazar_wireframe.dart';

/// SE.2 gate — the wireframe renders every UI state without throwing, and the key
/// elements read correctly (the button in the link card, the locked field, the
/// Coincide path, and the distinct list row).
void main() {
  group('SoloEnlazarWireframe (Spec 18, SE.2)', () {
    Future<void> pump(WidgetTester tester, SoloEnlazarState s) =>
        tester.pumpWidget(MaterialApp(home: SoloEnlazarWireframe(state: s)));

    for (final state in SoloEnlazarState.values) {
      testWidgets('renders state "${state.name}" without error',
          (tester) async {
        await pump(tester, state);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('linked: the button sits in the link card (off)',
        (tester) async {
      await pump(tester, SoloEnlazarState.linked);
      expect(find.text('Enlazada a: CALLE 20A # 3-03'), findsOneWidget);
      expect(
          find.text('Solo enlazar — no hay placa a la vista'), findsOneWidget);
      expect(find.byTooltip('Quitar enlace'), findsOneWidget);
    });

    testWidgets(
        'sinPlaca: the field is locked and reads "Sin placa a la vista"',
        (tester) async {
      await pump(tester, SoloEnlazarState.sinPlaca);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
      expect(find.text('Sin placa a la vista'), findsOneWidget); // field hint
      expect(
          find.textContaining('toca para escribir la placa'), findsOneWidget);
      expect(find.text('Tomar foto de placa (requerida)'), findsOneWidget);
    });

    testWidgets('coincide: the link card and button appear after Coincide',
        (tester) async {
      await pump(tester, SoloEnlazarState.coincide);
      expect(find.text('Enlazada a: CALLE 20A # 3-11'), findsOneWidget);
      expect(
          find.text('Solo enlazar — no hay placa a la vista'), findsOneWidget);
    });

    testWidgets('list: the row reads "Sin placa a la vista · enlazada a …"',
        (tester) async {
      await pump(tester, SoloEnlazarState.list);
      expect(find.text('Sin placa a la vista'), findsOneWidget);
      expect(
          find.textContaining('enlazada a CALLE 20A # 3-03'), findsOneWidget);
    });
  });
}

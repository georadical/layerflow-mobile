import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/ui/widgets/linked_card.dart';

/// SE.3 — the R1 link card with the Spec 18 "Solo enlazar" toggle.
void main() {
  group('LinkedCard (Spec 18, SE.3)', () {
    Future<({int toggles, int unlinks})> pump(
      WidgetTester tester, {
      required bool sinPlaca,
      void Function()? onToggle,
      void Function()? onUnlink,
    }) async {
      var toggles = 0, unlinks = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LinkedCard(
            direccion: 'CALLE 20A # 3-03',
            typed: sinPlaca ? '' : 'CALLE 20A # 3-03',
            onUnlink: onUnlink ?? () => unlinks++,
            sinPlaca: sinPlaca,
            onToggleSinPlaca: onToggle ?? () => toggles++,
          ),
        ),
      ));
      return (toggles: toggles, unlinks: unlinks);
    }

    testWidgets('off: shows the link and the "Solo enlazar" invitation',
        (tester) async {
      await pump(tester, sinPlaca: false);
      expect(find.text('Enlazada a: CALLE 20A # 3-03'), findsOneWidget);
      expect(find.textContaining('Tú escribiste'), findsOneWidget);
      expect(
          find.text('Solo enlazar — no hay placa a la vista'), findsOneWidget);
    });

    testWidgets('on: reads as the checked state, no "Tú escribiste"',
        (tester) async {
      await pump(tester, sinPlaca: true);
      expect(find.text('Sin placa a la vista — se verifica en oficina.'),
          findsOneWidget);
      expect(
          find.textContaining('toca para escribir la placa'), findsOneWidget);
      expect(find.textContaining('Tú escribiste'), findsNothing);
    });

    testWidgets('tapping the button calls the toggle (both states)',
        (tester) async {
      var toggles = 0;
      await pump(tester, sinPlaca: false, onToggle: () => toggles++);
      await tester.tap(find.text('Solo enlazar — no hay placa a la vista'));
      await pump(tester, sinPlaca: true, onToggle: () => toggles++);
      await tester.tap(find.textContaining('toca para escribir la placa'));
      expect(toggles, 2);
    });

    testWidgets('the X removes the link', (tester) async {
      var unlinks = 0;
      await pump(tester, sinPlaca: true, onUnlink: () => unlinks++);
      await tester.tap(find.byTooltip('Quitar enlace'));
      expect(unlinks, 1);
    });
  });
}

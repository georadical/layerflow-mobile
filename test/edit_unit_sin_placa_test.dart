import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/capture_repository.dart';
import 'package:layerflow_capture/ui/providers.dart';
import 'package:layerflow_capture/ui/screens/edit_unit_screen.dart';

import 'support/sqlite3.dart';

/// SE.6 — Spec 18 BR11/AC7: editar unidad offers the same "sin placa a la
/// vista" switch, and what it saves is placa null + the link (BR1).
Future<AppDatabase?> _tryMemoryDb() async {
  useSystemSqlite3();
  try {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    return db;
  } catch (_) {
    return null;
  }
}

const _solo = 'Solo enlazar — no hay placa a la vista';
const _on = 'Sin placa a la vista · toca para escribir la placa';

void main() {
  late AppDatabase db;
  late CaptureRepository repo;

  /// Seeds one capture, opens its editor (pushed, so Guardar can pop).
  Future<String?> open(
    WidgetTester tester, {
    String? placa,
    String? npn,
    bool esLote = false,
  }) async {
    final maybe = await tester.runAsync(_tryMemoryDb);
    if (maybe == null) return null;
    db = maybe;
    addTearDown(() => tester.runAsync(db.close));
    repo = CaptureRepository(db);
    final row = (await tester.runAsync(() async {
      final id = await repo.appendCapture(
          routeId: 'r1', placa: placa, npn: npn, esLote: esLote);
      return repo.captureOf(id);
    }))!;
    // Tall enough that the editor's lazy ListView builds Guardar unscrolled.
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        activeTenantIdProvider.overrideWithValue(null),
        queueOwnerProvider.overrideWithValue(null),
        routeStopsProvider('r1').overrideWith((ref) => Stream.value([])),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EditUnitScreen(row: row, allRows: [row]))),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return row.clientId;
  }

  TextField placaField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first);

  Future<Capture> saveAndRead(WidgetTester tester, String id) async {
    // A focused field's overlay can sit over the button: drop focus first.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    // The save hits the real (in-memory) DB: let it run, then let the pop settle.
    for (var i = 0;
        i < 20 && find.byType(EditUnitScreen).evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
    }
    expect(find.byType(EditUnitScreen), findsNothing); // saved and popped
    return (await tester.runAsync(() => repo.captureOf(id)))!;
  }

  testWidgets(
      'a linked capture with a placa opens OFF; turning it on clears, '
      'locks and saves placa null + the link', (tester) async {
    final id = await open(tester, placa: 'CALLE 20A # 3-03', npn: '4155');
    if (id == null) return markTestSkipped('native sqlite3 not available');

    expect(find.text(_solo), findsOneWidget);
    expect(placaField(tester).enabled, isTrue);

    await tester.tap(find.text(_solo));
    await tester.pump();
    expect(find.text(_on), findsOneWidget);
    expect(placaField(tester).enabled, isFalse);
    expect(placaField(tester).controller!.text, isEmpty);
    expect(find.text('Sin placa a la vista'), findsOneWidget); // the label

    final saved = await saveAndRead(tester, id);
    expect(saved.placa, isNull);
    expect(saved.npn, '4155');
  });

  testWidgets(
      'a "sin placa" capture opens ON; turning it off unlocks EMPTY '
      'and a typed placa is saved with the link', (tester) async {
    final id = await open(tester, npn: '4155');
    if (id == null) return markTestSkipped('native sqlite3 not available');

    expect(find.text(_on), findsOneWidget);
    expect(placaField(tester).enabled, isFalse);

    await tester.tap(find.text(_on));
    await tester.pump();
    expect(placaField(tester).enabled, isTrue);
    expect(placaField(tester).controller!.text, isEmpty);

    await tester.enterText(find.byType(TextField).first, 'CALLE 20A # 3-11');
    final saved = await saveAndRead(tester, id);
    expect(saved.placa, 'CALLE 20A # 3-11');
    expect(saved.npn, '4155');
  });

  testWidgets('removing the link turns the mode off and unlocks the field',
      (tester) async {
    final id = await open(tester, npn: '4155');
    if (id == null) return markTestSkipped('native sqlite3 not available');

    await tester.tap(find.byTooltip('Quitar enlace'));
    await tester.pump();
    expect(find.text(_on), findsNothing);
    expect(find.text(_solo), findsNothing);
    expect(placaField(tester).enabled, isTrue);
  });

  testWidgets('switching to "Sin construir" with the mode on drops the link',
      (tester) async {
    final id = await open(tester, npn: '4155');
    if (id == null) return markTestSkipped('native sqlite3 not available');

    await tester.tap(find.text('Sin construir'));
    await tester.pump();
    expect(find.text(_on), findsNothing);
    expect(placaField(tester).enabled, isTrue);

    final saved = await saveAndRead(tester, id);
    expect(saved.npn, isNull);
    expect(saved.esLote, isTrue);
  });

  testWidgets('an unlinked capture offers no switch', (tester) async {
    final id = await open(tester, placa: 'CALLE 20A # 3-03');
    if (id == null) return markTestSkipped('native sqlite3 not available');

    expect(find.text(_solo), findsNothing);
    expect(placaField(tester).enabled, isTrue);
  });
}

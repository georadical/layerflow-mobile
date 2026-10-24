import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/address/tipo_acceso.dart';
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
    String? direccionNorm,
    String? manzana,
    bool esLote = false,
    int? tenantId,
    List<R1DirectoryCompanion> r1 = const [],
    List<String> otherNpns = const [],
  }) async {
    final maybe = await tester.runAsync(_tryMemoryDb);
    if (maybe == null) return null;
    db = maybe;
    addTearDown(() => tester.runAsync(db.close));
    repo = CaptureRepository(db);
    final row = (await tester.runAsync(() async {
      if (tenantId != null && r1.isNotEmpty) {
        await db.replaceR1Slice(tenantId, r1);
      }
      final id = await repo.appendCapture(
          routeId: 'r1',
          placa: placa,
          npn: npn,
          direccionNorm: direccionNorm,
          manzanaCatastral: manzana,
          esLote: esLote);
      return repo.captureOf(id);
    }))!;
    // Other units of the route (the editor's allRows), e.g. a duplicate link.
    final others = <Capture>[];
    for (final n in otherNpns) {
      final other = await tester.runAsync(() async {
        final id = await repo.appendCapture(
            routeId: 'r1', placa: 'Y', npn: n, manzanaCatastral: manzana);
        return repo.captureOf(id);
      });
      others.add(other!);
    }
    // Tall enough that the editor's lazy ListView builds Guardar unscrolled.
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        activeTenantIdProvider.overrideWithValue(tenantId),
        queueOwnerProvider.overrideWithValue(null),
        routeStopsProvider('r1').overrideWith((ref) => Stream.value([])),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    EditUnitScreen(row: row, allRows: [row, ...others]))),
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

  Future<void> pickTipo(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

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

    // Spec 20: a built corner (sin placa a la vista) needs its access type.
    await pickTipo(tester, 'Puerta a la calle');
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

  group('placa-level (multi-unit) link — npn null + direccion_norm', () {
    const mz = '41551010100000005';
    const edificio = 'CALLE 13 # 3-20';

    testWidgets(
        'a "sin placa" placa-level capture opens ON, named, and saves '
        'placa null + direccion_norm', (tester) async {
      final id = await open(tester, direccionNorm: edificio, manzana: mz);
      if (id == null) return markTestSkipped('native sqlite3 not available');

      expect(find.text('Enlazada a: $edificio'), findsOneWidget);
      expect(find.text(_on), findsOneWidget);
      expect(placaField(tester).enabled, isFalse);

      // Spec 20: a built corner (sin placa a la vista) needs its access type.
      await pickTipo(tester, 'Puerta a la calle');
      final saved = await saveAndRead(tester, id);
      expect(saved.placa, isNull);
      expect(saved.npn, isNull);
      expect(saved.direccionNorm, edificio);
    });

    testWidgets('turning it off keeps the placa-level link with a typed placa',
        (tester) async {
      final id = await open(tester, direccionNorm: edificio, manzana: mz);
      if (id == null) return markTestSkipped('native sqlite3 not available');

      await tester.tap(find.text(_on));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, edificio);
      final saved = await saveAndRead(tester, id);
      expect(saved.placa, edificio);
      expect(saved.direccionNorm, edificio);
      expect(saved.npn, isNull);
    });

    testWidgets('unlinking clears the placa-level link', (tester) async {
      final id = await open(tester, direccionNorm: edificio, manzana: mz);
      if (id == null) return markTestSkipped('native sqlite3 not available');

      await tester.tap(find.byTooltip('Quitar enlace'));
      await tester.pump();
      expect(find.text(_solo), findsNothing);
      final saved = await saveAndRead(tester, id);
      expect(saved.direccionNorm, isNull);
      expect(saved.npn, isNull);
    });

    testWidgets(
        'linking a multi-unit R1 placa in the editor stores its '
        'direccion_norm (npn null)', (tester) async {
      final id = await open(
        tester,
        placa: '',
        manzana: mz,
        tenantId: 1,
        r1: [
          R1DirectoryCompanion.insert(
            tenantId: 1,
            direccionNorm: edificio,
            manzana: const Value(mz),
            unidades: const Value(3),
            esConjunto: const Value(true),
            parseOk: const Value(true),
          ),
        ],
      );
      if (id == null) return markTestSkipped('native sqlite3 not available');
      // Let the directory count load (async, real DB).
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, edificio);
      for (var i = 0; i < 10 && find.text('R1').evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('R1'));
      await tester.pumpAndSettle();
      expect(find.text('Enlazada a: $edificio'), findsOneWidget);
      expect(find.text(_solo), findsOneWidget);

      await tester.tap(find.text(_solo));
      await tester.pump();
      // Spec 20: a built corner (sin placa a la vista) needs its access type.
      await pickTipo(tester, 'Puerta a la calle');
      final saved = await saveAndRead(tester, id);
      expect(saved.placa, isNull);
      expect(saved.npn, isNull);
      expect(saved.direccionNorm, edificio);
    });
  });

  group('access type on built corners (Spec 20, TA.4)', () {
    testWidgets(
        'AC7: an old "sin placa" capture without access type cannot be saved '
        'until one is picked', (tester) async {
      final id = await open(tester, npn: '4155');
      if (id == null) return markTestSkipped('native sqlite3 not available');

      expect(find.text(tipoAccesoLabelRequired), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.byType(EditUnitScreen), findsOneWidget); // not saved
      expect(find.text(tipoAccesoRequiredError), findsOneWidget);

      await pickTipo(tester, 'Sin entrada visible');
      expect(find.text(tipoAccesoRequiredError), findsNothing);
      final saved = await saveAndRead(tester, id);
      expect(saved.tipoAcceso, 'sin_entrada_visible'); // AC5
    });

    testWidgets('a normal placa stays optional and saves without it',
        (tester) async {
      final id = await open(tester, placa: 'CALLE 20A # 3-03');
      if (id == null) return markTestSkipped('native sqlite3 not available');

      expect(find.text(tipoAccesoLabelOptional), findsOneWidget);
      final saved = await saveAndRead(tester, id);
      expect(saved.tipoAcceso, isNull);
    });

    testWidgets('AC8: the editor shows the same four options', (tester) async {
      final id = await open(tester, placa: 'CALLE 20A # 3-03');
      if (id == null) return markTestSkipped('native sqlite3 not available');

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      for (final label in tipoAccesoOptions.values) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });
  });

  group('"¿Te falta CON?" in the editor (BR-C4e, LX.8)', () {
    const sinCon = 'CALLE 13 CARRERA 3';

    testWidgets('AC-C10: Guardar asks; [Corregir] keeps the editor open',
        (tester) async {
      final id = await open(tester, placa: sinCon);
      if (id == null) return markTestSkipped('native sqlite3 not available');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('¿Te falta CON?'), findsOneWidget);

      await tester.tap(find.text('Corregir'));
      await tester.pumpAndSettle();
      expect(find.byType(EditUnitScreen), findsOneWidget); // not saved
    });

    testWidgets('[Guardar igual] saves as typed', (tester) async {
      final id = await open(tester, placa: sinCon);
      if (id == null) return markTestSkipped('native sqlite3 not available');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar igual'));
      for (var i = 0;
          i < 20 && find.byType(EditUnitScreen).evaluate().isNotEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pumpAndSettle();
      }
      expect(find.byType(EditUnitScreen), findsNothing);
      final row = await tester.runAsync(() => repo.captureOf(id));
      expect(row!.placa, sinCon);
    });

    testWidgets('AC-C8: a capture linked to R1 is never asked', (tester) async {
      final id = await open(tester, placa: sinCon, npn: '4155');
      if (id == null) return markTestSkipped('native sqlite3 not available');

      final saved = await saveAndRead(tester, id);
      expect(find.text('¿Te falta CON?'), findsNothing);
      expect(saved.placa, sinCon);
    });
  });

  group('duplicate R1 link in the editor (DUP.4)', () {
    const mz = '41551010100000005';
    final r1 = [
      R1DirectoryCompanion.insert(
        tenantId: 1,
        direccionNorm: 'CALLE 20A # 3-03',
        npn: const Value('n303'),
        manzana: const Value(mz),
        parseOk: const Value(true),
      ),
    ];

    Future<void> linkTyped(WidgetTester tester) async {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'CALLE 20A # 3-03');
      for (var i = 0; i < 10 && find.text('R1').evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('R1'));
      await tester.pumpAndSettle();
    }

    testWidgets('AC-D5: linking an R1 row already linked elsewhere warns',
        (tester) async {
      final id = await open(tester,
          placa: '', manzana: mz, tenantId: 1, r1: r1, otherNpns: ['n303']);
      if (id == null) return markTestSkipped('native sqlite3 not available');

      await linkTyped(tester);
      expect(find.textContaining('Esa placa de R1 ya está enlazada'),
          findsOneWidget);

      // Unlinking clears the warning.
      await tester.tap(find.byTooltip('Quitar enlace'));
      await tester.pump();
      expect(find.textContaining('ya está enlazada'), findsNothing);
    });

    testWidgets('no warning when the row is linked nowhere else',
        (tester) async {
      final id =
          await open(tester, placa: '', manzana: mz, tenantId: 1, r1: r1);
      if (id == null) return markTestSkipped('native sqlite3 not available');

      await linkTyped(tester);
      expect(find.text('Enlazada a: CALLE 20A # 3-03'), findsOneWidget);
      expect(find.textContaining('ya está enlazada'), findsNothing);
    });
  });
}

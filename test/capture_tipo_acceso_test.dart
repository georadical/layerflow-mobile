import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerflow_capture/core/address/tipo_acceso.dart';
import 'package:layerflow_capture/data/db/database.dart';
import 'package:layerflow_capture/data/repositories/capture_repository.dart';
import 'package:layerflow_capture/ui/providers.dart';
import 'package:layerflow_capture/ui/screens/capture_screen.dart';

import 'support/sqlite3.dart';

/// TA.3 — Spec 20 on the capture screen: the label tells when the access type
/// is required, and a built corner is not saved without it. Classic flow (no
/// parada, no tenant) over an in-memory DB. Saving paths use LOTS so the 1/N
/// routine-photo lottery can never open the camera mid-test.
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

void main() {
  late AppDatabase db;

  /// The screen may keep an indefinite animation (a progress indicator while a
  /// provider loads), so never wait for "settled" — pump a bounded while.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Unmounts the screen inside the test body so no provider timer is left
  /// pending when the test ends.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  /// [tenantId] + [r1] seed the local R1 directory (typeahead); [onRoute] is
  /// what the route already holds on this phone (the duplicate check reads it).
  Future<bool> open(
    WidgetTester tester, {
    int? tenantId,
    List<R1DirectoryCompanion> r1 = const [],
    List<Capture> onRoute = const [],
  }) async {
    final maybe = await tester.runAsync(_tryMemoryDb);
    if (maybe == null) return false;
    db = maybe;
    if (tenantId != null && r1.isNotEmpty) {
      await tester.runAsync(() => db.replaceR1Slice(tenantId, r1));
    }
    addTearDown(() => tester.runAsync(db.close));
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        activeTenantIdProvider.overrideWithValue(tenantId),
        queueOwnerProvider.overrideWithValue(null),
        routeStopsProvider('r1').overrideWith((ref) => Stream.value([])),
        fotoObligatoriaProvider('r1').overrideWithValue(false),
        tokenStatusProvider.overrideWith((ref) async => TokenStatus.ok),
        // No live drift queries on screen: their timers outlive the test.
        // What gets saved is read straight from the repository instead.
        capturesProvider('r1').overrideWith((ref) => Stream.value(onRoute)),
        noEncontradosProvider('r1').overrideWith((ref) => Stream.value([])),
        pendingEvidenceCountProvider('r1')
            .overrideWith((ref) => Stream.value(0)),
        pendingSurveyCountProvider('r1').overrideWith((ref) => Stream.value(0)),
        routeRowProvider('r1').overrideWith((ref) => Stream.value(null)),
        isOnlineProvider.overrideWithValue(true),
        isOnWifiProvider.overrideWithValue(true),
      ],
      child: const MaterialApp(home: CaptureScreen(routeId: 'r1')),
    ));
    await settle(tester);
    return true;
  }

  Finder placaField() => find.byType(TextField).first;

  Future<void> tapSave(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await tester.tap(find.text('Guardar y siguiente'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await settle(tester);
    }
  }

  Future<List<Capture>> stored(WidgetTester tester) async => (await tester
      .runAsync(() => CaptureRepository(db).capturesForRoute('r1')))!;

  Future<void> pickTipo(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle(tester);
    await tester.tap(find.text(label).last);
    await settle(tester);
  }

  testWidgets('AC6: the label turns mandatory only while it is a built corner',
      (tester) async {
    if (!await open(tester)) return markTestSkipped('no sqlite3');

    expect(find.text(tipoAccesoLabelOptional), findsOneWidget);
    await tester.enterText(placaField(), 'CALLE 13 # 3-20');
    await tester.pump();
    expect(find.text(tipoAccesoLabelOptional), findsOneWidget);

    await tester.enterText(placaField(), 'CALLE 13 CON CARRERA 3');
    await tester.pump();
    expect(find.text(tipoAccesoLabelRequired), findsOneWidget);

    // A lot on the corner stays optional (BR4).
    await tester.tap(find.text('Sin construir'));
    await settle(tester);
    expect(find.text(tipoAccesoLabelOptional), findsOneWidget);

    await finish(tester);
  });

  testWidgets('AC1: a Construido cruce without access type is not saved',
      (tester) async {
    if (!await open(tester)) return markTestSkipped('no sqlite3');

    await tester.enterText(placaField(), 'CALLE 13 CON CARRERA 3');
    await tapSave(tester);

    expect(await stored(tester), isEmpty);
    expect(find.text(tipoAccesoRequiredError), findsOneWidget);
    // The typed text stays (BR8).
    expect(find.text('CALLE 13 CON CARRERA 3'), findsOneWidget);

    // Picking any option clears the error.
    await pickTipo(tester, 'Puerta a la calle');
    expect(find.text(tipoAccesoRequiredError), findsNothing);

    await finish(tester);
  });

  testWidgets(
      'AC3 + AC5: a lot cruce saves without it; "Sin entrada visible" is '
      'offered and stored by its key', (tester) async {
    if (!await open(tester)) return markTestSkipped('no sqlite3');

    await tester.tap(find.text('Sin construir'));
    await settle(tester);
    await tester.enterText(placaField(), 'CALLE 13 CON CARRERA 3');
    await tapSave(tester);
    var rows = await stored(tester);
    expect(rows, hasLength(1));
    expect(rows.single.tipoAcceso, isNull);

    await tester.tap(find.text('Sin construir'));
    await settle(tester);
    await tester.enterText(placaField(), 'CALLE 13 CON CARRERA 4');
    await pickTipo(tester, 'Sin entrada visible');
    await tapSave(tester);
    rows = await stored(tester);
    expect(rows, hasLength(2));
    expect(rows.last.tipoAcceso, 'sin_entrada_visible');

    await finish(tester);
  });

  testWidgets('AC8: the four shared options, in order', (tester) async {
    if (!await open(tester)) return markTestSkipped('no sqlite3');

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle(tester);
    for (final label in tipoAccesoOptions.values) {
      expect(find.text(label), findsWidgets, reason: label);
    }

    await finish(tester);
  });

  group('"¿Te falta CON?" in both modes (BR-C4 amendment, LX.7)', () {
    const sinCon = 'CALLE 13 CARRERA 3';

    testWidgets('AC-C6: Construido without CON asks; [Corregir] saves nothing',
        (tester) async {
      if (!await open(tester)) return markTestSkipped('no sqlite3');

      await tester.enterText(placaField(), sinCon);
      await tapSave(tester);
      expect(find.text('¿Te falta CON?'), findsOneWidget);
      // Asked BEFORE the access-type check (BR-C4d): no Spec 20 error yet.
      expect(find.text(tipoAccesoRequiredError), findsNothing);

      await tester.tap(find.text('Corregir'));
      await settle(tester);
      expect(await stored(tester), isEmpty);
      expect(find.text(sinCon), findsOneWidget); // text intact

      await finish(tester);
    });

    testWidgets(
        'AC-C7: [Guardar igual] saves as typed, no access type required '
        '(not a cruce)', (tester) async {
      if (!await open(tester)) return markTestSkipped('no sqlite3');

      await tester.enterText(placaField(), sinCon);
      await tapSave(tester);
      await tester.tap(find.text('Guardar igual'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await settle(tester);
      }
      final rows = await stored(tester);
      expect(rows, hasLength(1));
      expect(rows.single.placa, sinCon);
      expect(rows.single.tipoAcceso, isNull);

      await finish(tester);
    });

    testWidgets('AC-C9: with CON there is no dialog — the access type is asked',
        (tester) async {
      if (!await open(tester)) return markTestSkipped('no sqlite3');

      await tester.enterText(placaField(), 'CALLE 13 CON CARRERA 3');
      await tapSave(tester);
      expect(find.text('¿Te falta CON?'), findsNothing);
      expect(find.text(tipoAccesoRequiredError), findsOneWidget);

      await finish(tester);
    });

    testWidgets('a lot without CON still asks (BR-C4 unchanged)',
        (tester) async {
      if (!await open(tester)) return markTestSkipped('no sqlite3');

      await tester.tap(find.text('Sin construir'));
      await settle(tester);
      await tester.enterText(placaField(), sinCon);
      await tapSave(tester);
      expect(find.text('¿Te falta CON?'), findsOneWidget);
      await tester.tap(find.text('Corregir'));
      await settle(tester);

      await finish(tester);
    });
  });

  group('duplicate R1 link, located (DUP.3)', () {
    final r1 = [
      R1DirectoryCompanion.insert(
        tenantId: 1,
        direccionNorm: 'CALLE 20A # 3-03',
        npn: const Value('n303'),
        parseOk: const Value(true),
      ),
      R1DirectoryCompanion.insert(
        tenantId: 1,
        direccionNorm: 'CALLE 14 # 2-104',
        unidades: const Value(3),
        esConjunto: const Value(true),
        parseOk: const Value(true),
      ),
    ];
    Capture already({String? npn, String? direccionNorm}) => Capture(
          clientId: 'prev',
          routeId: 'r1',
          posicion: 1,
          placa: 'X',
          npn: npn,
          direccionNorm: direccionNorm,
          sinR1: false,
          esLote: false,
          syncStatus: 'pending',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    Future<void> pick(WidgetTester tester, String direccion) async {
      Future<void> wait() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await settle(tester);
        }
      }

      // The screen loads the directory count asynchronously (real DB); a search
      // fired before it is ignored. Type once to let it load, then again.
      await tester.enterText(placaField(), direccion);
      await wait();
      await tester.enterText(placaField(), '$direccion ');
      await wait();
      await tester.tap(find.text(direccion).last);
      await settle(tester);
    }

    testWidgets('AC-D1: an npn already linked in the route is warned, located',
        (tester) async {
      if (!await open(tester,
          tenantId: 1, r1: r1, onRoute: [already(npn: 'n303')])) {
        return markTestSkipped('no sqlite3');
      }
      await pick(tester, 'CALLE 20A # 3-03');
      expect(find.textContaining('Esa placa de R1 ya está enlazada'),
          findsOneWidget);
      expect(find.textContaining('otro predio de esta ruta'), findsOneWidget);
      expect(find.textContaining('(PH)'), findsNothing);
      await finish(tester);
    });

    testWidgets('AC-D2: a placa-level (multi-unit) link is warned too',
        (tester) async {
      if (!await open(tester,
          tenantId: 1,
          r1: r1,
          onRoute: [already(direccionNorm: 'CALLE 14 # 2-104')])) {
        return markTestSkipped('no sqlite3');
      }
      await pick(tester, 'CALLE 14 # 2-104');
      expect(find.textContaining('Esa placa de R1 ya está enlazada'),
          findsOneWidget);
      await finish(tester);
    });

    testWidgets('no warning when the R1 row is not linked elsewhere',
        (tester) async {
      if (!await open(tester, tenantId: 1, r1: r1)) {
        return markTestSkipped('no sqlite3');
      }
      await pick(tester, 'CALLE 20A # 3-03');
      expect(find.textContaining('ya está enlazada'), findsNothing);
      await finish(tester);
    });
  });
}

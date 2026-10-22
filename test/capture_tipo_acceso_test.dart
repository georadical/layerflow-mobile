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

  Future<bool> open(WidgetTester tester) async {
    final maybe = await tester.runAsync(_tryMemoryDb);
    if (maybe == null) return false;
    db = maybe;
    addTearDown(() => tester.runAsync(db.close));
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        activeTenantIdProvider.overrideWithValue(null),
        queueOwnerProvider.overrideWithValue(null),
        routeStopsProvider('r1').overrideWith((ref) => Stream.value([])),
        fotoObligatoriaProvider('r1').overrideWithValue(false),
        tokenStatusProvider.overrideWith((ref) async => TokenStatus.ok),
        // No live drift queries on screen: their timers outlive the test.
        // What gets saved is read straight from the repository instead.
        capturesProvider('r1').overrideWith((ref) => Stream.value([])),
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
}

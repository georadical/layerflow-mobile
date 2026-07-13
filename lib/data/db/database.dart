import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/config/app_config.dart';

part 'database.g.dart';

/// Rutas abiertas en el dispositivo. Guarda el contexto mínimo para reanudar.
class Routes extends Table {
  /// UUID de la ruta (validada y "congelada" en oficina).
  TextColumn get routeId => text()();

  /// Código de censo de la ruta (viene del frame del backend).
  TextColumn get codigo => text().nullable()();

  /// Última vez que se trajo el frame (GET) para reanudar.
  DateTimeColumn get lastFrameSyncAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {routeId};
}

/// Una captura = un domicilio. Cola local offline-first.
///
/// Invariantes (impuestas por el repositorio, no por la UI):
/// - `clientId` es la clave de idempotencia (UUID generado por la app).
/// - `orden` es monotónico, append-only por ruta (1, 2, 3…). NUNCA se reordena
///   ni se reasigna en el MVP.
/// - Sin coordenadas: no existe columna de lat/lon en ninguna parte.
/// - `loc` y `remoteId` los asigna el servidor (loc = orden × 5); se guardan al
///   sincronizar.
class Captures extends Table {
  /// UUID generado por la app. Clave de idempotencia con el backend.
  TextColumn get clientId => text()();

  TextColumn get routeId => text()();

  /// Contador de caminata (append-only).
  IntColumn get orden => integer()();

  /// Placa (dirección en la puerta). Opcional: puede quedar en blanco.
  TextColumn get placa => text().nullable()();

  /// Manzana catastral (del diseño de ruta). Opcional.
  TextColumn get manzanaCatastral => text().nullable()();

  /// Tipo de acceso (opcional): p. ej. puerta_calle / area_comun / otro.
  TextColumn get tipoAcceso => text().nullable()();

  /// Observación libre (opcional).
  TextColumn get observacion => text().nullable()();

  /// localización asignada por el servidor (orden × 5). Null hasta sincronizar.
  IntColumn get loc => integer().nullable()();

  /// id del census_code remoto. Null hasta sincronizar.
  TextColumn get remoteId => text().nullable()();

  /// pending | synced | error
  TextColumn get syncStatus =>
      text().withDefault(const Constant(AppConfig.syncPending))();

  /// Último error de sync (diagnóstico). Null si no hay.
  TextColumn get syncError => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {clientId};
}

@DriftDatabase(tables: [Routes, Captures])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: AppConfig.dbName));

  @override
  int get schemaVersion => 1;

  // ---- Rutas ----

  Future<void> upsertRoute(RoutesCompanion route) =>
      into(routes).insertOnConflictUpdate(route);

  Future<Route?> getRoute(String routeId) =>
      (select(routes)..where((r) => r.routeId.equals(routeId)))
          .getSingleOrNull();

  Future<List<Route>> allRoutes() =>
      (select(routes)..orderBy([(r) => OrderingTerm.desc(r.lastFrameSyncAt)]))
          .get();

  // ---- Capturas ----

  /// Siguiente `orden` append-only para la ruta: max(orden)+1, o 1 si vacía.
  Future<int> nextOrden(String routeId) async {
    final maxExpr = captures.orden.max();
    final query = selectOnly(captures)
      ..where(captures.routeId.equals(routeId))
      ..addColumns([maxExpr]);
    final row = await query.getSingle();
    final currentMax = row.read(maxExpr);
    return (currentMax ?? 0) + 1;
  }

  Stream<List<Capture>> watchCaptures(String routeId) {
    return (select(captures)
          ..where((c) => c.routeId.equals(routeId))
          ..orderBy([(c) => OrderingTerm.asc(c.orden)]))
        .watch();
  }

  Future<List<Capture>> capturesForRoute(String routeId) {
    return (select(captures)
          ..where((c) => c.routeId.equals(routeId))
          ..orderBy([(c) => OrderingTerm.asc(c.orden)]))
        .get();
  }

  Future<Capture?> getCapture(String clientId) =>
      (select(captures)..where((c) => c.clientId.equals(clientId)))
          .getSingleOrNull();

  Future<List<Capture>> pendingCaptures(String routeId) {
    return (select(captures)
          ..where((c) =>
              c.routeId.equals(routeId) &
              c.syncStatus.equals(AppConfig.syncSynced).not())
          ..orderBy([(c) => OrderingTerm.asc(c.orden)]))
        .get();
  }

  Future<void> insertCapture(CapturesCompanion capture) =>
      into(captures).insert(capture);

  Future<void> upsertCapture(CapturesCompanion capture) =>
      into(captures).insertOnConflictUpdate(capture);

  Future<bool> updateCaptureRow(String clientId, CapturesCompanion patch) {
    return (update(captures)..where((c) => c.clientId.equals(clientId)))
        .write(patch)
        .then((rows) => rows > 0);
  }
}

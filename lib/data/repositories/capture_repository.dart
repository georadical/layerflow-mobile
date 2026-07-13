import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../api/dtos.dart';
import '../db/database.dart';

/// Repositorio de capturas. Único dueño de las invariantes de dominio:
/// - genera `clientId` (UUID) y `orden` append-only;
/// - nunca reordena ni reasigna `orden`;
/// - las ediciones (placa/tipo/obs) marcan la fila como `pending` (re-envío
///   idempotente al backend).
class CaptureRepository {
  CaptureRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Stream<List<Capture>> watchCaptures(String routeId) =>
      _db.watchCaptures(routeId);

  Future<List<Capture>> capturesForRoute(String routeId) =>
      _db.capturesForRoute(routeId);

  Future<int> nextOrden(String routeId) => _db.nextOrden(routeId);

  Future<Capture?> lastCapture(String routeId) async {
    final rows = await _db.capturesForRoute(routeId);
    return rows.isEmpty ? null : rows.last;
  }

  /// Agrega una captura al final (append-only). Devuelve el `clientId` nuevo.
  ///
  /// NO recibe `orden`: lo calcula el repositorio como max(orden)+1 para impedir
  /// reordenamientos libres desde la UI.
  Future<String> appendCapture({
    required String routeId,
    String? placa,
    String? manzanaCatastral,
    String? tipoAcceso,
    String? observacion,
  }) async {
    final now = DateTime.now();
    final clientId = _uuid.v4();
    final orden = await _db.nextOrden(routeId);

    await _db.insertCapture(
      CapturesCompanion.insert(
        clientId: clientId,
        routeId: routeId,
        orden: orden,
        placa: Value(_nullIfBlank(placa)),
        manzanaCatastral: Value(_nullIfBlank(manzanaCatastral)),
        tipoAcceso: Value(_nullIfBlank(tipoAcceso)),
        observacion: Value(_nullIfBlank(observacion)),
        syncStatus: const Value(AppConfig.syncPending),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return clientId;
  }

  /// Edita los atributos de una captura existente. NO toca `orden` (append-only)
  /// y la re-marca `pending` para re-enviarla (el backend actualiza en sitio).
  Future<void> editCapture({
    required String clientId,
    String? placa,
    String? manzanaCatastral,
    String? tipoAcceso,
    String? observacion,
  }) async {
    await _db.updateCaptureRow(
      clientId,
      CapturesCompanion(
        placa: Value(_nullIfBlank(placa)),
        manzanaCatastral: Value(_nullIfBlank(manzanaCatastral)),
        tipoAcceso: Value(_nullIfBlank(tipoAcceso)),
        observacion: Value(_nullIfBlank(observacion)),
        syncStatus: const Value(AppConfig.syncPending),
        syncError: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<List<Capture>> pending(String routeId) => _db.pendingCaptures(routeId);

  Future<void> markSynced({
    required String clientId,
    int? loc,
    String? remoteId,
  }) async {
    await _db.updateCaptureRow(
      clientId,
      CapturesCompanion(
        loc: Value(loc),
        remoteId: Value(remoteId),
        syncStatus: const Value(AppConfig.syncSynced),
        syncError: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markError(String clientId, String error) async {
    await _db.updateCaptureRow(
      clientId,
      CapturesCompanion(
        syncStatus: const Value(AppConfig.syncError),
        syncError: Value(error),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Reanudar: fusiona el frame remoto con lo local.
  /// - Items del servidor que no existen localmente → insertar como `synced`.
  /// - Items locales `pending`/`error` → se preservan (no se pisan ediciones sin
  ///   enviar); el re-envío posterior es idempotente por clientId.
  /// - Items locales ya `synced` → se actualizan con placa/loc del servidor.
  Future<void> mergeFrame(RouteFrame frame) async {
    final now = DateTime.now();

    await _db.upsertRoute(
      RoutesCompanion(
        routeId: Value(frame.routeId),
        codigo: Value(frame.codigo),
        lastFrameSyncAt: Value(now),
      ),
    );

    for (final item in frame.items) {
      final existing = await _db.getCapture(item.clientId);
      if (existing == null) {
        await _db.insertCapture(
          CapturesCompanion.insert(
            clientId: item.clientId,
            routeId: frame.routeId,
            orden: item.orden,
            placa: Value(item.placa),
            manzanaCatastral: Value(item.manzanaCatastral),
            loc: Value(item.loc),
            syncStatus: const Value(AppConfig.syncSynced),
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else if (existing.syncStatus == AppConfig.syncSynced) {
        await _db.updateCaptureRow(
          item.clientId,
          CapturesCompanion(
            orden: Value(item.orden),
            placa: Value(item.placa),
            manzanaCatastral: Value(item.manzanaCatastral),
            loc: Value(item.loc),
            updatedAt: Value(now),
          ),
        );
      }
      // pending/error local: se preserva tal cual.
    }
  }

  static String? _nullIfBlank(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}

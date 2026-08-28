import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../api/dtos.dart';
import '../db/database.dart';

/// Capture repository. Sole owner of the domain invariants:
/// - generates `clientId` (UUID) and the append-only `orden`;
/// - never reorders or reassigns `orden`;
/// - edits (placa/tipo_acceso/observacion) mark the row as `pending`
///   (idempotent re-send to the backend).
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

  /// Appends a capture at the end (append-only). Returns the new `clientId`.
  ///
  /// It does NOT take `orden`: the repository computes it as max(orden)+1 to
  /// prevent arbitrary reordering from the UI.
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

  /// Edits the attributes of an existing capture. It does NOT touch `orden`
  /// (append-only) and re-marks it `pending` for re-sending (the backend
  /// updates in place).
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

  /// Resume: merges the remote frame with local data.
  /// - Server items that do not exist locally → insert as `synced`.
  /// - Local `pending`/`error` items → preserved (unsent edits are not
  ///   overwritten); the later re-send is idempotent by clientId.
  /// - Local items already `synced` → updated with the server's placa/loc.
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
      // local pending/error: preserved as is.
    }
  }

  static String? _nullIfBlank(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}

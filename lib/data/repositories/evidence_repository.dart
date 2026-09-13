import 'dart:io';

import 'package:drift/drift.dart';

import '../../core/address/address_normalizer.dart';
import '../../core/config/app_config.dart';
import '../db/database.dart';

/// The photo-evidence queue (Spec 7, T7.4).
///
/// Same doctrine as the capture queue: offline-first, nothing travels
/// alone (CL-R5 — uploads happen inside the Enviar gesture), no verdict
/// no change, and rows leave only after the server confirmed reception —
/// then the local file is purged too.
class EvidenceRepository {
  EvidenceRepository(this._db);

  final AppDatabase _db;

  /// CL-R3: which retention class this capture's photo gets. Divergence
  /// triggers, in the spec's order: (1) not-in-list, (2) selected-R1 ≠
  /// observed placa, (3) plate illegible/absent (blank placa), (4) no
  /// physical plate but an NPN was linked by context, (5) duplicate NPN in
  /// the route. Everything else is routine.
  static String classifySoporte({
    required bool notInList,
    required bool duplicateNpn,
    required String? typedPlaca,
    required String? linkedDireccionNorm,
  }) {
    if (notInList || duplicateNpn) return AppConfig.soporteDivergencia;
    final blank = typedPlaca == null || typedPlaca.trim().isEmpty;
    if (blank) return AppConfig.soporteDivergencia; // triggers 3 and 4
    if (linkedDireccionNorm != null) {
      final norm = normalizeAddress(typedPlaca).direccionNorm;
      if (norm != linkedDireccionNorm) {
        return AppConfig.soporteDivergencia; // trigger 2 (or context link)
      }
    }
    return AppConfig.soporteRutina;
  }

  /// Queues (or replaces) the unit's photo. Re-capturing replaces file and
  /// row — the upload is idempotent per unit anyway. The OLD file is
  /// removed best-effort so re-shots do not accumulate on disk.
  Future<void> enqueue({
    required String clientId,
    required String routeId,
    required String filePath,
    required String soporte,
    String? owner,
  }) async {
    final existing = await _db.getEvidence(clientId);
    if (existing != null && existing.filePath != filePath) {
      await _deleteFile(existing.filePath);
    }
    final now = DateTime.now();
    await _db.upsertEvidence(EvidenceCompanion(
      clientId: Value(clientId),
      routeId: Value(routeId),
      filePath: Value(filePath),
      soporte: Value(soporte),
      ownerEmail: Value(owner),
      syncStatus: const Value(AppConfig.syncPending),
      syncError: const Value(null),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
    ));
  }

  Future<List<EvidenceData>> pendingForRoute(String routeId, {String? owner}) =>
      _db.pendingEvidenceForRoute(routeId, owner: owner);

  /// Server confirmed reception (2xx): purge row AND local file — the
  /// device holds no photo the server already has.
  Future<void> confirmUploaded(EvidenceData row) async {
    await _db.deleteEvidence(row.clientId);
    await _deleteFile(row.filePath);
  }

  /// A server VERDICT on the photo's merits (413/415/400/404): recorded on
  /// the row; a re-shot replaces it. Transport failures never call this.
  Future<void> markError(String clientId, String error) =>
      _db.markEvidenceError(clientId, error);

  Future<void> _deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best-effort: an undeletable temp file must never break the queue.
    }
  }
}

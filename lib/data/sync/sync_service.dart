import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/dtos.dart';
import '../repositories/capture_repository.dart';

/// Result of a sync push (for the UI).
class SyncResult {
  const SyncResult({
    required this.attempted,
    required this.synced,
    required this.failed,
    this.message,
  });

  final int attempted;
  final int synced;
  final int failed;
  final String? message;

  bool get isOk => failed == 0;
  bool get isNoop => attempted == 0;
}

/// Orchestrates pull (frame to resume) and push (pending queue → backend).
class SyncService {
  SyncService(this._api, this._repo, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final CaptureRepository _repo;
  final Uuid _uuid;

  /// Fetches the route frame and merges it locally (resume).
  Future<RouteFrame> pullFrame(String routeId) async {
    final frame = await _api.getRouteFrame(routeId);
    await _repo.mergeFrame(frame);
    return frame;
  }

  /// Pushes the route's pending queue as an idempotent batch.
  /// It is not all-or-nothing: each item is marked according to its result.
  Future<SyncResult> pushPending(String routeId) async {
    final pending = await _repo.pending(routeId);
    if (pending.isEmpty) {
      return const SyncResult(attempted: 0, synced: 0, failed: 0);
    }

    final batch = PlacaBatchRequest(
      routeId: routeId,
      batchId: _uuid.v4(),
      items: [
        for (final c in pending)
          PlacaItemRequest(
            clientId: c.clientId,
            orden: c.orden,
            placa: c.placa,
            manzanaCatastral: c.manzanaCatastral,
            tipoAcceso: c.tipoAcceso,
            observacion: c.observacion,
          ),
      ],
    );

    try {
      final res = await _api.postPlacas(batch);
      final byId = {for (final r in res.items) r.clientId: r};

      var synced = 0;
      var failed = 0;
      for (final c in pending) {
        final r = byId[c.clientId];
        if (r != null && r.ok) {
          await _repo.markSynced(
            clientId: c.clientId,
            loc: r.loc,
            remoteId: r.id,
          );
          synced++;
        } else {
          await _repo.markError(
            c.clientId,
            r?.error ?? 'El servidor no confirmó este item.',
          );
          failed++;
        }
      }
      return SyncResult(
        attempted: pending.length,
        synced: synced,
        failed: failed,
        message: failed == 0
            ? 'Sincronizadas $synced capturas.'
            : '$synced ok, $failed con error.',
      );
    } on ApiException catch (e) {
      // Transport failure: the queue stays pending for a retry.
      for (final c in pending) {
        await _repo.markError(c.clientId, e.message);
      }
      return SyncResult(
        attempted: pending.length,
        synced: 0,
        failed: pending.length,
        message: e.message,
      );
    }
  }
}

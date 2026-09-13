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
  /// [owner] scopes the queue to the current person: a predecessor's parked
  /// rows never travel under someone else's token (CL4).
  Future<SyncResult> pushPending(String routeId, {String? owner}) async {
    final pending = await _repo.pending(routeId, owner: owner);
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
            posicion: c.posicion,
            placa: c.placa,
            manzanaCatastral: c.manzanaCatastral,
            tipoAcceso: c.tipoAcceso,
            observacion: c.observacion,
            // Full-replacement contract: every push carries the row's current
            // mark, or the backend clears it (Spec 2.1, BR3). The npn link
            // rides under the same rule (Spec 7).
            insAfter: c.insAfter,
            npn: c.npn,
          ),
      ],
    );

    // A transport or auth failure is deliberately not caught: nothing was
    // rejected on its merits, so no row is marked `error`. The batch stays
    // exactly as queued and the caller maps the status code. Catching here
    // would paint a whole route as refused by the server when the request
    // never got a verdict (Spec 3, A4/A5 and BR6).
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
        // Includes the case where the response simply omits the item: it is
        // treated as failed and stays queued, never silently marked synced.
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
          ? 'Enviadas $synced.'
          : '$synced enviadas, $failed con error.',
    );
  }
}

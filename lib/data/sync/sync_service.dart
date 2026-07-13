import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/dtos.dart';
import '../db/database.dart';
import '../repositories/capture_repository.dart';

/// Resultado de un push de sincronización (para la UI).
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

/// Orquesta pull (frame para reanudar) y push (cola pendiente → backend).
class SyncService {
  SyncService(this._api, this._repo, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final CaptureRepository _repo;
  final Uuid _uuid;

  /// Trae el frame de la ruta y lo fusiona localmente (reanudar).
  Future<RouteFrame> pullFrame(String routeId) async {
    final frame = await _api.getRouteFrame(routeId);
    await _repo.mergeFrame(frame);
    return frame;
  }

  /// Empuja la cola pendiente de la ruta en un lote idempotente.
  /// No es all-or-nothing: cada item se marca según su resultado.
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
      // Fallo de transporte: la cola queda pendiente para reintentar.
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

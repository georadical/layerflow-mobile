import 'package:drift/drift.dart';

import '../api/api_client.dart';
import '../db/database.dart';

/// Owns the paradas cache (Spec 10, PC.1b): fetches a route's stops, keeps
/// them in drift so face-by-face navigation and the sweep work OFFLINE with
/// the last-known state, and drives the optimistic-local sweep (Decision Q1).
///
/// The sweep gate itself is the backend's authority (multi-device); this cache
/// only reflects it and lets the walk advance offline until the mark syncs.
class ParadaRepository {
  ParadaRepository(this._db, this._api);

  final AppDatabase _db;
  final ApiClient _api;

  Stream<List<Parada>> watchStops(String routeId) => _db.watchStops(routeId);

  Future<List<Parada>> stopsForRoute(String routeId) =>
      _db.stopsForRoute(routeId);

  /// The workable parada: the lowest `face_sequence` not yet swept. Null when
  /// the route has no (unswept) paradas.
  Future<Parada?> currentParada(String routeId) async {
    final stops = await _db.stopsForRoute(routeId); // ordered by faceSequence
    for (final p in stops) {
      if (!p.swept) return p;
    }
    return null;
  }

  /// Pulls the route's paradas and merges them into the cache. A still-unsynced
  /// local sweep is PRESERVED (not downgraded by a stale server value), and the
  /// locally-inferred direction is kept. Offline it throws — the caller keeps
  /// the cached stops (navigation never blocks).
  Future<void> refreshStops(String routeId) async {
    final remote = await _api.getRouteStops(routeId);
    final existing = {
      for (final p in await _db.stopsForRoute(routeId)) p.stopId: p,
    };
    final now = DateTime.now();
    final rows = <ParadasCompanion>[
      for (final s in remote.items)
        () {
          final local = existing[s.stopId];
          final pendingSweep = local != null && !local.sweptSynced;
          return ParadasCompanion.insert(
            stopId: s.stopId,
            routeId: routeId,
            faceSequence: s.faceSequence,
            blockFaceId: Value(s.blockFaceId),
            // Decisions v2 §7/§8: the terna (null on a rural parada) is what
            // the app reads to pick a capture mode — never re-derived locally.
            tipoVia: Value(s.tipoVia),
            numVia: Value(s.numVia),
            numCruce: Value(s.numCruce),
            // address-profiles AP.1–AP.5: the terna's cardinal zone suffix.
            cardinal: Value(s.cardinal),
            cardinalPosicion: Value(s.cardinalPosicion),
            faceIndex: Value(s.faceIndex),
            manzana: Value(s.manzanaCatastral),
            orientation: Value(s.orientation),
            // Keep a pending local sweep; otherwise take the server's truth.
            swept: Value(pendingSweep ? true : s.swept),
            sweptSynced: Value(!pendingSweep),
            direction: Value(local?.direction),
            // A prior push rejection is unrelated to this refresh; preserve
            // it (PC.5) same as direction — only a fresh mark clears it.
            sweepError: Value(local?.sweepError),
            updatedAt: now,
          );
        }(),
    ];
    await _db.replaceRouteStops(routeId, rows);
  }

  /// Marks a face swept locally and optimistically (Decision Q1): the next
  /// parada unlocks at once; `sweptSynced=false` queues it for the push (PC.5).
  /// `reopen` (swept=false) is the correction path. Clears any previous
  /// rejection reason — this fresh attempt supersedes it.
  Future<void> markSwept(String stopId, {bool swept = true}) =>
      _db.updateParadaRow(
        stopId,
        ParadasCompanion(
          swept: Value(swept),
          sweptSynced: const Value(false),
          sweepError: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Stores the inferred sweep direction for a face (PC.3), so it does not
  /// re-flip at the face end.
  Future<void> setDirection(String stopId, String direction) =>
      _db.updateParadaRow(
        stopId,
        ParadasCompanion(
          direction: Value(direction),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Sweeps whose local mark has not reached the server yet (PC.5 pushes them).
  Future<List<Parada>> pendingSweeps(String routeId) =>
      _db.pendingSweeps(routeId);

  /// The push confirmed this sweep (PC.5) — including a redundant re-push of
  /// an already-swept parada, which the backend treats as success too
  /// (verified idempotent: the order gate only looks at EARLIER paradas,
  /// never the target's own state, so it cannot self-block).
  Future<void> markSweepSynced(String stopId) => _db.updateParadaRow(
        stopId,
        ParadasCompanion(
          sweptSynced: const Value(true),
          sweepError: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// The push was REJECTED on its merits (barrido_fuera_de_orden /
  /// foto_obligatoria_pendiente). `sweptSynced` stays false so the row keeps
  /// retrying on the next Enviar — it may well succeed once an earlier
  /// parada's sweep lands, or the missing photos sync.
  Future<void> markSweepError(String stopId, String error) =>
      _db.updateParadaRow(
        stopId,
        ParadasCompanion(
          sweepError: Value(error),
          updatedAt: Value(DateTime.now()),
        ),
      );
}

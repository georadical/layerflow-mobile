import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../api/api_client.dart';
import '../api/dtos.dart';
import '../api/sync_dtos.dart';
import '../db/database.dart' show Capture, Parada;
import '../repositories/capture_repository.dart';
import '../repositories/evidence_repository.dart';
import '../repositories/parada_repository.dart';
import '../repositories/survey_repository.dart';
import 'survey_operations.dart';

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

/// Result of the evidence leg of a send (CL-R5).
class EvidenceResult {
  const EvidenceResult({
    required this.uploaded,
    required this.held,
    required this.failed,
  });

  final int uploaded;

  /// Waiting rows: routine photos without WiFi, or photos whose unit has
  /// not synced yet. They stay queued, untouched.
  final int held;

  /// Server verdicts against the photo (413/415/400/404): recorded per
  /// row; a re-shot replaces.
  final int failed;
}

/// Result of the survey leg of a send (Spec 8, T8.5c, CL-E5).
class SurveyResult {
  const SurveyResult({
    required this.synced,
    required this.held,
    required this.failed,
  });

  final int synced;

  /// Surveys whose anchor has not synced yet (its census_code does not exist,
  /// so the visit would be rejected): kept, untouched, for a later send.
  final int held;

  /// Surveys the server refused on their merits (lock, no assignment, a bad
  /// op): recorded per survey; editing re-queues.
  final int failed;
}

/// Result of the sweep leg of a send (Spec 10, PC.5).
class SweepResult {
  const SweepResult({
    required this.synced,
    required this.held,
    required this.failed,
  });

  final int synced;

  /// Transport died mid-chain: no verdict reached, kept pending untouched.
  final int held;

  /// The server rejected the sweep on its merits (barrido_fuera_de_orden /
  /// foto_obligatoria_pendiente): recorded per parada (never blocks the
  /// walk, Decision 1); it keeps retrying on the next Enviar.
  final int failed;
}

enum _SweepOutcome { synced, failed, held }

/// The four legs of one Enviar (Spec 10, PC.6): placas, photos, sweeps,
/// surveys — returned together so the send bar can report the whole gesture.
class RouteSyncResult {
  const RouteSyncResult({
    required this.placas,
    required this.evidence,
    required this.sweep,
    this.survey,
  });

  final SyncResult placas;
  final EvidenceResult evidence;
  final SweepResult sweep;
  final SurveyResult? survey;
}

/// Orchestrates pull (frame to resume) and push (pending queue → backend).
class SyncService {
  SyncService(
    this._api,
    this._repo, {
    Uuid? uuid,
    EvidenceRepository? evidence,
    SurveyRepository? survey,
    ParadaRepository? parada,
  })  : _evidence = evidence,
        _survey = survey,
        _parada = parada,
        _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final CaptureRepository _repo;
  final EvidenceRepository? _evidence;
  final SurveyRepository? _survey;
  final ParadaRepository? _parada;
  final Uuid _uuid;

  /// CL-R5 — the evidence leg of the SAME Enviar gesture, chained after
  /// the placa push so the census_codes exist. Divergence photos ship on
  /// any network; routine photos only when [wifiAvailable]. A photo whose
  /// unit is still unsent is held (its upload would 404). A transport
  /// failure stops the chain with everything left pending — no verdict,
  /// no change, like the capture queue.
  Future<EvidenceResult> pushEvidence(
    String routeId, {
    String? owner,
    required bool wifiAvailable,
    Set<String>? onlyClientIds,
  }) async {
    final evidenceRepo = _evidence;
    if (evidenceRepo == null) {
      return const EvidenceResult(uploaded: 0, held: 0, failed: 0);
    }
    final rows = await evidenceRepo.pendingForRoute(routeId, owner: owner);
    var uploaded = 0, held = 0, failed = 0;

    for (final row in rows) {
      // PC.6 per-parada order: a caller staging one parada at a time pushes
      // only that parada's photos (before its sweep runs the foto gate).
      if (onlyClientIds != null && !onlyClientIds.contains(row.clientId)) {
        continue;
      }
      if (row.soporte == AppConfig.soporteRutina && !wifiAvailable) {
        held++;
        continue;
      }
      final unit = await _repo.captureOf(row.clientId);
      if (unit == null || unit.syncStatus != AppConfig.syncSynced) {
        held++; // the placa push has not landed; uploading would 404
        continue;
      }
      try {
        await _api.uploadEvidence(
          clientId: row.clientId,
          soporte: row.soporte,
          filePath: row.filePath,
          proposito: row.proposito,
        );
        await evidenceRepo.confirmUploaded(row);
        uploaded++;
      } on ApiException catch (e) {
        if (e.statusCode != null) {
          // A verdict on the photo's merits: record it; a re-shot replaces.
          await evidenceRepo.markError(row, e.message);
          failed++;
        } else {
          // Transport died mid-chain: everything else stays pending.
          held += 1;
          break;
        }
      }
    }
    return EvidenceResult(uploaded: uploaded, held: held, failed: failed);
  }

  /// CL-E5 — the survey leg of the SAME Enviar gesture, chained after the
  /// placa push so each anchor's census_code exists (the visit resolves the
  /// route via `census_code_id`). One /sync/push per survey, its ops ordered
  /// parents-before-children. A survey whose anchor is not synced yet is
  /// HELD; the backend deriving the route means `census_code_id` is all the
  /// visit needs ([fieldWorkerId] must equal the token's worker). A transport
  /// failure stops the chain, everything left pending — no verdict, no
  /// change, like the capture queue.
  Future<SurveyResult> pushSurveys(
    String routeId, {
    String? owner,
    required String fieldWorkerId,
  }) async {
    final surveyRepo = _survey;
    if (surveyRepo == null) {
      return const SurveyResult(synced: 0, held: 0, failed: 0);
    }
    final rows = await surveyRepo.pending(routeId, owner: owner);
    var synced = 0, held = 0, failed = 0;

    for (final row in rows) {
      final anchor = await _repo.captureOf(row.anchorClientId);
      if (anchor == null ||
          anchor.syncStatus != AppConfig.syncSynced ||
          anchor.remoteId == null) {
        held++; // the census_code does not exist yet; the visit would fail
        continue;
      }
      final ops = surveyRepo.operationsFor(
        row,
        SurveyContext(
          censusCodeId: anchor.remoteId!,
          fieldWorkerId: fieldWorkerId,
        ),
      );
      final req = SyncPushRequest(batchId: _uuid.v4(), operations: ops);
      try {
        final res = await _api.pushSync(req);
        if (res.isOk) {
          await surveyRepo.markSynced(row.anchorClientId);
          synced++;
        } else {
          final errored = res.operations.where((o) => !o.isOk).toList();
          final motivo = res.hasSurveyLock
              ? 'La oficina no habilitó la encuesta para esta ruta o '
                  'encuestador.'
              : (errored.isNotEmpty
                  ? (errored.first.motivo ?? 'El servidor rechazó la encuesta.')
                  : 'El servidor rechazó la encuesta.');
          await surveyRepo.markError(row.anchorClientId, motivo);
          failed++;
        }
      } on ApiException {
        // Transport died mid-chain: no verdict reached this survey, so it
        // stays pending and the rest wait too.
        held++;
        break;
      }
    }
    return SurveyResult(synced: synced, held: held, failed: failed);
  }

  /// Spec 10, PC.5 — the sweep leg of the SAME Enviar gesture, chained after
  /// the evidence leg so a genuinely-complete face has its best chance of
  /// passing the server's foto_obligatoria check on THIS attempt (the photos
  /// just landed). One POST .../swept per pending parada (Decision 1:
  /// optimistic-local, never blocks the walk).
  ///
  /// A merit rejection (barrido_fuera_de_orden / foto_obligatoria_pendiente)
  /// is recorded on the row and left pending — it keeps retrying on the next
  /// Enviar, same as a rejected capture/survey. Re-confirmed with the backend
  /// (2026-09-22): a redundant re-push of an already-swept parada — this
  /// device retrying a lost response, or a paired device having swept it
  /// first — is idempotent and answers 200, never a rejection, because the
  /// order gate only looks at EARLIER paradas, never the target's own state.
  /// A transport failure stops the chain, everything else left pending.
  Future<SweepResult> pushSweeps(String routeId) async {
    final paradaRepo = _parada;
    if (paradaRepo == null) {
      return const SweepResult(synced: 0, held: 0, failed: 0);
    }
    final rows = await paradaRepo.pendingSweeps(routeId);
    var synced = 0, held = 0, failed = 0;

    for (final p in rows) {
      final outcome = await _pushSweepRow(routeId, p);
      switch (outcome) {
        case _SweepOutcome.synced:
          synced++;
        case _SweepOutcome.failed:
          failed++;
        case _SweepOutcome.held:
          // Transport died mid-chain: no verdict reached, so it and the
          // rest wait for the next attempt.
          held++;
          return SweepResult(synced: synced, held: held, failed: failed);
      }
    }
    return SweepResult(synced: synced, held: held, failed: failed);
  }

  /// Pushes one parada's sweep, recording a merit rejection on the row (kept
  /// pending to retry) and telling transport-held apart so the caller can stop
  /// the chain. Shared by [pushSweeps] and the per-parada [pushRoute].
  Future<_SweepOutcome> _pushSweepRow(String routeId, Parada p) async {
    final paradaRepo = _parada!;
    try {
      await _api.markSwept(routeId, p.stopId, swept: p.swept);
      await paradaRepo.markSweepSynced(p.stopId);
      return _SweepOutcome.synced;
    } on ApiException catch (e) {
      if (e.codigo == AppConfig.codeBarridoFueraDeOrden ||
          e.codigo == AppConfig.codeFotoObligatoriaPendiente) {
        await paradaRepo.markSweepError(p.stopId, _sweepRejectionText(e));
        return _SweepOutcome.failed;
      }
      return _SweepOutcome.held;
    }
  }

  /// PC.6 — one Enviar, in WALK ORDER. For each parada by face_sequence:
  /// push its placas, then its photos, then (if pending) its sweep — before
  /// moving to the next parada. Then any unassigned captures (rural/classic,
  /// no stop_id), then surveys.
  ///
  /// Why per-parada and not "all placas then all sweeps": the backend gates a
  /// placa on parada N by requiring every earlier parada swept, and rejects a
  /// placa onto an already-swept parada (`parada_ya_barrida`). Pushing all
  /// placas first would reject later paradas' placas until a second Enviar, and
  /// could sweep a parada before its own late placas landed — bypassing its
  /// foto_obligatoria gate (found in the PC.6 E2E). Interleaving keeps every
  /// parada whole and in order, so the backend guard never fires in normal flow.
  ///
  /// A placa transport/auth failure propagates (as [pushPending] does) so the
  /// caller records the attempt; a sweep transport-held stops the chain, the
  /// rest staying pending for the next Enviar.
  Future<RouteSyncResult> pushRoute(
    String routeId, {
    String? owner,
    required bool wifiAvailable,
    String? fieldWorkerId,
    bool surveyUnlocked = false,
  }) async {
    final stops = _parada == null
        ? const <Parada>[]
        : await _parada.stopsForRoute(routeId);
    final pending = await _repo.pending(routeId, owner: owner);
    final byStop = <String?, List<Capture>>{};
    for (final c in pending) {
      (byStop[c.stopId] ??= []).add(c);
    }

    var pAtt = 0, pSyn = 0, pFail = 0;
    var eUp = 0, eHeld = 0, eFail = 0;
    var sSyn = 0, sHeld = 0, sFail = 0;

    Future<void> stagePlacas(List<Capture> group) async {
      if (group.isEmpty) return;
      final r = await _pushPlacas(routeId, group);
      pAtt += r.attempted;
      pSyn += r.synced;
      pFail += r.failed;
    }

    Future<void> stageEvidence(Set<String> ids) async {
      if (ids.isEmpty) return;
      final r = await pushEvidence(routeId,
          owner: owner, wifiAvailable: wifiAvailable, onlyClientIds: ids);
      eUp += r.uploaded;
      eHeld += r.held;
      eFail += r.failed;
    }

    var chainBroken = false;
    for (final stop in stops) {
      final group = byStop[stop.stopId] ?? const <Capture>[];
      await stagePlacas(group);
      await stageEvidence({for (final c in group) c.clientId});
      if (!stop.sweptSynced) {
        final outcome = await _pushSweepRow(routeId, stop);
        switch (outcome) {
          case _SweepOutcome.synced:
            sSyn++;
          case _SweepOutcome.failed:
            sFail++;
          case _SweepOutcome.held:
            // Transport died: stop here, the rest waits for the next Enviar
            // (never sweep a later parada before an earlier one lands).
            sHeld++;
            chainBroken = true;
        }
      }
      if (chainBroken) break;
    }

    // Unassigned captures (no parada: classic routes, or rural before the
    // parada model) ride after the ordered paradas — nothing gates them.
    if (!chainBroken) {
      final loose = byStop[null] ?? const <Capture>[];
      await stagePlacas(loose);
      await stageEvidence({for (final c in loose) c.clientId});
    }

    SurveyResult? survey;
    if (!chainBroken && surveyUnlocked && fieldWorkerId != null) {
      survey = await pushSurveys(routeId,
          owner: owner, fieldWorkerId: fieldWorkerId);
    }

    return RouteSyncResult(
      placas: SyncResult(
        attempted: pAtt,
        synced: pSyn,
        failed: pFail,
        message: pFail == 0
            ? 'Enviadas $pSyn.'
            : '$pSyn enviadas, $pFail con error.',
      ),
      evidence: EvidenceResult(uploaded: eUp, held: eHeld, failed: eFail),
      sweep: SweepResult(synced: sSyn, held: sHeld, failed: sFail),
      survey: survey,
    );
  }

  /// A worker-readable reason for a rejected sweep. foto_obligatoria_pendiente
  /// names the offending locs from `detail.localizaciones` so the worker knows
  /// exactly where to re-shoot; barrido_fuera_de_orden (or anything else) uses
  /// the server's own message.
  static String _sweepRejectionText(ApiException e) {
    if (e.codigo == AppConfig.codeFotoObligatoriaPendiente &&
        e.localizaciones.isNotEmpty) {
      final locs = e.localizaciones.join(', ');
      final plural = e.localizaciones.length > 1;
      return 'Faltan fotos en ${plural ? 'loc' : 'la loc'} $locs.';
    }
    return e.message.isNotEmpty ? e.message : 'El servidor rechazó el barrido.';
  }

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
    return _pushPlacas(routeId, pending);
  }

  /// Pushes a specific list of pending captures as one idempotent batch and
  /// marks each by its per-item result. The per-parada orchestrator
  /// ([pushRoute]) calls this with one parada's captures at a time so the walk
  /// order is preserved on the wire; [pushPending] calls it with the whole
  /// queue.
  Future<SyncResult> _pushPlacas(
    String routeId,
    List<Capture> pending,
  ) async {
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
            // Third field under the same rule: omit it on a re-push and
            // the server clears the finding (CL-R7).
            sinR1: c.sinR1,
            // Spec 10: the parada binding rides on every push, same rule.
            // stop_id is the correct one from Decisions v2 §6 (urban AND
            // rural); block_face_id keeps riding for compatibility.
            stopId: c.stopId,
            blockFaceId: c.blockFaceId,
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
          secuenciaParada: r.secuenciaParada,
          remoteId: r.id,
        );
        synced++;
      } else {
        // Includes the case where the response simply omits the item: it is
        // treated as failed and stays queued, never silently marked synced.
        await _repo.markError(c.clientId, _placaRejectionText(r));
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

  /// A worker-readable reason for a rejected placa. The PC.6 backend guard
  /// `parada_ya_barrida` gets an actionable line (the per-parada send order
  /// makes it a multi-device rarity, but if it lands the worker needs to know
  /// to reopen); everything else uses the server's own message.
  static String _placaRejectionText(PlacaItemResult? r) {
    if (r?.codigo == AppConfig.codeParadaYaBarrida) {
      return 'Esa parada ya se cerró en el servidor; reábrela para agregar '
          'esta dirección.';
    }
    return r?.error ?? 'El servidor no confirmó este item.';
  }
}

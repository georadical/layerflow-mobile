import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../api/api_client.dart';
import '../api/dtos.dart';
import '../api/sync_dtos.dart';
import '../repositories/capture_repository.dart';
import '../repositories/evidence_repository.dart';
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

/// Orchestrates pull (frame to resume) and push (pending queue → backend).
class SyncService {
  SyncService(
    this._api,
    this._repo, {
    Uuid? uuid,
    EvidenceRepository? evidence,
    SurveyRepository? survey,
  })  : _evidence = evidence,
        _survey = survey,
        _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final CaptureRepository _repo;
  final EvidenceRepository? _evidence;
  final SurveyRepository? _survey;
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
  }) async {
    final evidenceRepo = _evidence;
    if (evidenceRepo == null) {
      return const EvidenceResult(uploaded: 0, held: 0, failed: 0);
    }
    final rows = await evidenceRepo.pendingForRoute(routeId, owner: owner);
    var uploaded = 0, held = 0, failed = 0;

    for (final row in rows) {
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
            // Third field under the same rule: omit it on a re-push and
            // the server clears the finding (CL-R7).
            sinR1: c.sinR1,
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

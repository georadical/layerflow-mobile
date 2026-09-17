/// DTOs for the census sync push (Spec 8, specs/extended-survey-phpv.md
/// §"Sync contract for the capture app" — POST /sync/push).
///
/// This file is the PINNED envelope only: the request operations, their
/// ordering discipline and the per-op result parsing. The concrete `data`
/// payloads of visit / observation_set / media_asset live in the backend's
/// census-sync contract (not mirrored here yet), so the operation BUILDER
/// that fills them is T8.1b, once those shapes are confirmed. Nothing in
/// this file invents a `data` schema.
///
/// INVARIANT (as everywhere): zero coordinates.
library;

import '../../core/config/app_config.dart';

/// The entity a /sync/push operation targets. The enum ORDER is the batch
/// ordering the backend requires — parents strictly before children
/// (visit → visit_attempt → observation_set → field_response → media_asset)
/// — so [orderOperations] can rank by `index` and a wrong order becomes
/// impossible to send (CR3 chain discipline).
enum SyncEntidad {
  visit('visit'),
  visitAttempt('visit_attempt'),
  observationSet('observation_set'),
  fieldResponse('field_response'),
  mediaAsset('media_asset');

  const SyncEntidad(this.wire);

  final String wire;
}

/// A create or an update. `update` requires the row to already exist; a
/// `create` on an existing id is the SAFE per-op re-send → `duplicada`.
enum SyncOp {
  create('create'),
  update('update');

  const SyncOp(this.wire);

  final String wire;
}

/// One operation in the batch. [id] is the client-owned UUIDv7 that IS the
/// row's identity — assigned once and STABLE across retries, exactly like a
/// capture's client_id: re-sending the same id never duplicates (layer (b)
/// of the two-layer idempotency).
class SyncOperation {
  const SyncOperation({
    required this.entidad,
    required this.op,
    required this.id,
    required this.data,
  });

  final SyncEntidad entidad;
  final SyncOp op;
  final String id;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
        'entidad': entidad.wire,
        'op': op.wire,
        'id': id,
        'data': data,
      };
}

/// Stable sort of a batch into parents-before-children order, preserving the
/// caller's order within a rank (so declaration/walk order survives). Pure —
/// the request calls it, and it is testable on its own.
List<SyncOperation> orderOperations(List<SyncOperation> ops) {
  final indexed = [
    for (var i = 0; i < ops.length; i++) (i, ops[i]),
  ];
  indexed.sort((a, b) {
    final byRank = a.$2.entidad.index.compareTo(b.$2.entidad.index);
    return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Request body of POST /sync/push.
class SyncPushRequest {
  const SyncPushRequest({
    required this.batchId,
    this.deviceId,
    required this.operations,
  });

  /// App-generated batch id. Replaying it returns the STORED result without
  /// re-applying — layer (a) of the two-layer idempotency (safe whole-batch
  /// retry). Keep it stable across retries of the same send.
  final String batchId;

  final String? deviceId;
  final List<SyncOperation> operations;

  /// A copy with operations sorted parents-before-children. Serialise THIS,
  /// never the raw list, so the ordering contract cannot be violated.
  SyncPushRequest ordered() => SyncPushRequest(
        batchId: batchId,
        deviceId: deviceId,
        operations: orderOperations(operations),
      );

  Map<String, dynamic> toJson() => {
        'batch_id': batchId,
        if (deviceId != null) 'device_id': deviceId,
        'operations': operations.map((e) => e.toJson()).toList(),
      };
}

/// One per-op verdict from the response. The field NAMES here are pinned
/// (`resultado`, `motivo`, and CL-E8's `codigo`); the row `id` is echoed
/// back so the caller can match it to what it sent.
class SyncOpResult {
  const SyncOpResult({
    this.id,
    this.entidad,
    required this.resultado,
    this.motivo,
    this.codigo,
  });

  final String? id;
  final String? entidad;

  /// `aplicada | duplicada | conflicto | error`.
  final String resultado;
  final String? motivo;

  /// CL-E8: a stable machine code on error (e.g. `survey_no_autorizado`);
  /// null for other errors and for successes.
  final String? codigo;

  bool get isApplied => resultado == AppConfig.syncApplied;
  bool get isDuplicate => resultado == AppConfig.syncDuplicate;
  bool get isConflict => resultado == AppConfig.syncConflict;
  bool get isError => resultado == AppConfig.syncOpError;

  /// Applied OR duplicada: both mean the row is as intended on the server, so
  /// the caller marks it synced either way (idempotent re-send is success).
  bool get isOk => isApplied || isDuplicate;

  /// CL-E8: this op was refused because the worker/route may not survey.
  bool get isSurveyLocked => codigo == AppConfig.codeSurveyNoAutorizado;

  factory SyncOpResult.fromJson(Map<String, dynamic> json) => SyncOpResult(
        id: json['id']?.toString(),
        entidad: json['entidad']?.toString(),
        resultado: json['resultado']?.toString() ?? AppConfig.syncOpError,
        motivo: json['motivo']?.toString(),
        codigo: json['codigo']?.toString(),
      );
}

/// Response of POST /sync/push (pinned Q3, backend d2bb861). The per-op
/// verdicts ride the `operaciones` array; the named counters ride `resumen`
/// {total, aplicadas, duplicadas, conflictos, errores} — read, not derived.
/// The op array falls back to results/operations/items and the counters fall
/// back to deriving from the results, only so an older/partial shape never
/// crashes the parser.
class SyncPushResponse {
  const SyncPushResponse({
    required this.batchId,
    required this.operations,
    required this.total,
    required this.aplicadas,
    required this.duplicadas,
    required this.conflictos,
    required this.errores,
  });

  final String batchId;
  final List<SyncOpResult> operations;
  final int total;
  final int aplicadas;
  final int duplicadas;
  final int conflictos;
  final int errores;

  /// Nothing was refused on its merits.
  bool get isOk => conflictos == 0 && errores == 0;

  /// CL-E8: at least one op hit the survey lock — the app should surface the
  /// lock, not paint the batch as a generic failure. (The `codigo` that
  /// carries it lands with backend TJ.6; until then this is always false.)
  bool get hasSurveyLock => operations.any((o) => o.isSurveyLocked);

  factory SyncPushResponse.fromJson(Map<String, dynamic> json) {
    final raw = (json['operaciones'] ??
            json['results'] ??
            json['operations'] ??
            json['items']) as List<dynamic>? ??
        const [];
    final ops = raw
        .map((e) => SyncOpResult.fromJson(e as Map<String, dynamic>))
        .toList();
    final resumen = json['resumen'] as Map<String, dynamic>?;
    int counter(String key, bool Function(SyncOpResult) pred) =>
        (resumen?[key] as num?)?.toInt() ?? ops.where(pred).length;
    return SyncPushResponse(
      batchId: json['batch_id']?.toString() ?? '',
      operations: ops,
      total: (resumen?['total'] as num?)?.toInt() ?? ops.length,
      aplicadas: counter('aplicadas', (o) => o.isApplied),
      duplicadas: counter('duplicadas', (o) => o.isDuplicate),
      conflictos: counter('conflictos', (o) => o.isConflict),
      errores: counter('errores', (o) => o.isError),
    );
  }
}

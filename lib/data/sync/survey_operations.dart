/// Builds the ordered /sync/push operations for one surveyed predio
/// (Spec 8, T8.1b). Turns the local [SurveyStructure] (T8.3) into the
/// visit → observation_set → field_response chain, using the `data` shapes
/// pinned by the backend (d2bb861, Q2).
///
/// Pure: no network, no id generation inside. The stable row ids are passed
/// in — the visit and observation_set ids from the persisted survey (T8.5),
/// each field_response id from [fieldResponseId] — so the builder is fully
/// testable and idempotent (same inputs → same batch). See
/// [surveyFieldResponseId] for the recommended stable-id scheme.
///
/// Two contract facts shape it:
/// - **Q1=(B): the app always emits a `unidad`.** [SurveyStructure.generate]
///   never returns empty, so a unifamiliar predio still emits its 01/01
///   here; the backend decides 00/00-vs-expand at promotion.
/// - **The totalizador photo does NOT ride this batch (Q2).** It travels via
///   `POST /field/capture/evidence` with `proposito='totalizador'` (CL-E4,
///   T8.4), bound to the anchor's client_id — so no `media_asset` op is
///   produced here. The totalizador's 99/99 `unidad` row (ph/pv only) IS
///   emitted, as the model pins it.
library;

import 'package:uuid/uuid.dart';

import '../../core/survey/survey_pyramid.dart';
import '../api/sync_dtos.dart';

/// `entidad_objetivo` for a survey unit's field_responses. The four CL-E3
/// answers and ph/pv all ride this one entity (Q1=(B) gives them a single
/// uniform home); sub-entities (hogar/connection/…) are a future ticket.
const String entidadUnidad = 'unidad';

/// The `campo` names of a `unidad` field_response (pinned in the spec model).
const String campoPh = 'ph';
const String campoPv = 'pv';
const String campoAcceso = 'acceso_independiente';
const String campoTipoAcceso = 'tipo_acceso';
const String campoMedicion = 'medicion';
const String campoUso = 'uso';

/// Fixed namespace for deterministic survey ids (an arbitrary, permanent
/// constant — do not change it, or ids would shift under existing rows).
const String _surveyNamespace = 'a5f3e0c2-9d4b-4e7a-8c1f-2b6d9e0a7c31';

/// The recommended stable id for a survey field_response: a name-based (v5)
/// UUID over (observation_set, instancia, campo). Deterministic, so it is
/// "assigned once, stable across retries" without persisting a row per field,
/// and unique per the natural key the backend enforces.
String surveyFieldResponseId(
  String observationSetId,
  int instancia,
  String campo, {
  Uuid uuid = const Uuid(),
}) =>
    uuid.v5(_surveyNamespace, '$observationSetId/$instancia/$campo');

/// The per-predio context a survey push needs, from the captured anchor and
/// the session (Q2 `visit.data`). `assignment_id` is NOT sent: the backend
/// derives it at visit-create from (worker + census_code_id → route), since a
/// route only appears to an assigned worker (backend f1a0721).
class SurveyContext {
  const SurveyContext({
    required this.censusCodeId,
    required this.fieldWorkerId,
  });

  final String censusCodeId;

  /// Must equal the worker behind the token; the backend rejects a visit that
  /// does not belong to the pushing worker.
  final String fieldWorkerId;
}

/// Builds the operations for one surveyed predio, already in
/// parents-before-children order (visit, observation_set, then the
/// field_responses in walk order). All ops are `create`: a survey is
/// immutable from the app once sent, and a re-send of an unchanged row is a
/// safe `duplicada` — so the app never needs `update`.
///
/// [fieldResponseId] must return an id that is UNIQUE per
/// (observation_set, entidad, instancia, campo) and STABLE across retries.
List<SyncOperation> buildSurveyOperations({
  required String visitId,
  required String observationSetId,
  required SurveyContext context,
  required SurveyStructure structure,
  required String Function(int instancia, String campo) fieldResponseId,
}) {
  final ops = <SyncOperation>[
    SyncOperation(
      entidad: SyncEntidad.visit,
      op: SyncOp.create,
      id: visitId,
      data: {
        'census_code_id': context.censusCodeId,
        'field_worker_id': context.fieldWorkerId,
      },
    ),
    SyncOperation(
      entidad: SyncEntidad.observationSet,
      op: SyncOp.create,
      id: observationSetId,
      data: {'visit_id': visitId},
    ),
  ];

  for (final unit in structure.generate()) {
    void field(String campo, String valor) {
      ops.add(SyncOperation(
        entidad: SyncEntidad.fieldResponse,
        op: SyncOp.create,
        id: fieldResponseId(unit.instancia, campo),
        data: {
          'observation_set_id': observationSetId,
          'entidad_objetivo': entidadUnidad,
          'instancia': unit.instancia,
          'campo': campo,
          'valor': valor,
        },
      ));
    }

    // ph/pv are structural — always present. The 99/99 totalizador emits
    // only these (the model pins no answers for it).
    field(campoPh, unit.ph);
    field(campoPv, unit.pv);
    if (!unit.isTotalizador) {
      final a = unit.answers;
      // Only answered questions travel; an unanswered one simply has no row
      // yet (a resumable survey completes across sends, each new answer a new
      // create — CL-E6).
      if (a.acceso != null) field(campoAcceso, a.acceso!.wire);
      if (a.tipoAcceso != null) field(campoTipoAcceso, a.tipoAcceso!.wire);
      if (a.medicion != null) field(campoMedicion, a.medicion!.wire);
      if (a.uso != null) field(campoUso, a.uso!.wire);
    }
  }

  return ops;
}

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/survey/survey_pyramid.dart';
import '../api/sync_dtos.dart';
import '../db/database.dart';
import '../sync/survey_operations.dart';

/// The per-unit survey-state chip in the resume list (CL-E1).
enum SurveyEstado { sinEncuesta, aMedias, completa }

/// Owns the resumable survey state (Spec 8, T8.5). It serialises the
/// [SurveyStructure] into one row per anchor unit, assigns the stable
/// /sync/push identities ONCE, and derives the resume-list chip. A survey
/// lives in drift, never memory-only (CL-E6), and is bound to the person who
/// runs it (CL4).
class SurveyRepository {
  SurveyRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Stream<Survey?> watchSurvey(String anchorClientId) =>
      _db.watchSurvey(anchorClientId);

  Future<Survey?> getSurvey(String anchorClientId) =>
      _db.getSurvey(anchorClientId);

  /// The declared structure for an anchor, or null if none was ever saved.
  Future<SurveyStructure?> loadStructure(String anchorClientId) async {
    final row = await _db.getSurvey(anchorClientId);
    return row == null ? null : _decode(row);
  }

  /// Creates or updates the survey for an anchor. The visit and
  /// observation_set ids are assigned once on first save and PRESERVED on
  /// every later save, so re-sends stay idempotent (idempotency layer b).
  /// Any save re-queues the row as pending — it travels on the next Enviar
  /// (CL-E5), never on its own (manual-only doctrine).
  Future<void> saveSurvey({
    required String anchorClientId,
    required String routeId,
    required SurveyStructure structure,
    String? owner,
  }) async {
    final now = DateTime.now();
    final existing = await _db.getSurvey(anchorClientId);
    await _db.upsertSurvey(SurveysCompanion(
      anchorClientId: Value(anchorClientId),
      routeId: Value(routeId),
      ownerEmail: Value(owner),
      visitId: Value(existing?.visitId ?? _uuid.v4()),
      observationSetId: Value(existing?.observationSetId ?? _uuid.v4()),
      structureJson: Value(jsonEncode(structure.toJson())),
      syncStatus: const Value(AppConfig.syncPending),
      syncError: const Value(null),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
    ));
  }

  /// The resume-list chip for a survey row: no row → sin encuesta, all real
  /// units answered → completa, otherwise a medias.
  SurveyEstado estadoOf(Survey? row) {
    if (row == null) return SurveyEstado.sinEncuesta;
    return _decode(row).isComplete
        ? SurveyEstado.completa
        : SurveyEstado.aMedias;
  }

  Stream<List<Survey>> watchSurveysForRoute(String routeId, {String? owner}) =>
      _db.watchSurveysForRoute(routeId, owner: owner);

  Future<List<Survey>> pending(String routeId, {String? owner}) =>
      _db.pendingSurveys(routeId, owner: owner);

  Stream<int> watchPendingCount(String routeId, {String? owner}) =>
      _db.watchPendingSurveyCount(routeId, owner: owner);

  Future<void> markSynced(String anchorClientId) => _db.updateSurveyRow(
        anchorClientId,
        SurveysCompanion(
          syncStatus: const Value(AppConfig.syncSynced),
          syncError: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> markError(String anchorClientId, String error) =>
      _db.updateSurveyRow(
        anchorClientId,
        SurveysCompanion(
          syncStatus: const Value(AppConfig.syncError),
          syncError: Value(error),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deleteSurvey(String anchorClientId) =>
      _db.deleteSurvey(anchorClientId);

  /// The /sync/push operations for a stored survey — bridges the persisted
  /// stable ids to the T8.1 builder. [context] supplies the visit's
  /// assignment / census_code / field_worker (from the frame + session).
  List<SyncOperation> operationsFor(Survey row, SurveyContext context) =>
      buildSurveyOperations(
        visitId: row.visitId,
        observationSetId: row.observationSetId,
        context: context,
        structure: _decode(row),
        fieldResponseId: (instancia, campo) =>
            surveyFieldResponseId(row.observationSetId, instancia, campo),
      );

  SurveyStructure _decode(Survey row) => SurveyStructure.fromJson(
      jsonDecode(row.structureJson) as Map<String, dynamic>);
}

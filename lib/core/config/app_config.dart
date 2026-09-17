/// App configuration constants (no secrets).
///
/// The backend `baseUrl` and the `field_token` do NOT live here: they are
/// configured at runtime from the Settings screen and stored in
/// `SettingsStore` (SharedPreferences + secure storage).
library;

class AppConfig {
  const AppConfig._();

  /// Logical name of the local SQLite file.
  static const String dbName = 'layerflow_capture';

  /// Network timeouts.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// Paths of the capture API contract (LayerFlow backend).
  static const String postPlacasPath = '/field/capture/placas';
  static String routeFramePath(String routeId) =>
      '/field/capture/route/$routeId';

  /// Routes assigned to the authenticated field worker.
  static const String assignedRoutesPath = '/field/routes';

  /// Field login (Spec 5): credentials → one fresh token per active ESP.
  static const String loginPath = '/field/login';

  /// Silent renewal; the 7-day grace window exists only here.
  static const String refreshPath = '/field/token/refresh';

  /// R1 directory for the typeahead (Spec 7). Tenant-scoped by the token.
  static const String r1DirectoryPath = '/field/r1-directory';

  /// Placa photo evidence upload (Spec 7). Multipart; JPEG only, <=500KB.
  static const String evidencePath = '/field/capture/evidence';

  /// Retention class of a photo (CL-R3): divergence ships on any network,
  /// routine only under WiFi (CL-R5); the server keeps divergence forever.
  static const String soporteDivergencia = 'divergencia';
  static const String soporteRutina = 'rutina';

  /// Purpose of a photo (backend TJ.3). The placa evidence (Spec 7) and the
  /// totalizador evidence (Spec 8, CL-E4) coexist for one unit, keyed by
  /// (client_id, proposito); the totalizador forces soporte=divergencia.
  static const String propositoPlaca = 'placa';
  static const String propositoTotalizador = 'totalizador';

  /// CL-R3 v1.1: routine captures draw a photo audit 1 in N, decided AT
  /// SAVE (unpredictable — honesty becomes the dominant strategy). Rate
  /// fixed in-app for v1 by agreement (a backend config would be a
  /// contract change); promote to config with its own pin if retuning
  /// becomes frequent.
  static const int evidenceLotteryOneIn = 10;

  /// Server-side provenance value that carries a sin_r1 finding back in
  /// the frame (CL-R7) — the app reconstructs the flag from it on resume.
  static const String methodSinMatch = 'field_sin_match';

  /// Census sync (Spec 8) — the survey pass ships as ordered operations
  /// over visits/observation_sets/field_responses/media_assets. Distinct
  /// transport from the placa push; same manual-only Enviar doctrine.
  static const String syncPushPath = '/sync/push';
  static const String syncPullPath = '/sync/pull';

  /// Per-op verdicts of POST /sync/push (pinned). `aplicada` and `duplicada`
  /// both mean "the row is as intended on the server" (idempotent re-send).
  static const String syncApplied = 'aplicada';
  static const String syncDuplicate = 'duplicada';
  static const String syncConflict = 'conflicto';
  static const String syncOpError = 'error';

  /// CL-E8: the stable per-op code when the worker/route is not authorised
  /// to run the extended survey. The app gates the survey entry so this
  /// should be unreachable, but the client maps it defensively.
  static const String codeSurveyNoAutorizado = 'survey_no_autorizado';

  /// Route-state locks (Spec 9). The app REFLECTS these; the backend is the
  /// authority and enforces at the write.
  /// Placa pass: only an explicit 'cerrada' disables capture (fail-OPEN —
  /// absent means abierta, so routes predating the flag keep capturing).
  static const String placasAbierta = 'abierta';
  static const String placasCerrada = 'cerrada';
  /// Survey pass: fail-CLOSED — absent means bloqueada.
  static const String surveyBloqueada = 'bloqueada';
  static const String surveyAbierta = 'abierta';

  /// 409 code when a placa push races a route close (backend da98366).
  static const String codeRutaPlacasCerrada = 'ruta_placas_cerrada';

  /// Local sync states.
  static const String syncPending = 'pending';
  static const String syncSynced = 'synced';
  static const String syncError = 'error';

  /// Outcomes of a manual send attempt (Spec 4, BR7). Stored per route so the
  /// worker can tell "never tried" from "tried and failed" after the message
  /// is gone.
  static const String pushOk = 'ok';
  static const String pushPartial = 'partial';
  static const String pushNetwork = 'network';
  static const String pushAuth = 'auth';
  static const String pushHttp = 'http';
}

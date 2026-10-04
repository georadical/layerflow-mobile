/// DTOs for the capture contract (LayerFlow / FastAPI backend).
///
/// Contract (see specs/field-capture-api.md):
///   POST /field/capture/placas  -> batch upsert (idempotent by client_id)
///   GET  /field/capture/route/{route_id} -> frame used to resume
///
/// INVARIANT: ZERO coordinates. No DTO carries lat/lon.
library;

import '../../core/config/app_config.dart';

/// Capture item in the POST request.
class PlacaItemRequest {
  const PlacaItemRequest({
    required this.clientId,
    required this.posicion,
    this.placa,
    this.manzanaCatastral,
    this.tipoAcceso,
    this.observacion,
    this.insAfter,
    this.npn,
    this.sinR1,
    this.blockFaceId,
    this.stopId,
    this.esLote = false,
  });

  final String clientId;
  final int posicion;
  final String? placa;
  final String? manzanaCatastral;
  final String? tipoAcceso;
  final String? observacion;

  /// Parada binding (Decisions v2 §6) — the correct one from here on: it
  /// exists for both urban AND rural paradas. Same full-replacement rule as
  /// npn/ins_after; null means an unassisted (no-parada) route.
  final String? stopId;

  /// Parada binding, legacy/compatibility form (Spec 10 PC.1a): the face a
  /// rural parada does not have. Kept riding alongside [stopId].
  final String? blockFaceId;

  /// Pending relocation: the loc this unit goes after (0 = start of route).
  /// The contract is full-replacement, so omitting it clears the mark on the
  /// server — the caller must always pass the row's current value.
  final int? insAfter;

  /// NPN linked at the door (Spec 7). Same full-replacement trap as the
  /// mark: omitting it on a re-push clears the link, so every push carries
  /// the row's current value.
  final String? npn;

  /// CL-R7, TRI-STATE (backend 287cf2a): true asserts the finding (the
  /// worker tapped "No está en la lista"), false RETRACTS it, null omits
  /// the key and the server PRESERVES what it holds. Mutually exclusive
  /// with [npn].
  final bool? sinR1;

  /// es_lote (Spec 12, LT.4): the predio is a vacant lot ("Sin construir").
  /// Full-replacement (BR2): the backend reverts to false on omit, so the value
  /// is ALWAYS sent (true/false), re-carried from the frame like npn/ins_after.
  final bool esLote;

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'posicion': posicion,
        // placa is optional: null is sent when blank (the server allows it).
        'placa': placa,
        // Always sent (full-replacement): omitting it would clear the flag.
        'es_lote': esLote,
        if (manzanaCatastral != null) 'manzana_catastral': manzanaCatastral,
        if (tipoAcceso != null) 'tipo_acceso': tipoAcceso,
        if (observacion != null) 'observacion': observacion,
        // Omitted and explicit null mean the same to the server (clear), so
        // only a real mark is serialised.
        if (insAfter != null) 'ins_after': insAfter,
        if (npn != null) 'npn': npn,
        // Tri-state: the key travels only when there is something to say
        // (assert or retract). Sending it beside npn is a per-item error.
        if (sinR1 != null && npn == null) 'sin_r1': sinR1,
        if (stopId != null) 'stop_id': stopId,
        if (blockFaceId != null) 'block_face_id': blockFaceId,
      };
}

/// Request for POST /field/capture/placas.
class PlacaBatchRequest {
  const PlacaBatchRequest({
    required this.routeId,
    required this.batchId,
    required this.items,
  });

  final String routeId;
  final String batchId;
  final List<PlacaItemRequest> items;

  Map<String, dynamic> toJson() => {
        'route_id': routeId,
        'batch_id': batchId,
        'items': items.map((e) => e.toJson()).toList(),
      };
}

/// Per-item result in the POST response.
class PlacaItemResult {
  const PlacaItemResult({
    required this.clientId,
    required this.ok,
    this.id,
    this.loc,
    this.secuenciaParada,
    this.status,
    this.error,
    this.codigo,
  });

  final String clientId;
  final bool ok;
  final String? id;
  final int? loc;

  /// Spec 11: the predio's position WITHIN its parada, assigned by the backend
  /// (MAX + 1), restarting at 1 per parada. Present only on `ok:true` items;
  /// an `updated` item carries the SAME frozen value. Null when the backend has
  /// not assigned one (legacy / no stop_id). The app never sends it.
  final int? secuenciaParada;

  /// 'created' | 'updated' (when ok).
  final String? status;
  final String? error;

  /// Stable per-item machine code when refused (Spec 10, e.g.
  /// 'barrido_fuera_de_orden'); null otherwise.
  final String? codigo;

  factory PlacaItemResult.fromJson(Map<String, dynamic> json) {
    return PlacaItemResult(
      clientId: json['client_id'] as String,
      ok: json['ok'] as bool? ?? false,
      id: json['id']?.toString(),
      loc: (json['loc'] as num?)?.toInt(),
      secuenciaParada: (json['secuencia_parada'] as num?)?.toInt(),
      status: json['status'] as String?,
      error: json['error']?.toString(),
      codigo: json['codigo']?.toString(),
    );
  }
}

/// Response of POST /field/capture/placas.
class PlacaBatchResponse {
  const PlacaBatchResponse({
    required this.batchId,
    required this.total,
    required this.created,
    required this.updated,
    required this.errores,
    required this.items,
  });

  final String batchId;
  final int total;
  final int created;
  final int updated;
  final int errores;
  final List<PlacaItemResult> items;

  factory PlacaBatchResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>? ?? const [])
        .map((e) => PlacaItemResult.fromJson(e as Map<String, dynamic>))
        .toList();
    return PlacaBatchResponse(
      batchId: json['batch_id']?.toString() ?? '',
      total: (json['total'] as num?)?.toInt() ?? rawItems.length,
      created: (json['created'] as num?)?.toInt() ?? 0,
      updated: (json['updated'] as num?)?.toInt() ?? 0,
      errores: (json['errores'] as num?)?.toInt() ?? 0,
      items: rawItems,
    );
  }
}

/// One route assigned to the authenticated field worker.
///
/// From `GET /field/routes`. The backend already filters to routes assigned to
/// this worker (titular or pareja) in state `verificada`, and already orders
/// them by `codigo`: the app renders what it is given (BR1).
class RouteSummary {
  const RouteSummary({
    required this.routeId,
    required this.codigo,
    required this.estado,
    this.nombre,
    this.totalCapturado,
    this.placasEstado = AppConfig.placasAbierta,
    this.surveyEstado = AppConfig.surveyBloqueada,
    this.fotoObligatoria = false,
  });

  /// The same id consumed by `GET /field/capture/route/{route_id}`.
  final String routeId;
  final String codigo;

  /// Domain is `borrador | verificada`. There is no "congelada" (BR2).
  final String estado;

  /// Optional route name; the wire sends null when there is none.
  final String? nombre;

  /// Units captured so far. Absent — not zero — when the wire omits it.
  final int? totalCapturado;

  /// Placa-pass lock (Spec 9). Fail-OPEN: absent → abierta, only an explicit
  /// 'cerrada' disables capture.
  final String placasEstado;

  /// Survey-pass lock (CL-E8). Fail-CLOSED: absent → bloqueada.
  final String surveyEstado;

  /// Parada photo policy (Spec 10): when true, a face cannot close until every
  /// placa on it has a photo. Absent → false.
  final bool fotoObligatoria;

  factory RouteSummary.fromJson(Map<String, dynamic> json) {
    return RouteSummary(
      routeId: json['route_id'] as String,
      codigo: json['codigo']?.toString() ?? '',
      estado: json['estado']?.toString() ?? '',
      nombre: json['nombre'] as String?,
      totalCapturado: (json['total_capturado'] as num?)?.toInt(),
      placasEstado:
          json['placas_estado']?.toString() ?? AppConfig.placasAbierta,
      surveyEstado:
          json['survey_estado']?.toString() ?? AppConfig.surveyBloqueada,
      fotoObligatoria: json['foto_obligatoria'] as bool? ?? false,
    );
  }

  /// Round-trips through the local cache. Keeps the wire's snake_case so the
  /// cached copy and a fresh response parse identically.
  Map<String, dynamic> toJson() => {
        'route_id': routeId,
        'codigo': codigo,
        'estado': estado,
        'nombre': nombre,
        // Written only when present: absent and zero mean different things.
        if (totalCapturado != null) 'total_capturado': totalCapturado,
        'placas_estado': placasEstado,
        'survey_estado': surveyEstado,
        'foto_obligatoria': fotoObligatoria,
      };
}

/// Response of GET /field/routes.
class AssignedRoutes {
  const AssignedRoutes({required this.esp, required this.items});

  /// Display name of the ESP (tenant) the token belongs to.
  final String esp;

  /// Empty means "no routes assigned": a valid 200, never an error (A1).
  final List<RouteSummary> items;

  factory AssignedRoutes.fromJson(Map<String, dynamic> json) {
    return AssignedRoutes(
      esp: json['esp']?.toString() ?? '',
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => RouteSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'esp': esp,
        'items': items.map((e) => e.toJson()).toList(),
      };
}

/// One ESP entry of the login response (Spec 5). Carries that ESP's field
/// token — handle like the token it is: stored encrypted, never displayed,
/// never logged (CL3/BR7).
class LoginEsp {
  const LoginEsp({
    required this.tenantId,
    required this.espNombre,
    required this.fieldWorkerId,
    required this.fieldToken,
    this.rutasAsignadas,
    this.canSurvey = false,
  });

  final int tenantId;
  final String espNombre;
  final String fieldWorkerId;

  /// Distinct `verificada` routes assigned to this field_worker (titular or
  /// pareja) — same criterion as GET /field/routes, so the picker's number
  /// always matches the list (contract, backend f371076).
  final int? rutasAsignadas;

  /// CL-E8: whether this worker-in-ESP may run the extended survey. Rides in
  /// the login response beside the token; the authority is the backend
  /// (checked live at /sync/push). Fail-CLOSED: absent → false.
  final bool canSurvey;

  final String fieldToken;

  factory LoginEsp.fromJson(Map<String, dynamic> json) {
    return LoginEsp(
      tenantId: (json['tenant_id'] as num).toInt(),
      espNombre: json['esp_nombre']?.toString() ?? '',
      fieldWorkerId: json['field_worker_id'] as String,
      rutasAsignadas: (json['rutas_asignadas'] as num?)?.toInt(),
      canSurvey: json['can_survey'] as bool? ?? false,
      fieldToken: json['field_token'] as String,
    );
  }

  /// For the encrypted session store only — this JSON contains the token and
  /// must never travel anywhere else.
  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'esp_nombre': espNombre,
        'field_worker_id': fieldWorkerId,
        if (rutasAsignadas != null) 'rutas_asignadas': rutasAsignadas,
        'can_survey': canSurvey,
        'field_token': fieldToken,
      };
}

/// Response of POST /field/login.
class LoginResponse {
  const LoginResponse({
    required this.workerNombre,
    this.workerDocumento,
    required this.esps,
  });

  final String workerNombre;
  final String? workerDocumento;

  /// One entry per ACTIVE linked field_worker. Never empty on 200 (an empty
  /// linkage answers 403, A2).
  final List<LoginEsp> esps;

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final worker = json['worker'] as Map<String, dynamic>? ?? const {};
    return LoginResponse(
      workerNombre: worker['nombre']?.toString() ?? '',
      workerDocumento: worker['documento']?.toString(),
      esps: (json['esps'] as List<dynamic>? ?? const [])
          .map((e) => LoginEsp.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// The logged-in session as the device holds it (Spec 5, T5.1).
///
/// Persisted ONLY in secure storage: it contains every ESP's token. The
/// active ESP's token is additionally mirrored into the legacy `field_token`
/// slot, so the API client and every existing flow keep working untouched.
class FieldSession {
  const FieldSession({
    required this.email,
    required this.workerNombre,
    this.workerDocumento,
    required this.esps,
    this.activeTenantId,
  });

  /// Normalized login email — the person key that binds the local queue to
  /// its owner (CL4; the wire carries no person id).
  final String email;

  final String workerNombre;
  final String? workerDocumento;
  final List<LoginEsp> esps;

  /// Tenant chosen as active (CL5). Null only between login and the choice.
  final int? activeTenantId;

  LoginEsp? get activeEsp {
    for (final e in esps) {
      if (e.tenantId == activeTenantId) return e;
    }
    return null;
  }

  FieldSession withActiveTenant(int tenantId) => FieldSession(
        email: email,
        workerNombre: workerNombre,
        workerDocumento: workerDocumento,
        esps: esps,
        activeTenantId: tenantId,
      );

  /// Replaces one ESP's token (silent refresh, T5.3) without touching the
  /// rest of the session.
  FieldSession withEspToken(int tenantId, String token) => FieldSession(
        email: email,
        workerNombre: workerNombre,
        workerDocumento: workerDocumento,
        esps: [
          for (final e in esps)
            e.tenantId == tenantId
                ? LoginEsp(
                    tenantId: e.tenantId,
                    espNombre: e.espNombre,
                    fieldWorkerId: e.fieldWorkerId,
                    rutasAsignadas: e.rutasAsignadas,
                    canSurvey: e.canSurvey,
                    fieldToken: token,
                  )
                : e,
        ],
        activeTenantId: activeTenantId,
      );

  factory FieldSession.fromJson(Map<String, dynamic> json) {
    return FieldSession(
      email: json['email'] as String,
      workerNombre: json['worker_nombre']?.toString() ?? '',
      workerDocumento: json['worker_documento']?.toString(),
      esps: (json['esps'] as List<dynamic>? ?? const [])
          .map((e) => LoginEsp.fromJson(e as Map<String, dynamic>))
          .toList(),
      activeTenantId: (json['active_tenant_id'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'worker_nombre': workerNombre,
        if (workerDocumento != null) 'worker_documento': workerDocumento,
        'esps': esps.map((e) => e.toJson()).toList(),
        if (activeTenantId != null) 'active_tenant_id': activeTenantId,
      };
}

/// One item of GET /field/r1-directory (Spec 15, v4): a **PLACA** (collapsed by
/// manzana + direccion_norm), not a single unit. The NPN is carried but NEVER
/// displayed — the worker only ever sees addresses. The per-unit npn/direccion
/// live in `units[]`; here we keep only the **representative npn** (the single
/// unit's, when `unidades==1`) — a multi-unit placa has `npn=null` and is
/// captured by `direccion_norm`. The full `units[]` is deferred to the survey
/// phase (Spec 8).
class R1DirectoryItem {
  const R1DirectoryItem({
    this.npn,
    required this.direccionNorm,
    this.manzana,
    this.tipoVia,
    this.numVia,
    this.numCruce,
    this.placa,
    this.unidades = 1,
    this.esConjunto = false,
    this.capturada = false,
    this.parseOk = false,
    this.refGeografica,
  });

  /// Representative NPN: the single unit's when [unidades] == 1, else null
  /// (a multi-unit placa is captured at the placa level by [direccionNorm]).
  final String? npn;
  final String direccionNorm;
  final String? manzana;

  /// Server-parsed address components (Spec 10). The local face prediction
  /// groups by these authoritative values — never re-parsing direccion_norm.
  final String? tipoVia;
  final String? numVia;
  final String? numCruce;
  final String? placa;

  /// Census units sharing this placa (apto/local/interior). 1 for a normal
  /// door; >1 for PH. The per-unit detail is linked later (survey, Spec 8).
  final int unidades;

  /// Derived `unidades > 1`; carried for display/debugging only.
  final bool esConjunto;

  /// The placa is already captured on a route (Spec 15, BR-V3): HIDE it from the
  /// typeahead — a finished door is never re-offered.
  final bool capturada;

  final bool parseOk;

  /// Best-effort geographic reference (Spec 10): the corregimiento/vereda name
  /// scraped from the raw address, or null on a clean urban row. Hint only.
  final String? refGeografica;

  factory R1DirectoryItem.fromJson(Map<String, dynamic> json) {
    final units = (json['units'] as List<dynamic>? ?? const []);
    final unidades = (json['unidades'] as num?)?.toInt() ??
        (units.isNotEmpty ? units.length : 1);
    // Representative npn ONLY for a single-unit placa (multi-unit → null, captured
    // by direccion_norm). Tolerate a flat v3 row (npn at the item level) during
    // the brief window before the backend deploys v4.
    String? repNpn;
    if (unidades == 1) {
      if (units.isNotEmpty && units.first is Map) {
        repNpn = (units.first as Map)['npn']?.toString();
      }
      repNpn ??= json['npn']?.toString();
    }
    return R1DirectoryItem(
      npn: repNpn,
      direccionNorm: json['direccion_norm']?.toString() ?? '',
      manzana: json['manzana']?.toString(),
      tipoVia: json['tipo_via']?.toString(),
      numVia: json['num_via']?.toString(),
      numCruce: json['num_cruce']?.toString(),
      placa: json['placa']?.toString(),
      unidades: unidades,
      esConjunto: json['es_conjunto'] as bool? ?? (unidades > 1),
      capturada: json['capturada'] as bool? ?? false,
      parseOk: json['parse_ok'] as bool? ?? false,
      refGeografica: json['ref_geografica']?.toString(),
    );
  }
}

/// Response of GET /field/r1-directory. With `?version=<known>` matching,
/// the server answers `unchanged: true` and no items (CL-R4).
class R1DirectoryResponse {
  const R1DirectoryResponse({
    required this.version,
    this.unchanged = false,
    this.items = const [],
  });

  final String version;
  final bool unchanged;
  final List<R1DirectoryItem> items;

  factory R1DirectoryResponse.fromJson(Map<String, dynamic> json) {
    return R1DirectoryResponse(
      version: json['version']?.toString() ?? '',
      unchanged: json['unchanged'] as bool? ?? false,
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => R1DirectoryItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One parada of a route (Spec 10) — from GET /field/routes/{id}/stops.
/// The app navigates by `faceSequence`; `faceIndex` is identity/QC.
///
/// Decisions v2 (§5–§8): EVERY point of the route is a parada, urban or
/// rural, in one sequence. [blockFaceId] and the terna
/// (`tipoVia`/`numVia`/`numCruce`) are null on a rural parada — that null-ness
/// IS the mode signal the app reads (§8): a terna means guided/distance-only,
/// its absence means free-text (topónimo), never a manual toggle.
class RouteStop {
  const RouteStop({
    required this.stopId,
    required this.faceSequence,
    this.blockFaceId,
    this.tipoVia,
    this.numVia,
    this.numCruce,
    this.cardinal,
    this.cardinalPosicion,
    this.faceIndex,
    this.manzanaCatastral,
    this.orientation,
    this.swept = false,
    this.esActual = false,
  });

  final String stopId;
  final int faceSequence;
  final String? blockFaceId;

  /// The terna that fixes this face's vía + generadora (§7) — lives on the
  /// parada; the backend composes/normalizes against it. Null on a rural
  /// parada (§8): all three null together means free-text/topónimo mode.
  final String? tipoVia;
  final String? numVia;
  final String? numCruce;

  /// Cardinal zone suffix (NORTE/SUR/ESTE/OESTE, address-profiles AP.1–AP.5)
  /// — from the face, never typed. [cardinalPosicion] is 'via' (after
  /// num_via) or 'placa' (after the distance); meaningless when null.
  final String? cardinal;
  final String? cardinalPosicion;

  final int? faceIndex;
  final String? manzanaCatastral;
  final String? orientation;
  final bool swept;

  /// The workable parada: the lowest `faceSequence` not yet swept.
  final bool esActual;

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      stopId: json['stop_id'].toString(),
      faceSequence: (json['face_sequence'] as num?)?.toInt() ?? 0,
      blockFaceId: json['block_face_id'] as String?,
      tipoVia: json['tipo_via'] as String?,
      numVia: json['num_via'] as String?,
      numCruce: json['num_cruce'] as String?,
      cardinal: json['cardinal'] as String?,
      cardinalPosicion: json['cardinal_posicion'] as String?,
      faceIndex: (json['face_index'] as num?)?.toInt(),
      manzanaCatastral: json['manzana_catastral'] as String?,
      orientation: json['orientation'] as String?,
      swept: json['swept'] as bool? ?? false,
      esActual: json['es_actual'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'stop_id': stopId,
        'face_sequence': faceSequence,
        if (blockFaceId != null) 'block_face_id': blockFaceId,
        if (tipoVia != null) 'tipo_via': tipoVia,
        if (numVia != null) 'num_via': numVia,
        if (numCruce != null) 'num_cruce': numCruce,
        if (cardinal != null) 'cardinal': cardinal,
        if (cardinalPosicion != null) 'cardinal_posicion': cardinalPosicion,
        if (faceIndex != null) 'face_index': faceIndex,
        if (manzanaCatastral != null) 'manzana_catastral': manzanaCatastral,
        if (orientation != null) 'orientation': orientation,
        'swept': swept,
        'es_actual': esActual,
      };
}

/// Response of GET /field/routes/{id}/stops.
class RouteStops {
  const RouteStops({required this.routeId, required this.items});

  final String routeId;
  final List<RouteStop> items;

  factory RouteStops.fromJson(Map<String, dynamic> json) {
    return RouteStops(
      routeId: json['route_id']?.toString() ?? '',
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => RouteStop.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Frame item (GET). What was already captured, used to resume.
class RouteFrameItem {
  const RouteFrameItem({
    required this.clientId,
    required this.posicion,
    this.loc,
    this.secuenciaParada,
    this.placa,
    this.manzanaCatastral,
    this.insAfter,
    this.npn,
    this.npnMatchMethod,
    this.blockFaceId,
    this.stopId,
    this.esLote = false,
  });

  final String clientId;
  final int posicion;
  final int? loc;

  /// Spec 11: the predio's position WITHIN its parada (restarts at 1 per
  /// parada), as the server holds it. Null for legacy / no-stop_id rows. The
  /// authoritative value on resume; the app never sends it.
  final int? secuenciaParada;

  final String? placa;
  final String? manzanaCatastral;

  /// Pending relocation flag as the server holds it. Null once the office
  /// applies the shift — the frame is the source of truth on resume.
  final int? insAfter;

  /// NPN link as the server holds it (Spec 7). The frame is the source of
  /// truth on resume; the app re-carries this on every push (BR5).
  final String? npn;

  /// Provenance of the link (field_confirmed | manual | ...); informational.
  final String? npnMatchMethod;

  /// Parada binding as the server holds it (Decisions v2 §6 — the correct
  /// one, urban or rural); re-carried on push.
  final String? stopId;

  /// Parada binding, legacy/compatibility form (Spec 10 PC.1a).
  final String? blockFaceId;

  /// es_lote (Spec 12): the predio is a vacant lot, as the server holds it.
  /// Default false; re-carried on push (full-replacement).
  final bool esLote;

  factory RouteFrameItem.fromJson(Map<String, dynamic> json) {
    return RouteFrameItem(
      clientId: json['client_id'] as String,
      // The 'orden' alias was retired contract-wide (backend de28c1f), and
      // frames are never cached, so nothing feeds the old key any more.
      posicion: (json['posicion'] as num).toInt(),
      loc: (json['loc'] as num?)?.toInt(),
      secuenciaParada: (json['secuencia_parada'] as num?)?.toInt(),
      placa: json['placa'] as String?,
      manzanaCatastral: json['manzana_catastral'] as String?,
      insAfter: (json['ins_after'] as num?)?.toInt(),
      npn: json['npn'] as String?,
      npnMatchMethod: json['npn_match_method'] as String?,
      blockFaceId: json['block_face_id'] as String?,
      stopId: json['stop_id'] as String?,
      esLote: json['es_lote'] as bool? ?? false,
    );
  }
}

/// Response of GET /field/capture/route/{route_id}.
class RouteFrame {
  const RouteFrame({
    required this.routeId,
    this.codigo,
    required this.items,
    this.placasEstado = AppConfig.placasAbierta,
    this.surveyEstado = AppConfig.surveyBloqueada,
    this.fotoObligatoria = false,
  });

  final String routeId;
  final String? codigo;
  final List<RouteFrameItem> items;

  /// Route-state locks carried on the frame too (Spec 9), so a resumed route
  /// gates against the freshest value. Same fail-open/closed defaults.
  final String placasEstado;
  final String surveyEstado;

  /// Parada photo policy (Spec 10), carried on the frame too.
  final bool fotoObligatoria;

  factory RouteFrame.fromJson(Map<String, dynamic> json) {
    return RouteFrame(
      routeId: json['route_id'] as String,
      codigo: json['codigo']?.toString(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => RouteFrameItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      placasEstado:
          json['placas_estado']?.toString() ?? AppConfig.placasAbierta,
      surveyEstado:
          json['survey_estado']?.toString() ?? AppConfig.surveyBloqueada,
      fotoObligatoria: json['foto_obligatoria'] as bool? ?? false,
    );
  }
}

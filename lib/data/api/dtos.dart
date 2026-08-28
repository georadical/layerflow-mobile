/// DTOs for the capture contract (LayerFlow / FastAPI backend).
///
/// Contract (see specs/field-capture-api.md):
///   POST /field/capture/placas  -> batch upsert (idempotent by client_id)
///   GET  /field/capture/route/{route_id} -> frame used to resume
///
/// INVARIANT: ZERO coordinates. No DTO carries lat/lon.
library;

/// Capture item in the POST request.
class PlacaItemRequest {
  const PlacaItemRequest({
    required this.clientId,
    required this.orden,
    this.placa,
    this.manzanaCatastral,
    this.tipoAcceso,
    this.observacion,
  });

  final String clientId;
  final int orden;
  final String? placa;
  final String? manzanaCatastral;
  final String? tipoAcceso;
  final String? observacion;

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'orden': orden,
        // placa is optional: null is sent when blank (the server allows it).
        'placa': placa,
        if (manzanaCatastral != null) 'manzana_catastral': manzanaCatastral,
        if (tipoAcceso != null) 'tipo_acceso': tipoAcceso,
        if (observacion != null) 'observacion': observacion,
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
    this.status,
    this.error,
  });

  final String clientId;
  final bool ok;
  final String? id;
  final int? loc;

  /// 'created' | 'updated' (when ok).
  final String? status;
  final String? error;

  factory PlacaItemResult.fromJson(Map<String, dynamic> json) {
    return PlacaItemResult(
      clientId: json['client_id'] as String,
      ok: json['ok'] as bool? ?? false,
      id: json['id']?.toString(),
      loc: (json['loc'] as num?)?.toInt(),
      status: json['status'] as String?,
      error: json['error']?.toString(),
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

  factory RouteSummary.fromJson(Map<String, dynamic> json) {
    return RouteSummary(
      routeId: json['route_id'] as String,
      codigo: json['codigo']?.toString() ?? '',
      estado: json['estado']?.toString() ?? '',
      nombre: json['nombre'] as String?,
      totalCapturado: (json['total_capturado'] as num?)?.toInt(),
    );
  }
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
}

/// Frame item (GET). What was already captured, used to resume.
class RouteFrameItem {
  const RouteFrameItem({
    required this.clientId,
    required this.orden,
    this.loc,
    this.placa,
    this.manzanaCatastral,
  });

  final String clientId;
  final int orden;
  final int? loc;
  final String? placa;
  final String? manzanaCatastral;

  factory RouteFrameItem.fromJson(Map<String, dynamic> json) {
    return RouteFrameItem(
      clientId: json['client_id'] as String,
      orden: (json['orden'] as num).toInt(),
      loc: (json['loc'] as num?)?.toInt(),
      placa: json['placa'] as String?,
      manzanaCatastral: json['manzana_catastral'] as String?,
    );
  }
}

/// Response of GET /field/capture/route/{route_id}.
class RouteFrame {
  const RouteFrame({
    required this.routeId,
    this.codigo,
    required this.items,
  });

  final String routeId;
  final String? codigo;
  final List<RouteFrameItem> items;

  factory RouteFrame.fromJson(Map<String, dynamic> json) {
    return RouteFrame(
      routeId: json['route_id'] as String,
      codigo: json['codigo']?.toString(),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => RouteFrameItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

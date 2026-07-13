/// DTOs del contrato de captura (backend LayerFlow / FastAPI).
///
/// Contrato (ver specs/field-capture-api.md):
///   POST /field/capture/placas  -> upsert por lote (idempotente por client_id)
///   GET  /field/capture/route/{route_id} -> frame para reanudar
///
/// INVARIANTE: CERO coordenadas. Ningún DTO lleva lat/lon.
library;

/// Item de captura en el request del POST.
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
        // placa opcional: se envía null si está en blanco (el server la permite).
        'placa': placa,
        if (manzanaCatastral != null) 'manzana_catastral': manzanaCatastral,
        if (tipoAcceso != null) 'tipo_acceso': tipoAcceso,
        if (observacion != null) 'observacion': observacion,
      };
}

/// Request del POST /field/capture/placas.
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

/// Resultado por item en la respuesta del POST.
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

  /// 'created' | 'updated' (cuando ok).
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

/// Respuesta del POST /field/capture/placas.
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

/// Item del frame (GET). Lo ya capturado, para reanudar.
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

/// Respuesta del GET /field/capture/route/{route_id}.
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

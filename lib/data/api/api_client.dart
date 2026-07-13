import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../settings/settings_store.dart';
import 'dtos.dart';

/// Error de red/servidor que la UI puede mostrar.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Cliente de la API de captura. Lee baseUrl y field_token en cada request
/// desde [SettingsStore], de modo que cambiar Ajustes surte efecto sin
/// reconstruir el cliente.
class ApiClient {
  ApiClient(this._settings, {Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = AppConfig.connectTimeout
      ..receiveTimeout = AppConfig.receiveTimeout
      ..headers['Content-Type'] = 'application/json';

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _settings.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final SettingsStore _settings;
  final Dio _dio;

  Future<String> _baseUrl() async {
    final base = await _settings.getBaseUrl();
    if (base == null || base.isEmpty) {
      throw ApiException('Falta configurar la URL del backend en Ajustes.');
    }
    return base.replaceAll(RegExp(r'/+$'), '');
  }

  /// POST /field/capture/placas — upsert por lote (idempotente por client_id).
  Future<PlacaBatchResponse> postPlacas(PlacaBatchRequest batch) async {
    final base = await _baseUrl();
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$base${AppConfig.postPlacasPath}',
        data: batch.toJson(),
      );
      return PlacaBatchResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// GET /field/capture/route/{route_id} — frame para reanudar.
  Future<RouteFrame> getRouteFrame(String routeId) async {
    final base = await _baseUrl();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$base${AppConfig.routeFramePath(routeId)}',
      );
      return RouteFrame.fromJson(res.data ?? {'route_id': routeId, 'items': []});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    final code = e.response?.statusCode;
    final data = e.response?.data;
    String detail;
    if (data is Map && data['detail'] != null) {
      detail = data['detail'].toString();
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      detail = 'Sin conexión con el backend.';
    } else {
      detail = e.message ?? 'Error de red.';
    }
    return ApiException(detail, statusCode: code);
  }
}

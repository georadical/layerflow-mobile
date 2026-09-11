import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../settings/settings_store.dart';
import 'dtos.dart';

/// Network/server error that the UI can display.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Capture API client. Reads baseUrl and field_token on every request from
/// [SettingsStore], so that changing Settings takes effect without rebuilding
/// the client.
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

  /// POST /field/capture/placas — batch upsert (idempotent by client_id).
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

  /// GET /field/routes — routes assigned to the authenticated field worker.
  ///
  /// The backend scopes and orders the list, so the app does not filter it.
  /// An empty `items` is a valid answer, not an error.
  Future<AssignedRoutes> getAssignedRoutes() async {
    final base = await _baseUrl();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$base${AppConfig.assignedRoutesPath}',
      );
      return AssignedRoutes.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// GET /field/capture/route/{route_id} — frame used to resume.
  Future<RouteFrame> getRouteFrame(String routeId) async {
    final base = await _baseUrl();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$base${AppConfig.routeFramePath(routeId)}',
      );
      return RouteFrame.fromJson(
          res.data ?? {'route_id': routeId, 'items': []});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// POST /field/login — credentials → one fresh 30-day token per active ESP.
  ///
  /// The password lives only in this call: used, sent over TLS, discarded
  /// (CL3). Neither argument is ever logged.
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    final base = await _baseUrl();
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$base${AppConfig.loginPath}',
        data: {'email': email.trim().toLowerCase(), 'password': password},
      );
      return LoginResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// POST /field/token/refresh — silent renewal of the ACTIVE token (the
  /// interceptor sends it). The server accepts it expired up to 7 days;
  /// beyond that it answers 401 and the recovery is login.
  Future<String> refreshToken() async {
    final base = await _baseUrl();
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$base${AppConfig.refreshPath}',
      );
      final token = res.data?['field_token'] as String?;
      if (token == null || token.isEmpty) {
        throw ApiException('El refresh no devolvió un token.');
      }
      return token;
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

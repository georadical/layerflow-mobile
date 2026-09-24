import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../settings/settings_store.dart';
import 'dtos.dart';
import 'sync_dtos.dart';

/// Network/server error that the UI can display.
class ApiException implements Exception {
  ApiException(this.message,
      {this.statusCode, this.codigo, this.localizaciones = const []});
  final String message;
  final int? statusCode;

  /// Stable machine code from the server's `detail.codigo` when present
  /// (e.g. 'ruta_placas_cerrada'), so callers map the cause, not the prose.
  final String? codigo;

  /// The offending locs from `detail.localizaciones` when the server names
  /// them (Spec 10: a foto_obligatoria_pendiente rejection lists which locs
  /// still lack a photo), so the app can tell the worker exactly where.
  final List<int> localizaciones;

  @override
  String toString() => 'ApiException($statusCode/$codigo): $message';
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

  /// POST /sync/push — the survey pass batch (Spec 8, T8.5c). Serialises the
  /// operations parents-before-children (`ordered()`), and parses the
  /// per-op verdicts + resumen. A closed/unauthorized op comes back inside
  /// the 200 envelope with its `codigo`, not as an HTTP error.
  Future<SyncPushResponse> pushSync(SyncPushRequest req) async {
    final base = await _baseUrl();
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$base${AppConfig.syncPushPath}',
        data: req.ordered().toJson(),
      );
      return SyncPushResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// GET /field/routes/{id}/stops — the route's paradas (Spec 10), ordered by
  /// face_sequence, with the current one flagged (es_actual).
  Future<RouteStops> getRouteStops(String routeId) async {
    final base = await _baseUrl();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$base${AppConfig.routeStopsPath(routeId)}',
      );
      return RouteStops.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// POST /field/routes/{id}/stops/{stop_id}/swept — mark a face swept
  /// (gated) or reopen it (`swept:false`, ungated). A gated rejection throws
  /// ApiException with `codigo` (barrido_fuera_de_orden /
  /// foto_obligatoria_pendiente).
  Future<void> markSwept(
    String routeId,
    String stopId, {
    required bool swept,
  }) async {
    final base = await _baseUrl();
    try {
      await _dio.post<void>(
        '$base${AppConfig.stopSweptPath(routeId, stopId)}',
        data: {'swept': swept},
      );
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

  /// GET /field/r1-directory — the tenant's addressed R1 slice (Spec 7).
  /// Pass [knownVersion] to skip the download when nothing changed (CL-R4).
  Future<R1DirectoryResponse> getR1Directory({String? knownVersion}) async {
    final base = await _baseUrl();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$base${AppConfig.r1DirectoryPath}',
        queryParameters: {
          if (knownVersion != null && knownVersion.isNotEmpty)
            'version': knownVersion,
        },
      );
      return R1DirectoryResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// POST /field/capture/evidence — one JPEG per request (Spec 7).
  /// Idempotent per unit: re-uploading replaces file and record.
  /// 415 = not JPEG, 413 = over 500KB, 400 = bad soporte, 404 = the unit's
  /// placa push has not landed yet (the caller holds the photo).
  Future<void> uploadEvidence({
    required String clientId,
    required String soporte,
    required String filePath,
    String proposito = AppConfig.propositoPlaca,
  }) async {
    final base = await _baseUrl();
    try {
      final form = FormData.fromMap({
        'client_id': clientId,
        'soporte': soporte,
        'proposito': proposito,
        'foto': await MultipartFile.fromFile(
          filePath,
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      await _dio.post<void>('$base${AppConfig.evidencePath}', data: form);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    final code = e.response?.statusCode;
    final data = e.response?.data;
    final rawDetail = data is Map ? data['detail'] : null;
    String detail;
    String? codigo;
    var localizaciones = const <int>[];
    if (rawDetail is Map) {
      // Structured detail (e.g. 409 {detail:{codigo, motivo}}): keep the
      // machine code apart from the human message.
      codigo = rawDetail['codigo']?.toString();
      detail = (rawDetail['motivo'] ??
              rawDetail['mensaje'] ??
              rawDetail['error'] ??
              codigo ??
              'Error del servidor.')
          .toString();
      final locs = rawDetail['localizaciones'];
      if (locs is List) {
        localizaciones = [
          for (final l in locs)
            if (l is num) l.toInt() else int.tryParse(l.toString()) ?? -1,
        ].where((l) => l >= 0).toList();
      }
    } else if (rawDetail != null) {
      detail = rawDetail.toString();
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      detail = 'Sin conexión con el backend.';
    } else {
      detail = e.message ?? 'Error de red.';
    }
    return ApiException(detail,
        statusCode: code, codigo: codigo, localizaciones: localizaciones);
  }
}

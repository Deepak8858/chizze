import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_config.dart';
import '../models/api_response.dart';

/// Centralized HTTP client for the Go backend API (uses Dio)
class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: ApiConfig.timeoutSeconds),
        receiveTimeout: const Duration(seconds: ApiConfig.timeoutSeconds),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
  }

  /// Set the JWT auth token (called after login)
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Clear auth token (called on logout)
  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  // ─── Core HTTP Methods ───

  /// GET request
  Future<ApiResponse<T>> get<T>(
    String endpoint, {
    Map<String, dynamic>? queryParams,
    T Function(dynamic)? fromData,
  }) async {
    try {
      final response = await _dio.get(endpoint, queryParameters: queryParams);
      return _parseResponse<T>(response, fromData);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// POST request
  Future<ApiResponse<T>> post<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromData,
  }) async {
    try {
      final response = await _dio.post(endpoint, data: body);
      return _parseResponse<T>(response, fromData);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// PUT request
  Future<ApiResponse<T>> put<T>(
    String endpoint, {
    Map<String, dynamic>? body,
    T Function(dynamic)? fromData,
  }) async {
    try {
      final response = await _dio.put(endpoint, data: body);
      return _parseResponse<T>(response, fromData);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// DELETE request
  Future<ApiResponse<T>> delete<T>(
    String endpoint, {
    T Function(dynamic)? fromData,
  }) async {
    try {
      final response = await _dio.delete(endpoint);
      return _parseResponse<T>(response, fromData);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ─── Helpers ───

  ApiResponse<T> _parseResponse<T>(
    Response response,
    T Function(dynamic)? fromData,
  ) {
    final json = response.data as Map<String, dynamic>;
    return ApiResponse<T>.fromJson(json, fromData);
  }

  ApiException _handleDioError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      final message = data is Map
          ? data['error'] ?? 'Request failed'
          : 'Request failed';
      return ApiException(
        statusCode: e.response?.statusCode ?? 500,
        message: message.toString(),
      );
    }
    return ApiException(statusCode: 0, message: e.message ?? 'Network error');
  }
}

/// Global ApiClient provider
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

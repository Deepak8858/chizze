import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_config.dart';
import '../models/api_response.dart';

/// Secure storage key for persisted JWT
const _kJwtStorageKey = 'chizze_jwt_token';

/// Centralized HTTP client for the Go backend API (uses Dio)
class ApiClient {
  late final Dio _dio;
  String? _currentToken;
  Future<String?> Function()? _refreshCallback;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: Duration(seconds: ApiConfig.timeoutSeconds),
        receiveTimeout: Duration(seconds: ApiConfig.timeoutSeconds),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add interceptor for automatic 401 → refresh → retry
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          if (error.response?.statusCode == 401 && _refreshCallback != null) {
            debugPrint('[ApiClient] 401 received, attempting token refresh...');
            try {
              final newToken = await _refreshCallback!();
              if (newToken != null) {
                setAuthToken(newToken);
                // Retry the original request with the new token
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                final response = await _dio.fetch(opts);
                return handler.resolve(response);
              }
            } catch (e) {
              debugPrint('[ApiClient] Token refresh failed: $e');
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  /// Set the JWT auth token (called after login)
  void setAuthToken(String token) {
    _currentToken = token;
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Clear auth token (called on logout)
  void clearAuthToken() {
    _currentToken = null;
    _dio.options.headers.remove('Authorization');
  }

  /// Persist the JWT token to secure storage
  Future<void> persistToken(String token) async {
    try {
      await _secureStorage.write(key: _kJwtStorageKey, value: token);
    } catch (e) {
      debugPrint('[ApiClient] Failed to persist token: $e');
    }
  }

  /// Load the persisted JWT token from secure storage and set it
  /// Returns the token if found, null otherwise
  Future<String?> loadPersistedToken() async {
    try {
      final token = await _secureStorage.read(key: _kJwtStorageKey);
      if (token != null && token.isNotEmpty) {
        setAuthToken(token);
        debugPrint('[ApiClient] Restored persisted JWT token');
        return token;
      }
    } catch (e) {
      debugPrint('[ApiClient] Failed to load persisted token: $e');
    }
    return null;
  }

  /// Clear persisted JWT token from secure storage
  Future<void> clearPersistedToken() async {
    try {
      await _secureStorage.delete(key: _kJwtStorageKey);
    } catch (e) {
      debugPrint('[ApiClient] Failed to clear persisted token: $e');
    }
  }

  /// Get the current token (for refresh logic)
  String? get currentToken => _currentToken;

  /// Set the refresh callback — called when a 401 is received
  void setRefreshCallback(Future<String?> Function() callback) {
    _refreshCallback = callback;
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

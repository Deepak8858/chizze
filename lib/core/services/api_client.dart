import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'api_config.dart';
import '../models/api_response.dart';
import 'cache_service.dart';

/// Secure storage key for persisted JWT
const _kJwtStorageKey = 'chizze_jwt_token';

/// Global cache service instance (initialized in main.dart)
final CacheService cacheService = CacheService();

/// Centralized HTTP client for the Go backend API (uses Dio)
class ApiClient {
  late final Dio _dio;
  String? _currentToken;
  Future<String?> Function()? _refreshCallback;
  void Function()? _onAuthFailure;
  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: Duration(seconds: ApiConfig.timeoutSeconds),
        receiveTimeout: Duration(seconds: ApiConfig.timeoutSeconds),
        sendTimeout: Duration(seconds: ApiConfig.timeoutSeconds),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add cache interceptor first (serves offline responses)
    _dio.interceptors.add(CacheInterceptor(cacheService));

    // Add interceptor for automatic 401 → refresh → retry
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          // Skip refresh for public auth endpoints (exchange, verify-otp, etc.)
          final path = error.requestOptions.path;
          final isPublicAuth = path.contains('/auth/');
          if (error.response?.statusCode == 401 &&
              _refreshCallback != null &&
              !isPublicAuth) {
            // If already refreshing, wait for the in-flight refresh to complete
            if (_isRefreshing) {
              try {
                final newToken = await _refreshCompleter?.future;
                if (newToken != null) {
                  final opts = error.requestOptions;
                  opts.headers['Authorization'] = 'Bearer $newToken';
                  final response = await _dio.fetch(opts);
                  return handler.resolve(response);
                }
              } catch (_) {}
              return handler.next(error);
            }

            _isRefreshing = true;
            _refreshCompleter = Completer<String?>();
            if (kDebugMode) {
              debugPrint('[ApiClient] 401 received, attempting token refresh...');
            }
            try {
              final newToken = await _refreshCallback!();
              _refreshCompleter?.complete(newToken);
              if (newToken != null) {
                setAuthToken(newToken);
                // Retry the original request with the new token
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                final response = await _dio.fetch(opts);
                return handler.resolve(response);
              } else {
                // Refresh returned null — force logout
                _onAuthFailure?.call();
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[ApiClient] Token refresh failed: $e');
              }
              _refreshCompleter?.completeError(e);
              // Token refresh failed — force logout to clear stale state
              _onAuthFailure?.call();
            } finally {
              _isRefreshing = false;
              _refreshCompleter = null;
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
      if (kDebugMode) debugPrint('[ApiClient] Failed to persist token: $e');
    }
  }

  /// Load the persisted JWT token from secure storage and set it
  /// Returns the token if found, null otherwise
  Future<String?> loadPersistedToken() async {
    try {
      final token = await _secureStorage.read(key: _kJwtStorageKey);
      if (token != null && token.isNotEmpty) {
        setAuthToken(token);
        if (kDebugMode) debugPrint('[ApiClient] Restored persisted JWT token');
        return token;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiClient] Failed to load persisted token: $e');
    }
    return null;
  }

  /// Clear persisted JWT token from secure storage
  Future<void> clearPersistedToken() async {
    try {
      await _secureStorage.delete(key: _kJwtStorageKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[ApiClient] Failed to clear persisted token: $e');
    }
  }

  /// Get the current token (for refresh logic)
  String? get currentToken => _currentToken;

  /// Set the refresh callback — called when a 401 is received
  void setRefreshCallback(Future<String?> Function() callback) {
    _refreshCallback = callback;
  }

  /// Set callback for unrecoverable auth failure — forces logout
  void setAuthFailureCallback(void Function() callback) {
    _onAuthFailure = callback;
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
    Map<String, String>? headers,
    T Function(dynamic)? fromData,
  }) async {
    try {
      final response = await _dio.post(
        endpoint,
        data: body,
        options: headers != null ? Options(headers: headers) : null,
      );
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
    // Report API errors to Sentry with request context
    Sentry.addBreadcrumb(Breadcrumb(
      message: 'API Error: ${e.requestOptions.method} ${e.requestOptions.path}',
      category: 'http',
      level: SentryLevel.error,
      data: {
        'url': e.requestOptions.uri.toString(),
        'method': e.requestOptions.method,
        'status_code': e.response?.statusCode?.toString() ?? 'none',
      },
    ));

    if (e.response != null) {
      final data = e.response?.data;
      final message = data is Map
          ? data['error'] ?? 'Request failed'
          : 'Request failed';
      final exception = ApiException(
        statusCode: e.response?.statusCode ?? 500,
        message: message.toString(),
      );
      // Don't auto-report 5xx errors — callers handle them gracefully and
      // the breadcrumb above provides sufficient context. Auto-capturing
      // caused noisy duplicate Sentry issues (FLUTTER-2/6/7).
      return exception;
    }
    final exception = ApiException(statusCode: 0, message: e.message ?? 'Network error');
    // Don't report transient network errors (offline, timeout, DNS) to Sentry —
    // they are not bugs. The breadcrumb above is sufficient for context.
    return exception;
  }
}

/// Global ApiClient provider
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

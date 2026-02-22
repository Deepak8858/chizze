import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Cache entry with TTL
class CacheEntry {
  final String data;
  final int statusCode;
  final int timestamp;
  final int ttlMs;

  CacheEntry({
    required this.data,
    required this.statusCode,
    required this.timestamp,
    required this.ttlMs,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch - timestamp > ttlMs;

  Map<String, dynamic> toMap() => {
        'data': data,
        'statusCode': statusCode,
        'timestamp': timestamp,
        'ttlMs': ttlMs,
      };

  factory CacheEntry.fromMap(Map<dynamic, dynamic> map) => CacheEntry(
        data: map['data'] as String,
        statusCode: map['statusCode'] as int,
        timestamp: map['timestamp'] as int,
        ttlMs: map['ttlMs'] as int,
      );
}

/// Hive-backed offline cache service with configurable TTL per endpoint
class CacheService {
  static const String _boxName = 'api_cache';
  late Box<Map> _box;

  /// Default TTL per endpoint pattern (in milliseconds)
  static final Map<String, int> _ttlMap = {
    '/restaurants': 5 * 60 * 1000, // 5 min — restaurant list
    '/users/me': 10 * 60 * 1000, // 10 min — user profile
    '/users/me/addresses': 30 * 60 * 1000, // 30 min — addresses
    '/users/me/favorites': 5 * 60 * 1000, // 5 min — favorites
    '/notifications': 2 * 60 * 1000, // 2 min — notifications
    '/orders': 1 * 60 * 1000, // 1 min — orders
    '/coupons': 15 * 60 * 1000, // 15 min — coupons
    '/gold': 10 * 60 * 1000, // 10 min — gold plans
    '/referrals': 10 * 60 * 1000, // 10 min — referrals
  };

  static const int _defaultTtl = 3 * 60 * 1000; // 3 min default

  /// Initialize Hive and open cache box
  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<Map>(_boxName);
    debugPrint('[Cache] Initialized with ${_box.length} cached entries');
  }

  /// Get TTL for an endpoint
  int _getTtl(String path) {
    for (final entry in _ttlMap.entries) {
      if (path.contains(entry.key)) return entry.value;
    }
    return _defaultTtl;
  }

  /// Build cache key from request path + query params
  String _buildKey(String path, Map<String, dynamic>? queryParams) {
    final buffer = StringBuffer(path);
    if (queryParams != null && queryParams.isNotEmpty) {
      final sorted = queryParams.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      buffer.write('?');
      buffer.write(sorted.map((e) => '${e.key}=${e.value}').join('&'));
    }
    return buffer.toString();
  }

  /// Store response in cache
  Future<void> put(
    String path,
    Map<String, dynamic>? queryParams,
    int statusCode,
    String responseBody,
  ) async {
    final key = _buildKey(path, queryParams);
    final entry = CacheEntry(
      data: responseBody,
      statusCode: statusCode,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      ttlMs: _getTtl(path),
    );
    await _box.put(key, entry.toMap());
  }

  /// Get cached response (returns null if missing or expired)
  CacheEntry? get(String path, Map<String, dynamic>? queryParams) {
    final key = _buildKey(path, queryParams);
    final raw = _box.get(key);
    if (raw == null) return null;

    final entry = CacheEntry.fromMap(raw);
    if (entry.isExpired) {
      _box.delete(key);
      return null;
    }
    return entry;
  }

  /// Get cached response even if expired (for offline fallback)
  CacheEntry? getStale(String path, Map<String, dynamic>? queryParams) {
    final key = _buildKey(path, queryParams);
    final raw = _box.get(key);
    if (raw == null) return null;
    return CacheEntry.fromMap(raw);
  }

  /// Clear all cached data
  Future<void> clearAll() async {
    await _box.clear();
    debugPrint('[Cache] All entries cleared');
  }

  /// Clear expired entries
  Future<int> pruneExpired() async {
    int pruned = 0;
    final keysToDelete = <dynamic>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw != null) {
        final entry = CacheEntry.fromMap(raw);
        if (entry.isExpired) {
          keysToDelete.add(key);
          pruned++;
        }
      }
    }
    await _box.deleteAll(keysToDelete);
    if (pruned > 0) debugPrint('[Cache] Pruned $pruned expired entries');
    return pruned;
  }
}

/// Dio interceptor that serves cached GET responses when offline
/// and caches successful GET responses for offline fallback
class CacheInterceptor extends Interceptor {
  final CacheService _cache;

  CacheInterceptor(this._cache);

  /// Endpoints that should NOT be cached (mutations, auth, payments)
  static const _noCachePaths = [
    '/auth/',
    '/payments/',
    '/partner/',
    '/delivery/',
  ];

  bool _shouldCache(String path) {
    return !_noCachePaths.any((p) => path.contains(p));
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Only cache GET requests
    if (options.method != 'GET' || !_shouldCache(options.path)) {
      handler.next(options);
      return;
    }

    // Check connectivity
    final connectivity = await Connectivity().checkConnectivity();
    final isOffline = connectivity.contains(ConnectivityResult.none);

    if (isOffline) {
      // Serve stale cache when offline
      final cached = _cache.getStale(options.path, options.queryParameters);
      if (cached != null) {
        debugPrint('[Cache] Serving offline cache: ${options.path}');
        handler.resolve(
          Response(
            requestOptions: options,
            data: jsonDecode(cached.data),
            statusCode: cached.statusCode,
            headers: Headers.fromMap({
              'x-cache': ['HIT-OFFLINE'],
            }),
          ),
        );
        return;
      }
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Cache successful GET responses
    if (response.requestOptions.method == 'GET' &&
        response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300 &&
        _shouldCache(response.requestOptions.path)) {
      final body = jsonEncode(response.data);
      _cache.put(
        response.requestOptions.path,
        response.requestOptions.queryParameters,
        response.statusCode!,
        body,
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // On network error, try to serve cached data
    if (err.requestOptions.method == 'GET' &&
        _shouldCache(err.requestOptions.path) &&
        (err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError ||
            err.type == DioExceptionType.unknown)) {
      final cached = _cache.getStale(
        err.requestOptions.path,
        err.requestOptions.queryParameters,
      );
      if (cached != null) {
        debugPrint('[Cache] Serving stale cache on error: ${err.requestOptions.path}');
        handler.resolve(
          Response(
            requestOptions: err.requestOptions,
            data: jsonDecode(cached.data),
            statusCode: cached.statusCode,
            headers: Headers.fromMap({
              'x-cache': ['HIT-STALE'],
            }),
          ),
        );
        return;
      }
    }
    handler.next(err);
  }
}

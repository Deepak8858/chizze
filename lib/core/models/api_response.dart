/// Standard API response wrapper matching the Go backend
/// { "success": true, "data": ..., "error": "...", "meta": {...} }
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final PaginationMeta? meta;

  const ApiResponse({required this.success, this.data, this.error, this.meta});

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromData,
  ) {
    return ApiResponse<T>(
      success: json['success'] ?? false,
      data: json['data'] != null && fromData != null
          ? fromData(json['data'])
          : json['data'] as T?,
      error: json['error'] as String?,
      meta: json['meta'] != null ? PaginationMeta.fromJson(json['meta']) : null,
    );
  }
}

/// Pagination metadata
class PaginationMeta {
  final int page;
  final int perPage;
  final int total;
  final int totalPages;

  const PaginationMeta({
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) {
    return PaginationMeta(
      page: json['page'] ?? 1,
      perPage: json['perPage'] ?? 20,
      total: json['total'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
    );
  }
}

/// API exception for error handling
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

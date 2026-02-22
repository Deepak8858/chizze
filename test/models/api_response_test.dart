import 'package:flutter_test/flutter_test.dart';
import 'package:chizze/core/models/api_response.dart';

void main() {
  group('PaginationMeta.fromJson', () {
    test('parses all fields', () {
      final meta = PaginationMeta.fromJson({
        'page': 2,
        'perPage': 10,
        'total': 55,
        'totalPages': 6,
      });
      expect(meta.page, 2);
      expect(meta.perPage, 10);
      expect(meta.total, 55);
      expect(meta.totalPages, 6);
    });

    test('defaults on empty map', () {
      final meta = PaginationMeta.fromJson({});
      expect(meta.page, 1);
      expect(meta.perPage, 20);
      expect(meta.total, 0);
      expect(meta.totalPages, 0);
    });
  });

  group('ApiResponse.fromJson', () {
    test('successful response with data', () {
      final resp = ApiResponse<String>.fromJson(
        {'success': true, 'data': 'hello', 'error': null, 'meta': null},
        (d) => d as String,
      );
      expect(resp.success, isTrue);
      expect(resp.data, 'hello');
      expect(resp.error, isNull);
      expect(resp.meta, isNull);
    });

    test('error response', () {
      final resp = ApiResponse.fromJson(
        {'success': false, 'error': 'Not found'},
        null,
      );
      expect(resp.success, isFalse);
      expect(resp.error, 'Not found');
      expect(resp.data, isNull);
    });

    test('response with pagination meta', () {
      final resp = ApiResponse<List>.fromJson(
        {
          'success': true,
          'data': [1, 2, 3],
          'meta': {'page': 1, 'perPage': 20, 'total': 3, 'totalPages': 1},
        },
        (d) => d as List,
      );
      expect(resp.success, isTrue);
      expect(resp.data, [1, 2, 3]);
      expect(resp.meta, isNotNull);
      expect(resp.meta!.total, 3);
    });

    test('response without fromData function uses cast', () {
      final resp = ApiResponse<String>.fromJson(
        {'success': true, 'data': 'raw'},
        null,
      );
      expect(resp.data, 'raw');
    });

    test('defaults success to false if missing', () {
      final resp = ApiResponse.fromJson({}, null);
      expect(resp.success, isFalse);
    });
  });

  group('ApiException', () {
    test('toString format', () {
      const ex = ApiException(statusCode: 404, message: 'Not found');
      expect(ex.toString(), 'ApiException(404): Not found');
    });

    test('implements Exception', () {
      const ex = ApiException(statusCode: 500, message: 'Server error');
      expect(ex, isA<Exception>());
    });
  });
}

class PromoBanner {
  final String id;
  final String title;
  final String imageUrl;
  final String deeplink;
  final String targetSegment;
  final bool isActive;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int sortOrder;

  const PromoBanner({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.deeplink,
    required this.targetSegment,
    required this.isActive,
    required this.validFrom,
    required this.validUntil,
    required this.sortOrder,
  });

  factory PromoBanner.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is! String || value.trim().isEmpty) return null;
      return DateTime.tryParse(value)?.toUtc();
    }

    int parseSort(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 9999;
      return 9999;
    }

    return PromoBanner(
      id: map['\$id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      imageUrl: map['image_url']?.toString() ?? '',
      deeplink: map['deeplink']?.toString() ?? '',
      targetSegment: map['target_segment']?.toString() ?? 'all',
      isActive: map['is_active'] == null ? true : map['is_active'] == true,
      validFrom: parseDate(map['valid_from']),
      validUntil: parseDate(map['valid_until']),
      sortOrder: parseSort(map['sort_order']),
    );
  }
}

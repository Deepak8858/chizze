import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Saved address model
class SavedAddress {
  final String id;
  final String label; // Home, Work, Other
  final String fullAddress;
  final String landmark;
  final double latitude;
  final double longitude;
  final bool isDefault;

  const SavedAddress({
    required this.id,
    required this.label,
    required this.fullAddress,
    this.landmark = '',
    this.latitude = 0,
    this.longitude = 0,
    this.isDefault = false,
  });

  SavedAddress copyWith({
    String? label,
    String? fullAddress,
    String? landmark,
    double? latitude,
    double? longitude,
    bool? isDefault,
  }) {
    return SavedAddress(
      id: id,
      label: label ?? this.label,
      fullAddress: fullAddress ?? this.fullAddress,
      landmark: landmark ?? this.landmark,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  IconLabel get iconLabel {
    switch (label.toLowerCase()) {
      case 'home':
        return IconLabel.home;
      case 'work':
        return IconLabel.work;
      default:
        return IconLabel.other;
    }
  }
}

/// Icon and label pairing
enum IconLabel {
  home('Home', '🏠'),
  work('Work', '💼'),
  other('Other', '📍');

  final String label;
  final String emoji;
  const IconLabel(this.label, this.emoji);
}

/// Address notifier
class AddressNotifier extends StateNotifier<List<SavedAddress>> {
  AddressNotifier() : super(_mockAddresses);

  void addAddress(SavedAddress address) {
    state = [...state, address];
  }

  void removeAddress(String id) {
    state = state.where((a) => a.id != id).toList();
  }

  void updateAddress(SavedAddress updated) {
    state = state.map((a) => a.id == updated.id ? updated : a).toList();
  }

  void setDefault(String id) {
    state = state.map((a) => a.copyWith(isDefault: a.id == id)).toList();
  }

  static final _mockAddresses = [
    const SavedAddress(
      id: 'addr1',
      label: 'Home',
      fullAddress: '45, Lake View Colony, Madhapur, Hyderabad 500081',
      landmark: 'Near Inorbit Mall',
      latitude: 17.4401,
      longitude: 78.3911,
      isDefault: true,
    ),
    const SavedAddress(
      id: 'addr2',
      label: 'Work',
      fullAddress: '12A, Tech Park, HITEC City, Hyderabad 500032',
      landmark: 'Opposite Mindspace',
      latitude: 17.4486,
      longitude: 78.3810,
    ),
    const SavedAddress(
      id: 'addr3',
      label: 'Other',
      fullAddress: '8, Jubilee Hills Rd No.36, Hyderabad 500033',
      landmark: 'Near GVK One Mall',
      latitude: 17.4312,
      longitude: 78.4079,
    ),
  ];
}

final addressProvider =
    StateNotifierProvider<AddressNotifier, List<SavedAddress>>((ref) {
      return AddressNotifier();
    });

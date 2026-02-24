import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';

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

/// Address notifier — API-backed with mock fallback
class AddressNotifier extends StateNotifier<List<SavedAddress>> {
  final ApiClient _api;

  AddressNotifier(this._api) : super(const []) {
    fetchAddresses();
  }

  /// Fetch addresses from API
  Future<void> fetchAddresses() async {
    try {
      final response = await _api.get(ApiConfig.addresses);
      if (response.success && response.data != null) {
        final list = response.data as List<dynamic>;
        state = list.map((d) {
          final m = d as Map<String, dynamic>;
          return SavedAddress(
            id: m['\$id'] ?? '',
            label: m['label'] ?? 'Other',
            fullAddress: m['full_address'] ?? '',
            landmark: m['landmark'] ?? '',
            latitude: (m['latitude'] ?? 0).toDouble(),
            longitude: (m['longitude'] ?? 0).toDouble(),
            isDefault: m['is_default'] ?? false,
          );
        }).toList();
      }
    } on ApiException {
      // Keep current state
    } catch (_) {}
  }

  void addAddress(SavedAddress address) {
    state = [...state, address];
    _api
        .post(
          ApiConfig.addresses,
          body: {
            'label': address.label,
            'full_address': address.fullAddress,
            'landmark': address.landmark,
            'latitude': address.latitude,
            'longitude': address.longitude,
            'is_default': address.isDefault,
          },
        )
        .then((r) {
      if (!r.success) {
        debugPrint('[Address] add failed: ${r.error}');
        state = state.where((a) => a.id != address.id).toList();
      }
    }).catchError((e) {
      debugPrint('[Address] add error: $e');
      state = state.where((a) => a.id != address.id).toList();
    });
  }

  void removeAddress(String id) {
    final removed = state.where((a) => a.id == id).toList();
    state = state.where((a) => a.id != id).toList();
    _api.delete('${ApiConfig.addresses}/$id').then((r) {
      if (!r.success) {
        debugPrint('[Address] remove failed: ${r.error}');
        state = [...state, ...removed];
      }
    }).catchError((e) {
      debugPrint('[Address] remove error: $e');
      state = [...state, ...removed];
    });
  }

  void updateAddress(SavedAddress updated) {
    final old = state.firstWhere((a) => a.id == updated.id, orElse: () => updated);
    state = state.map((a) => a.id == updated.id ? updated : a).toList();
    _api
        .put(
          '${ApiConfig.addresses}/${updated.id}',
          body: {
            'label': updated.label,
            'full_address': updated.fullAddress,
            'landmark': updated.landmark,
          },
        )
        .then((r) {
      if (!r.success) {
        debugPrint('[Address] update failed: ${r.error}');
        state = state.map((a) => a.id == updated.id ? old : a).toList();
      }
    }).catchError((e) {
      debugPrint('[Address] update error: $e');
      state = state.map((a) => a.id == updated.id ? old : a).toList();
    });
  }

  void setDefault(String id) {
    final prev = List<SavedAddress>.of(state);
    state = state.map((a) => a.copyWith(isDefault: a.id == id)).toList();
    // Persist default flag to backend for each address
    for (final addr in state) {
      _api.put('${ApiConfig.addresses}/${addr.id}', body: {
        'is_default': addr.id == id,
      }).then((r) {
        if (!r.success) {
          debugPrint('[Address] setDefault update failed for ${addr.id}: ${r.error}');
        }
      }).catchError((e) {
        debugPrint('[Address] setDefault error for ${addr.id}: $e');
        state = prev;
      });
    }
  }

  // Mock addresses removed — using real data from API only
}

final addressProvider =
    StateNotifierProvider<AddressNotifier, List<SavedAddress>>((ref) {
      final api = ref.watch(apiClientProvider);
      return AddressNotifier(api);
    });

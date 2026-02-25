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
      if (r.success && r.data != null) {
        // Replace optimistic entry with server-returned doc (real $id)
        final data = r.data as Map<String, dynamic>;
        final serverAddress = SavedAddress(
          id: data['\$id'] ?? address.id,
          label: data['label'] ?? address.label,
          fullAddress: data['full_address'] ?? address.fullAddress,
          landmark: data['landmark'] ?? address.landmark,
          latitude: (data['latitude'] ?? address.latitude).toDouble(),
          longitude: (data['longitude'] ?? address.longitude).toDouble(),
          isDefault: data['is_default'] ?? address.isDefault,
        );
        state = state.map((a) => a.id == address.id ? serverAddress : a).toList();
        debugPrint('[Address] synced server ID: ${serverAddress.id}');
      } else if (!r.success) {
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
    // Only update the new default address and the old default (if any)
    final oldDefault = prev.where((a) => a.isDefault && a.id != id).toList();
    // Set new default
    _api.put('${ApiConfig.addresses}/$id', body: {
      'is_default': true,
    }).then((r) {
      if (!r.success) {
        debugPrint('[Address] setDefault update failed for $id: ${r.error}');
        state = prev;
      }
    }).catchError((e) {
      debugPrint('[Address] setDefault error for $id: $e');
      state = prev;
    });
    // Clear old default(s)
    for (final addr in oldDefault) {
      _api.put('${ApiConfig.addresses}/${addr.id}', body: {
        'is_default': false,
      }).then((r) {
        if (!r.success) {
          debugPrint('[Address] clear old default failed for ${addr.id}: ${r.error}');
        }
      }).catchError((e) {
        debugPrint('[Address] clear old default error for ${addr.id}: $e');
      });
    }
  }

  // Mock addresses removed — using real data from API only

  /// Add address and wait for server response — returns the server-created address
  /// Use this for flows that need the real server ID (e.g. onboarding, checkout)
  Future<SavedAddress?> addAddressAsync(SavedAddress address) async {
    try {
      final r = await _api.post(
        ApiConfig.addresses,
        body: {
          'label': address.label,
          'full_address': address.fullAddress,
          'landmark': address.landmark,
          'latitude': address.latitude,
          'longitude': address.longitude,
          'is_default': address.isDefault,
        },
      );
      if (r.success && r.data != null) {
        final data = r.data as Map<String, dynamic>;
        final serverAddress = SavedAddress(
          id: data['\$id'] ?? '',
          label: data['label'] ?? address.label,
          fullAddress: data['full_address'] ?? address.fullAddress,
          landmark: data['landmark'] ?? address.landmark,
          latitude: (data['latitude'] ?? address.latitude).toDouble(),
          longitude: (data['longitude'] ?? address.longitude).toDouble(),
          isDefault: data['is_default'] ?? address.isDefault,
        );
        state = [...state, serverAddress];
        debugPrint('[Address] addAddressAsync success: ${serverAddress.id}');
        return serverAddress;
      }
      debugPrint('[Address] addAddressAsync failed: ${r.error}');
      return null;
    } catch (e) {
      debugPrint('[Address] addAddressAsync error: $e');
      return null;
    }
  }
}

final addressProvider =
    StateNotifierProvider<AddressNotifier, List<SavedAddress>>((ref) {
      final api = ref.watch(apiClientProvider);
      return AddressNotifier(api);
    });

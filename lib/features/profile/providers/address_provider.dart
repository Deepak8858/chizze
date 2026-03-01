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

/// Address notifier — API-backed, server-first
class AddressNotifier extends StateNotifier<List<SavedAddress>> {
  final ApiClient _api;
  bool _fetched = false;

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
        _fetched = true;
      }
    } on ApiException {
      // Keep current state
    } catch (e) {
      debugPrint('[Address] fetchAddresses error: $e');
    }
  }

  bool get hasFetched => _fetched;

  SavedAddress _parseDoc(Map<String, dynamic> data, {SavedAddress? fallback}) {
    return SavedAddress(
      id: data['\$id'] ?? fallback?.id ?? '',
      label: data['label'] ?? fallback?.label ?? 'Other',
      fullAddress: data['full_address'] ?? fallback?.fullAddress ?? '',
      landmark: data['landmark'] ?? fallback?.landmark ?? '',
      latitude: (data['latitude'] ?? fallback?.latitude ?? 0).toDouble(),
      longitude: (data['longitude'] ?? fallback?.longitude ?? 0).toDouble(),
      isDefault: data['is_default'] ?? fallback?.isDefault ?? false,
    );
  }

  Map<String, dynamic> _toBody(SavedAddress a) => {
    'label': a.label,
    'full_address': a.fullAddress,
    'landmark': a.landmark,
    'latitude': a.latitude,
    'longitude': a.longitude,
    'is_default': a.isDefault,
  };

  /// Add address — awaits server response. Returns the saved address or null on failure.
  Future<SavedAddress?> addAddress(SavedAddress address) async {
    try {
      final r = await _api.post(ApiConfig.addresses, body: _toBody(address));
      if (r.success && r.data != null) {
        final serverAddress = _parseDoc(r.data as Map<String, dynamic>, fallback: address);
        state = [...state, serverAddress];
        debugPrint('[Address] add success: ${serverAddress.id}');
        return serverAddress;
      }
      debugPrint('[Address] add failed: ${r.error}');
      return null;
    } catch (e) {
      debugPrint('[Address] add error: $e');
      return null;
    }
  }

  /// Remove address — awaits server response. Returns true on success.
  Future<bool> removeAddress(String id) async {
    final prev = List<SavedAddress>.of(state);
    state = state.where((a) => a.id != id).toList();
    try {
      final r = await _api.delete('${ApiConfig.addresses}/$id');
      if (r.success) return true;
      debugPrint('[Address] remove failed: ${r.error}');
      state = prev;
      return false;
    } catch (e) {
      debugPrint('[Address] remove error: $e');
      state = prev;
      return false;
    }
  }

  /// Update address — awaits server response. Returns the updated address or null.
  Future<SavedAddress?> updateAddress(SavedAddress updated) async {
    final old = state.firstWhere((a) => a.id == updated.id, orElse: () => updated);
    state = state.map((a) => a.id == updated.id ? updated : a).toList();
    try {
      final r = await _api.put(
        '${ApiConfig.addresses}/${updated.id}',
        body: {
          'label': updated.label,
          'full_address': updated.fullAddress,
          'landmark': updated.landmark,
          'latitude': updated.latitude,
          'longitude': updated.longitude,
          'is_default': updated.isDefault,
        },
      );
      if (r.success) {
        if (r.data != null) {
          final serverAddr = _parseDoc(r.data as Map<String, dynamic>, fallback: updated);
          state = state.map((a) => a.id == updated.id ? serverAddr : a).toList();
          return serverAddr;
        }
        return updated;
      }
      debugPrint('[Address] update failed: ${r.error}');
      state = state.map((a) => a.id == updated.id ? old : a).toList();
      return null;
    } catch (e) {
      debugPrint('[Address] update error: $e');
      state = state.map((a) => a.id == updated.id ? old : a).toList();
      return null;
    }
  }

  /// Set default address — awaits server confirmation.
  Future<bool> setDefault(String id) async {
    final prev = List<SavedAddress>.of(state);
    state = state.map((a) => a.copyWith(isDefault: a.id == id)).toList();
    final oldDefault = prev.where((a) => a.isDefault && a.id != id).toList();
    try {
      final r = await _api.put('${ApiConfig.addresses}/$id', body: {'is_default': true});
      if (!r.success) {
        debugPrint('[Address] setDefault failed for $id: ${r.error}');
        state = prev;
        return false;
      }
      // Clear old default(s)
      for (final addr in oldDefault) {
        try {
          await _api.put('${ApiConfig.addresses}/${addr.id}', body: {'is_default': false});
        } catch (e) {
          debugPrint('[Address] clear old default error for ${addr.id}: $e');
        }
      }
      return true;
    } catch (e) {
      debugPrint('[Address] setDefault error for $id: $e');
      state = prev;
      return false;
    }
  }

  /// Add address and wait for server response — alias for addAddress.
  /// Use this for flows that need the real server ID (e.g. onboarding, checkout)
  Future<SavedAddress?> addAddressAsync(SavedAddress address) => addAddress(address);
}

final addressProvider =
    StateNotifierProvider<AddressNotifier, List<SavedAddress>>((ref) {
      final api = ref.watch(apiClientProvider);
      return AddressNotifier(api);
    });

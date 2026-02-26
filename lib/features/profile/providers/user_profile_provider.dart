import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';

/// User profile model
class UserProfile {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String? avatarUrl;
  final bool isVeg;
  final bool darkMode;
  final String defaultAddressId;
  final String address;
  final double latitude;
  final double longitude;
  final String role;
  final bool isGoldMember;
  final String referralCode;
  final String referredBy;

  const UserProfile({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    this.avatarUrl,
    this.isVeg = false,
    this.darkMode = true,
    this.defaultAddressId = '',
    this.address = '',
    this.latitude = 0,
    this.longitude = 0,
    this.role = 'customer',
    this.isGoldMember = false,
    this.referralCode = '',
    this.referredBy = '',
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    bool? isVeg,
    bool? darkMode,
    String? defaultAddressId,
    String? address,
    double? latitude,
    double? longitude,
    String? role,
    bool? isGoldMember,
    String? referralCode,
    String? referredBy,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      phone: phone,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVeg: isVeg ?? this.isVeg,
      darkMode: darkMode ?? this.darkMode,
      defaultAddressId: defaultAddressId ?? this.defaultAddressId,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      role: role ?? this.role,
      isGoldMember: isGoldMember ?? this.isGoldMember,
      referralCode: referralCode ?? this.referralCode,
      referredBy: referredBy ?? this.referredBy,
    );
  }

  String get initials {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  static const empty = UserProfile(
    id: '',
    name: '',
    phone: '',
    email: '',
    isVeg: false,
    darkMode: true,
    defaultAddressId: '',
    address: '',
    latitude: 0,
    longitude: 0,
    role: 'customer',
    isGoldMember: false,
    referralCode: '',
    referredBy: '',
  );
}

/// Profile state notifier — fetches from API with mock fallback
class UserProfileNotifier extends StateNotifier<UserProfile> {
  final ApiClient _api;

  static const _keyIsVeg = 'chizze_pref_is_veg';
  static const _keyDarkMode = 'chizze_pref_dark_mode';
  static const _keyDefaultAddress = 'chizze_pref_default_address';

  UserProfileNotifier(this._api) : super(UserProfile.empty) {
    _loadPrefsAndFetch();
  }

  Future<void> _loadPrefsAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      isVeg: prefs.getBool(_keyIsVeg) ?? false,
      darkMode: prefs.getBool(_keyDarkMode) ?? true,
      defaultAddressId: prefs.getString(_keyDefaultAddress) ?? '',
    );
    await fetchProfile();
  }

  /// Fetch profile from API
  Future<void> fetchProfile() async {
    try {
      final response = await _api.get(ApiConfig.profile);
      if (response.success && response.data != null) {
        final d = response.data as Map<String, dynamic>;
        state = UserProfile(
          id: d['\$id'] ?? state.id,
          name: d['name'] ?? state.name,
          phone: d['phone'] ?? state.phone,
          email: d['email'] ?? state.email,
          avatarUrl: d['avatar_url'],
          isVeg: d['is_veg'] ?? state.isVeg,
          darkMode: d['dark_mode'] ?? state.darkMode,
          defaultAddressId: d['default_address_id'] ?? state.defaultAddressId,
          address: d['address'] ?? state.address,
          latitude: (d['latitude'] ?? state.latitude).toDouble(),
          longitude: (d['longitude'] ?? state.longitude).toDouble(),
          role: d['role'] ?? state.role,
          isGoldMember: d['is_gold_member'] ?? state.isGoldMember,
          referralCode: d['referral_code'] ?? state.referralCode,
          referredBy: d['referred_by'] ?? state.referredBy,
        );

        // Sync local prefs with server values
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_keyIsVeg, state.isVeg);
        await prefs.setBool(_keyDarkMode, state.darkMode);
        if (state.defaultAddressId.isNotEmpty) {
          await prefs.setString(_keyDefaultAddress, state.defaultAddressId);
        }
      }
    } on ApiException {
      // Keep current state
    } catch (_) {
      // Keep current state
    }
  }

  Future<bool> updateName(String name) async {
    final oldName = state.name;
    state = state.copyWith(name: name);
    try {
      final r = await _api.put(ApiConfig.profile, body: {'name': name});
      if (!r.success) {
        debugPrint('[Profile] updateName failed: ${r.error}');
        state = state.copyWith(name: oldName);
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[Profile] updateName error: $e');
      state = state.copyWith(name: oldName);
      return false;
    }
  }

  Future<bool> updateEmail(String email) async {
    final oldEmail = state.email;
    state = state.copyWith(email: email);
    try {
      final r = await _api.put(ApiConfig.profile, body: {'email': email});
      if (!r.success) {
        debugPrint('[Profile] updateEmail failed: ${r.error}');
        state = state.copyWith(email: oldEmail);
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[Profile] updateEmail error: $e');
      state = state.copyWith(email: oldEmail);
      return false;
    }
  }

  void toggleVeg() async {
    state = state.copyWith(isVeg: !state.isVeg);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsVeg, state.isVeg);
    // Sync to backend
    _api.put(ApiConfig.profile, body: {'is_veg': state.isVeg}).then((r) {
      if (!r.success) {
        debugPrint('[Profile] toggleVeg sync failed: ${r.error}');
      }
    }).catchError((e) {
      debugPrint('[Profile] toggleVeg sync error: $e');
    });
  }

  void toggleDarkMode() async {
    state = state.copyWith(darkMode: !state.darkMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, state.darkMode);
  }

  void setDefaultAddress(String id) async {
    state = state.copyWith(defaultAddressId: id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultAddress, id);
    // Sync to backend so the default persists across devices / reinstalls
    _api.put(ApiConfig.profile, body: {'default_address_id': id}).then((r) {
      if (!r.success) {
        debugPrint('[Profile] setDefaultAddress sync failed: ${r.error}');
      }
    }).catchError((e) {
      debugPrint('[Profile] setDefaultAddress sync error: $e');
    });
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
      final api = ref.watch(apiClientProvider);
      return UserProfileNotifier(api);
    });

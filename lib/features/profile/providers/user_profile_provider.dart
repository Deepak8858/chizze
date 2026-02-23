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

  const UserProfile({
    required this.id,
    required this.name,
    required this.phone,
    this.email = '',
    this.avatarUrl,
    this.isVeg = false,
    this.darkMode = true,
    this.defaultAddressId = '',
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    bool? isVeg,
    bool? darkMode,
    String? defaultAddressId,
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
          isVeg: d['dietary_preferences']?.contains('veg') ?? false,
          darkMode: state.darkMode,
          defaultAddressId: state.defaultAddressId,
        );
      }
    } on ApiException {
      // Keep current state
    } catch (_) {
      // Keep current state
    }
  }

  void updateName(String name) {
    final oldName = state.name;
    state = state.copyWith(name: name);
    _api.put(ApiConfig.profile, body: {'name': name}).then((r) {
      if (!r.success) {
        debugPrint('[Profile] updateName failed: ${r.error}');
        state = state.copyWith(name: oldName);
      }
    }).catchError((e) {
      debugPrint('[Profile] updateName error: $e');
      state = state.copyWith(name: oldName);
    });
  }

  void updateEmail(String email) {
    final oldEmail = state.email;
    state = state.copyWith(email: email);
    _api.put(ApiConfig.profile, body: {'email': email}).then((r) {
      if (!r.success) {
        debugPrint('[Profile] updateEmail failed: ${r.error}');
        state = state.copyWith(email: oldEmail);
      }
    }).catchError((e) {
      debugPrint('[Profile] updateEmail error: $e');
      state = state.copyWith(email: oldEmail);
    });
  }

  void toggleVeg() async {
    state = state.copyWith(isVeg: !state.isVeg);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsVeg, state.isVeg);
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
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
      final api = ref.watch(apiClientProvider);
      return UserProfileNotifier(api);
    });

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  static const mock = UserProfile(
    id: 'u1',
    name: 'Arjun Reddy',
    phone: '+919876543210',
    email: 'arjun@example.com',
    isVeg: false,
    darkMode: true,
    defaultAddressId: 'addr1',
  );
}

/// Profile state notifier — fetches from API with mock fallback
class UserProfileNotifier extends StateNotifier<UserProfile> {
  final ApiClient _api;

  UserProfileNotifier(this._api) : super(UserProfile.mock) {
    fetchProfile();
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
      // Keep mock data as fallback
    } catch (_) {
      // Keep mock data
    }
  }

  void updateName(String name) {
    state = state.copyWith(name: name);
    _api.put(ApiConfig.profile, body: {'name': name}).ignore();
  }

  void updateEmail(String email) {
    state = state.copyWith(email: email);
    _api.put(ApiConfig.profile, body: {'email': email}).ignore();
  }

  void toggleVeg() {
    state = state.copyWith(isVeg: !state.isVeg);
  }

  void toggleDarkMode() => state = state.copyWith(darkMode: !state.darkMode);

  void setDefaultAddress(String id) =>
      state = state.copyWith(defaultAddressId: id);
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
      final api = ref.watch(apiClientProvider);
      return UserProfileNotifier(api);
    });

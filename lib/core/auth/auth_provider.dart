import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/appwrite_service.dart';
import '../services/api_client.dart';

/// Secure storage keys for persisted auth data
const _kRoleStorageKey = 'chizze_user_role';
const _kOnboardedKey = 'chizze_onboarded';

/// Auth state — represents the current user's authentication state
enum AuthStatus { initial, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final models.User? user;
  final String? error;
  final bool isLoading;
  final String userRole; // 'customer' | 'restaurant_owner' | 'delivery_partner'
  final bool isNewUser; // true when user just signed up, needs onboarding
  final String selectedRole; // role picked on role-selection screen (before login)

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.error,
    this.isLoading = false,
    this.userRole = 'customer',
    this.isNewUser = false,
    this.selectedRole = 'customer',
  });

  AuthState copyWith({
    AuthStatus? status,
    models.User? user,
    String? error,
    bool? isLoading,
    String? userRole,
    bool? isNewUser,
    String? selectedRole,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
      isLoading: isLoading ?? this.isLoading,
      userRole: userRole ?? this.userRole,
      isNewUser: isNewUser ?? this.isNewUser,
      selectedRole: selectedRole ?? this.selectedRole,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isPartner => userRole == 'restaurant_owner';
  bool get isDeliveryPartner => userRole == 'delivery_partner';
  bool get needsOnboarding => isNewUser;
}

/// Auth Notifier — manages login, signup, logout, session checks
class AuthNotifier extends StateNotifier<AuthState> {
  final Account _account;
  final ApiClient _apiClient;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  AuthNotifier(this._account, this._apiClient) : super(const AuthState()) {
    // Set up auto-refresh: when 401 is received, re-exchange the Appwrite JWT
    _apiClient.setRefreshCallback(() async {
      try {
        final jwt = await _account.createJWT();
        final response = await _apiClient.post<Map<String, dynamic>>(
          '/auth/exchange',
          body: {'jwt': jwt.jwt},
        );
        final token = response.data?['token'] as String?;
        if (token != null) {
          debugPrint('[Auth] Token refreshed via interceptor');
          await _apiClient.persistToken(token);
          return token;
        }
      } catch (e) {
        debugPrint('[Auth] Refresh via interceptor failed: $e');
      }
      return null;
    });
    checkSession();
  }

  /// Exchange Appwrite JWT for Go backend JWT
  /// Exchange Appwrite JWT for Go backend JWT.
  /// Throws on failure — callers decide whether to treat it as fatal.
  Future<void> _exchangeToken() async {
    final jwt = await _account.createJWT();
    debugPrint('[Auth] Got Appwrite JWT, exchanging with backend...');
    // Clear any stale backend token before exchange (exchange is a public endpoint)
    _apiClient.clearAuthToken();
    final body = <String, dynamic>{'jwt': jwt.jwt};
    // Always send selected role to backend (including 'customer')
    body['role'] = state.selectedRole;
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/auth/exchange',
      body: body,
    );
    final token = response.data?['token'] as String?;
    final role = response.data?['role'] as String? ?? 'customer';
    final isNew = response.data?['is_new'] as bool? ?? false;
    if (token != null) {
      _apiClient.setAuthToken(token);
      await _apiClient.persistToken(token);
      await _persistRole(role);
      // Sync onboarded flag based on backend's is_new determination.
      // Backend checks for role-specific records, so is_new=true means
      // onboarding is genuinely needed even for migrated/returning users.
      if (isNew) {
        await _secureStorage.delete(key: _kOnboardedKey);
      } else {
        await _secureStorage.write(key: _kOnboardedKey, value: 'true');
      }
      state = state.copyWith(
        userRole: role,
        isNewUser: isNew,
      );
      debugPrint('[Auth] Backend JWT set & persisted, role=$role, isNew=$isNew');
    } else {
      throw Exception('Backend returned no token');
    }
  }

  /// Persist the user role locally
  Future<void> _persistRole(String role) async {
    try {
      await _secureStorage.write(key: _kRoleStorageKey, value: role);
    } catch (_) {}
  }

  /// Load persisted role
  Future<String?> _loadPersistedRole() async {
    try {
      return await _secureStorage.read(key: _kRoleStorageKey);
    } catch (_) {
      return null;
    }
  }

  /// Check if user has an active session
  Future<void> checkSession() async {
    debugPrint('[Auth] checkSession() started');
    state = state.copyWith(isLoading: true);
    try {
      final user = await _account.get().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[Auth] Appwrite account.get() timed out after 10s');
          throw TimeoutException('Session check timed out');
        },
      );
      debugPrint('[Auth] Session found for user: ${user.name} (${user.$id})');

      // Try to restore persisted backend JWT & role (faster than exchange)
      final persisted = await _apiClient.loadPersistedToken();
      final persistedRole = await _loadPersistedRole();
      final onboarded = await _secureStorage.read(key: _kOnboardedKey);

      if (persisted != null && persistedRole != null) {
        // Fast path: have persisted token & role — set everything atomically
        debugPrint('[Auth] Using persisted JWT, role=$persistedRole, onboarded=$onboarded');
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          isLoading: false,
          userRole: persistedRole,
          isNewUser: onboarded != 'true',
        );
      } else {
        // Slow path: exchange token first to get correct role, THEN set authenticated
        state = state.copyWith(user: user);
        await _exchangeToken();
        state = state.copyWith(
          status: AuthStatus.authenticated,
          isLoading: false,
        );
      }
    } catch (e) {
      debugPrint('[Auth] No active session: $e');
      // Clear any stale persisted token
      await _apiClient.clearPersistedToken();
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
      );
    }
  }

  /// Login with email & password
  Future<void> loginWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _account.createEmailPasswordSession(
        email: email,
        password: password,
      );
      final user = await _account.get();
      // Exchange token FIRST to get correct role/isNew, THEN set authenticated
      state = state.copyWith(user: user);
      await _exchangeToken();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        isLoading: false,
      );
    } on AppwriteException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message ?? 'Login failed',
      );
    } catch (e) {
      debugPrint('[Auth] Login failed (exchange): $e');
      // Clean up the Appwrite session since we can't complete login
      try { await _account.deleteSession(sessionId: 'current'); } catch (_) {}
      state = state.copyWith(
        isLoading: false,
        error: 'Server unavailable. Please try again.',
      );
    }
  }

  /// Register with email & password
  Future<void> registerWithEmail(
    String name,
    String email,
    String password,
  ) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _account.create(
        userId: ID.unique(),
        name: name,
        email: email,
        password: password,
      );
      // Auto-login after registration
      await loginWithEmail(email, password);
    } on AppwriteException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message ?? 'Registration failed',
      );
    }
  }

  /// Login with phone OTP — Step 1: Send OTP
  Future<String?> sendPhoneOTP(String phone) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      debugPrint('[Auth] sendPhoneOTP: sending OTP to $phone');
      final token = await _account.createPhoneToken(
        userId: ID.unique(),
        phone: phone,
      );
      debugPrint('[Auth] sendPhoneOTP: success, userId=${token.userId}');
      state = state.copyWith(isLoading: false);
      return token.userId;
    } on AppwriteException catch (e) {
      debugPrint('[Auth] sendPhoneOTP: failed — ${e.message} (${e.code})');
      state = state.copyWith(
        isLoading: false,
        error: e.message ?? 'Failed to send OTP',
      );
      return null;
    }
  }

  /// Login with phone OTP — Step 2: Verify OTP
  Future<void> verifyPhoneOTP(String userId, String otp) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      debugPrint('[Auth] verifyPhoneOTP: verifying userId=$userId');
      await _account.createSession(userId: userId, secret: otp);
      final user = await _account.get();
      if (kDebugMode) {
        debugPrint('[Auth] verifyPhoneOTP: success, user=${user.name} (${user.$id})');
      }
      // Exchange token FIRST to get correct role/isNew, THEN set authenticated
      state = state.copyWith(user: user);
      await _exchangeToken();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        isLoading: false,
      );
    } on AppwriteException catch (e) {
      debugPrint('[Auth] verifyPhoneOTP: failed — ${e.message} (${e.code})');
      state = state.copyWith(
        isLoading: false,
        error: e.message ?? 'Invalid OTP',
      );    } catch (e) {
      debugPrint('[Auth] verifyPhoneOTP exchange failed: $e');
      // Clean up the Appwrite session since we can't complete login
      try { await _account.deleteSession(sessionId: 'current'); } catch (_) {}
      state = state.copyWith(
        isLoading: false,
        error: 'Server unavailable. Please try again.',
      );    }
  }

  /// OAuth login (Google, Apple)
  Future<void> loginWithOAuth(OAuthProvider provider) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _account.createOAuth2Session(provider: provider);
      final user = await _account.get();
      // Exchange token FIRST to get correct role/isNew, THEN set authenticated
      state = state.copyWith(user: user);
      await _exchangeToken();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        isLoading: false,
      );
    } on AppwriteException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message ?? 'OAuth login failed',
      );
    } catch (e) {
      debugPrint('[Auth] OAuth login exchange failed: $e');
      try { await _account.deleteSession(sessionId: 'current'); } catch (_) {}
      state = state.copyWith(
        isLoading: false,
        error: 'Server unavailable. Please try again.',
      );
    }
  }

  /// Set the role the user selected on the role selection screen (before login)
  void setSelectedRole(String role) {
    if (state.selectedRole == role) return; // no-op if already set
    state = state.copyWith(selectedRole: role);
    debugPrint('[Auth] Selected role set to: $role');
  }

  /// Complete onboarding — save profile + role-specific data to backend, mark as onboarded
  Future<void> completeOnboarding({
    required String name,
    String? email,
    String? address,
    String? city,
    double? latitude,
    double? longitude,
    bool? isVeg,
    // Restaurant-specific
    String? restaurantName,
    String? restaurantAddress,
    String? cuisineType,
    // Delivery-specific
    String? vehicleType,
    String? vehicleNumber,
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name,
      };
      if (email != null && email.isNotEmpty) {
        body['email'] = email;
      }
      if (address != null && address.isNotEmpty) {
        body['address'] = address;
      }
      if (city != null && city.isNotEmpty) {
        body['city'] = city;
      }
      if (latitude != null && longitude != null) {
        body['latitude'] = latitude;
        body['longitude'] = longitude;
      }
      if (isVeg != null) {
        body['is_veg'] = isVeg;
      }

      // Role-specific fields
      if (state.userRole == 'restaurant_owner') {
        if (restaurantName != null && restaurantName.isNotEmpty) {
          body['restaurant_name'] = restaurantName;
        }
        if (restaurantAddress != null && restaurantAddress.isNotEmpty) {
          body['restaurant_address'] = restaurantAddress;
        }
        if (cuisineType != null && cuisineType.isNotEmpty) {
          body['cuisine_type'] = cuisineType;
        }
      } else if (state.userRole == 'delivery_partner') {
        if (vehicleType != null && vehicleType.isNotEmpty) {
          body['vehicle_type'] = vehicleType;
        }
        if (vehicleNumber != null && vehicleNumber.isNotEmpty) {
          body['vehicle_number'] = vehicleNumber;
        }
      }

      await _apiClient.post<Map<String, dynamic>>(
        '/auth/onboard',
        body: body,
      );
      debugPrint('[Auth] Onboarding profile saved via /auth/onboard');

      // For customers, auto-create a saved address from onboarding data
      if (state.userRole == 'customer' && address != null && address.isNotEmpty) {
        try {
          await _apiClient.post(
            '/users/me/addresses',
            body: {
              'label': 'Home',
              'full_address': address,
              'landmark': '',
              'latitude': latitude ?? 0,
              'longitude': longitude ?? 0,
              'is_default': true,
            },
          );
          debugPrint('[Auth] Auto-created saved address from onboarding');
        } catch (e) {
          debugPrint('[Auth] Auto-create saved address failed (non-critical): $e');
        }
      }

      // Mark as onboarded locally ONLY after successful API call
      await _secureStorage.write(key: _kOnboardedKey, value: 'true');
      state = state.copyWith(isNewUser: false);
      debugPrint('[Auth] Onboarding complete');
    } catch (e) {
      debugPrint('[Auth] Onboarding save failed: $e');
      rethrow; // Let caller show error — do NOT mark as onboarded
    }
  }

  /// Logout
  Future<void> logout() async {
    debugPrint('[Auth] logout() called');
    state = state.copyWith(isLoading: true);

    // Blacklist JWT on Go backend (best-effort)
    try {
      await _apiClient.delete('/auth/logout');
      debugPrint('[Auth] Backend logout successful (JWT blacklisted)');
    } catch (e) {
      debugPrint('[Auth] Backend logout failed (non-critical): $e');
    }

    // Delete Appwrite session
    try {
      await _account.deleteSession(sessionId: 'current');
      debugPrint('[Auth] Appwrite session deleted');
    } catch (e) {
      debugPrint('[Auth] Session delete error (may be expired): $e');
    }
    _apiClient.clearAuthToken();
    await _apiClient.clearPersistedToken();
    // Clear persisted role and onboarded flag
    try {
      await _secureStorage.delete(key: _kRoleStorageKey);
      await _secureStorage.delete(key: _kOnboardedKey);
    } catch (_) {}
    state = const AuthState(status: AuthStatus.unauthenticated);
    debugPrint('[Auth] State set to unauthenticated');
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Auth provider — global auth state for the entire app
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final account = ref.watch(appwriteAccountProvider);
  final apiClient = ref.watch(apiClientProvider);
  return AuthNotifier(account, apiClient);
});

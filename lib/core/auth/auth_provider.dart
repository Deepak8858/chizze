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
  Future<void> _exchangeToken() async {
    try {
      final jwt = await _account.createJWT();
      debugPrint('[Auth] Got Appwrite JWT, exchanging with backend...');
      final body = <String, dynamic>{'jwt': jwt.jwt};
      // If user selected a specific role (from role selection screen), send it
      if (state.selectedRole != 'customer') {
        body['role'] = state.selectedRole;
      }
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
        // Check onboarded flag
        final onboarded = await _secureStorage.read(key: _kOnboardedKey);
        state = state.copyWith(
          userRole: role,
          isNewUser: isNew || onboarded != 'true',
        );
        debugPrint('[Auth] Backend JWT set & persisted, role=$role, isNew=$isNew');
      }
    } catch (e) {
      debugPrint('[Auth] Token exchange failed: $e');
      // Non-fatal — Appwrite session still valid, backend calls will fail
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
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isLoading: false,
      );
      // Try to restore persisted backend JWT first (faster than exchange)
      final persisted = await _apiClient.loadPersistedToken();
      final persistedRole = await _loadPersistedRole();
      final onboarded = await _secureStorage.read(key: _kOnboardedKey);
      if (persistedRole != null) {
        state = state.copyWith(
          userRole: persistedRole,
          isNewUser: onboarded != 'true',
        );
        debugPrint('[Auth] Restored persisted role=$persistedRole, onboarded=$onboarded');
      }
      if (persisted == null) {
        // No persisted token — do a full exchange
        await _exchangeToken();
      } else {
        debugPrint('[Auth] Using persisted backend JWT');
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
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isLoading: false,
      );
      await _exchangeToken();
    } on AppwriteException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message ?? 'Login failed',
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
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isLoading: false,
      );
      await _exchangeToken();
    } on AppwriteException catch (e) {
      debugPrint('[Auth] verifyPhoneOTP: failed — ${e.message} (${e.code})');
      state = state.copyWith(
        isLoading: false,
        error: e.message ?? 'Invalid OTP',
      );
    }
  }

  /// OAuth login (Google, Apple)
  Future<void> loginWithOAuth(OAuthProvider provider) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _account.createOAuth2Session(provider: provider);
      final user = await _account.get();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isLoading: false,
      );
      await _exchangeToken();
    } on AppwriteException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message ?? 'OAuth login failed',
      );
    }
  }

  /// Set the role the user selected on the role selection screen (before login)
  void setSelectedRole(String role) {
    if (state.selectedRole == role) return; // no-op if already set
    state = state.copyWith(selectedRole: role);
    debugPrint('[Auth] Selected role set to: $role');
  }

  /// Complete onboarding — save name + address to backend, mark as onboarded
  Future<void> completeOnboarding({
    required String name,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name,
        'role': state.userRole,
      };
      if (address != null && address.isNotEmpty) {
        body['address'] = address;
      }
      if (latitude != null && longitude != null) {
        body['latitude'] = latitude;
        body['longitude'] = longitude;
      }

      await _apiClient.put<Map<String, dynamic>>(
        '/users/me',
        body: body,
      );
      debugPrint('[Auth] Onboarding profile saved');
    } catch (e) {
      debugPrint('[Auth] Onboarding profile save failed (non-fatal): $e');
    }

    // Mark as onboarded locally
    await _secureStorage.write(key: _kOnboardedKey, value: 'true');
    state = state.copyWith(isNewUser: false);
    debugPrint('[Auth] Onboarding complete');
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

import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/appwrite_service.dart';
import '../services/api_client.dart';
import '../services/facebook_service.dart';
import '../models/api_response.dart';

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
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  String _roleDisplayName(String role) {
    switch (role) {
      case 'restaurant_owner':
        return 'Restaurant Partner';
      case 'delivery_partner':
        return 'Delivery Partner';
      case 'customer':
        return 'Customer';
      default:
        return 'selected role';
    }
  }

  String? _extractRoleLabelFromMessage(String lowerCaseMessage) {
    if (lowerCaseMessage.contains('restaurant partner') ||
        lowerCaseMessage.contains('restaurant_owner')) {
      return 'Restaurant Partner';
    }
    if (lowerCaseMessage.contains('delivery partner') ||
        lowerCaseMessage.contains('delivery_partner')) {
      return 'Delivery Partner';
    }
    if (lowerCaseMessage.contains('customer')) {
      return 'Customer';
    }
    return null;
  }

  bool _looksLikeNetworkIssue(String lowerCaseMessage) {
    return lowerCaseMessage.contains('socketexception') ||
        lowerCaseMessage.contains('failed host lookup') ||
        lowerCaseMessage.contains('network') ||
        lowerCaseMessage.contains('connection') ||
        lowerCaseMessage.contains('timed out') ||
        lowerCaseMessage.contains('timeout') ||
        lowerCaseMessage.contains('dns') ||
        lowerCaseMessage.contains('handshakeexception');
  }

  String _friendlyApiError(ApiException e) {
    final raw = e.message.trim();
    final lower = raw.toLowerCase();

    if (e.statusCode == 0 || _looksLikeNetworkIssue(lower)) {
      return 'Unable to connect right now. Please check your internet connection and try again.';
    }

    if (e.statusCode == 409 && lower.contains('already registered as')) {
      final roleLabel = _extractRoleLabelFromMessage(lower) ?? 'another role';
      return 'This phone number is already registered as $roleLabel. Please choose $roleLabel on the role selection screen, or use a different phone number.';
    }

    if (e.statusCode == 403 &&
        lower.contains('signups are currently disabled')) {
      final roleLabel = _extractRoleLabelFromMessage(lower) ?? 'partner';
      return 'New $roleLabel sign-ups are temporarily unavailable. Please try a different role or contact support.';
    }

    if (e.statusCode == 401) {
      return 'Your session has expired. Please sign in again.';
    }

    if (e.statusCode == 429) {
      return 'Too many attempts. Please wait a few minutes and try again.';
    }

    if (e.statusCode >= 500) {
      return 'Our servers are temporarily unavailable. Please try again in a moment.';
    }

    if (raw.isEmpty || lower == 'request failed') {
      return 'We could not complete your request. Please try again.';
    }

    return raw;
  }

  String _friendlyAppwriteError(AppwriteException e, {required String action}) {
    final raw = (e.message ?? '').trim();
    final lower = raw.toLowerCase();
    final code = e.code ?? 0;

    if (_looksLikeNetworkIssue(lower)) {
      return 'Unable to connect right now. Please check your internet connection and try again.';
    }

    final isRateLimited =
        code == 429 ||
        lower.contains('too many') ||
        lower.contains('rate limit');
    if (isRateLimited) {
      if (action == 'verifyOtp') {
        return 'Too many OTP verification attempts. Please wait a few minutes and request a new OTP.';
      }
      return 'Too many requests right now. Please wait a few minutes and try again.';
    }

    if (action == 'sendOtp') {
      if (code == 400 || lower.contains('phone') || lower.contains('invalid')) {
        return 'Please enter a valid 10-digit mobile number (for example, 9876543210).';
      }
      return 'We could not send an OTP right now. Please try again.';
    }

    if (action == 'verifyOtp') {
      if (code == 401 ||
          code == 403 ||
          lower.contains('invalid') ||
          lower.contains('otp') ||
          lower.contains('secret') ||
          lower.contains('expired')) {
        return 'Incorrect or expired OTP. Please enter the latest 6-digit code and try again.';
      }
      if (code == 404 ||
          lower.contains('session') ||
          lower.contains('not found')) {
        return 'Your login session expired. Please request a new OTP and try again.';
      }
      return 'We could not verify the OTP. Please try again.';
    }

    if (action == 'emailLogin') {
      if (code == 401 ||
          lower.contains('invalid credentials') ||
          lower.contains('password')) {
        return 'Incorrect email or password. Please try again.';
      }
      return 'Unable to sign in with email right now. Please try again.';
    }

    if (action == 'oauthLogin') {
      if (lower.contains('cancel')) {
        return 'Sign-in was cancelled. Please try again when you are ready.';
      }
      return 'Unable to complete social sign-in right now. Please try again.';
    }

    if (action == 'register') {
      if (code == 409 || lower.contains('already')) {
        return 'An account with this email already exists. Please sign in instead.';
      }
      return 'We could not create your account right now. Please try again.';
    }

    if (raw.isNotEmpty) {
      return raw;
    }
    return 'Something went wrong. Please try again.';
  }

  /// Checks whether the phone is already registered and, if so, whether the
  /// registered role matches the selected role.
  ///
  /// Returns null when the caller may proceed, or an error string to surface.
  Future<String?> _checkPhoneRoleConflict(String phone) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/auth/check-phone',
        body: {'phone': phone},
      );
      final data = response.data;
      if (data == null || data['exists'] != true) return null;

      final registeredRole = (data['role'] as String?)?.trim();
      if (registeredRole == null ||
          registeredRole.isEmpty ||
          registeredRole == state.selectedRole) {
        return null;
      }

      final registeredRoleLabel = _roleDisplayName(registeredRole);
      final selectedRoleLabel = _roleDisplayName(state.selectedRole);
      return 'This phone number is already registered as $registeredRoleLabel. '
          'You selected $selectedRoleLabel. Please go back and continue as '
          '$registeredRoleLabel, or use a different phone number.';
    } on ApiException {
      // Pre-check is non-blocking. If unavailable, continue normal OTP flow.
      return null;
    } catch (_) {
      return null;
    }
  }

  AuthNotifier(this._account, this._apiClient) : super(const AuthState()) {
    // Set up forced-logout callback: when token refresh fails unrecoverably
    _apiClient.setAuthFailureCallback(() {
      if (state.isAuthenticated) {
        logout();
      }
    });

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
          if (kDebugMode) debugPrint('[Auth] Token refreshed via interceptor');
          await _apiClient.persistToken(token);
          return token;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Auth] Refresh via interceptor failed: $e');
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
    if (kDebugMode) {
      debugPrint('[Auth] Got Appwrite JWT, exchanging with backend...');
    }
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
      if (kDebugMode) {
        debugPrint(
          '[Auth] Backend JWT set & persisted, role=$role, isNew=$isNew',
        );
      }
    } else {
      throw Exception('Backend returned no token');
    }
  }

  /// Persist the user role locally
  Future<void> _persistRole(String role) async {
    try {
      await _secureStorage.write(key: _kRoleStorageKey, value: role);
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] persistRole error: $e');
    }
  }

  /// Load persisted role
  Future<String?> _loadPersistedRole() async {
    try {
      return await _secureStorage.read(key: _kRoleStorageKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] loadPersistedRole error: $e');
      return null;
    }
  }

  /// Check if user has an active session
  Future<void> checkSession() async {
    if (kDebugMode) debugPrint('[Auth] checkSession() started');
    state = state.copyWith(isLoading: true);
    try {
      final user = await _account.get().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('[Auth] Appwrite account.get() timed out after 10s');
          }
          throw TimeoutException('Session check timed out');
        },
      );
      if (kDebugMode) {
        debugPrint('[Auth] Session found for user: ${user.name} (${user.$id})');
      }

      // Try to restore persisted backend JWT & role (faster than exchange)
      final persisted = await _apiClient.loadPersistedToken();
      final persistedRole = await _loadPersistedRole();
      final onboarded = await _secureStorage.read(key: _kOnboardedKey);

      if (persisted != null && persistedRole != null) {
        // Fast path: have persisted token & role — set everything atomically
        if (kDebugMode) {
          debugPrint(
            '[Auth] Using persisted JWT, role=$persistedRole, onboarded=$onboarded',
          );
        }
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
      if (kDebugMode) debugPrint('[Auth] checkSession error: $e');

      // Determine if this is a network/connectivity error vs a genuine
      // "no session" response from Appwrite.
      final errStr = e.toString();
      final isNetworkError =
          e is TimeoutException ||
          errStr.contains('SocketException') ||
          errStr.contains('Failed host lookup') ||
          errStr.contains('Connection refused') ||
          errStr.contains('Network is unreachable') ||
          errStr.contains('HandshakeException') ||
          errStr.contains('Connection closed') ||
          errStr.contains('Connection reset') ||
          errStr.contains('timed out');

      if (isNetworkError) {
        // Network is down — try to restore from local storage so the user
        // stays logged in and can browse cached content.
        final persisted = await _apiClient.loadPersistedToken();
        final persistedRole = await _loadPersistedRole();
        final onboarded = await _secureStorage.read(key: _kOnboardedKey);

        if (persisted != null && persistedRole != null) {
          if (kDebugMode) {
            debugPrint(
            '[Auth] Offline mode: restoring session from local storage (role=$persistedRole)',
          );
          }
          state = state.copyWith(
            status: AuthStatus.authenticated,
            isLoading: false,
            userRole: persistedRole,
            isNewUser: onboarded != 'true',
          );
          return;
        }
      }

      // Genuinely no session or no persisted data — clear and go to login
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
        error: _friendlyAppwriteError(e, action: 'emailLogin'),
      );
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[Auth] Login failed (exchange): $e');
      try {
        await _account.deleteSession(sessionId: 'current');
      } catch (_) {}
      state = state.copyWith(isLoading: false, error: _friendlyApiError(e));
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Login failed (exchange): $e');
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
        error: _friendlyAppwriteError(e, action: 'register'),
      );
    }
  }

  /// Login with phone OTP — Step 1: Send OTP
  Future<String?> sendPhoneOTP(String phone, {String? userId}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final roleConflictError = await _checkPhoneRoleConflict(phone);
      if (roleConflictError != null) {
        state = state.copyWith(isLoading: false, error: roleConflictError);
        return null;
      }

      if (kDebugMode) debugPrint('[Auth] sendPhoneOTP: sending OTP to $phone');
      final token = await _account.createPhoneToken(
        userId: userId ?? ID.unique(),
        phone: phone,
      );
      if (kDebugMode) {
        debugPrint('[Auth] sendPhoneOTP: success, userId=${token.userId}');
      }
      state = state.copyWith(isLoading: false);
      return token.userId;
    } on AppwriteException catch (e) {
      if (kDebugMode) {
        debugPrint('[Auth] sendPhoneOTP: failed — ${e.message} (${e.code})');
      }
      state = state.copyWith(
        isLoading: false,
        error: _friendlyAppwriteError(e, action: 'sendOtp'),
      );
      return null;
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: _friendlyApiError(e));
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] sendPhoneOTP: unexpected error — $e');
      state = state.copyWith(
        isLoading: false,
        error: 'We could not send an OTP right now. Please try again.',
      );
      return null;
    }
  }

  /// Login with phone OTP — Step 2: Verify OTP
  Future<void> verifyPhoneOTP(String userId, String otp) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      if (kDebugMode) {
        debugPrint('[Auth] verifyPhoneOTP: verifying userId=$userId');
      }
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
      // FB App Events: track registration so FB Ads can attribute installs.
      // isNewUser flag is set by _exchangeToken based on backend response.
      if (state.isNewUser) {
        unawaited(FacebookService.instance.logCompletedRegistration(method: 'phone_otp'));
      }
    } on AppwriteException catch (e) {
      if (kDebugMode) {
        debugPrint('[Auth] verifyPhoneOTP: failed — ${e.message} (${e.code})');
      }
      state = state.copyWith(
        isLoading: false,
        error: _friendlyAppwriteError(e, action: 'verifyOtp'),
      );
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[Auth] verifyPhoneOTP exchange failed: $e');
      try {
        await _account.deleteSession(sessionId: 'current');
      } catch (_) {}
      state = state.copyWith(isLoading: false, error: _friendlyApiError(e));
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] verifyPhoneOTP exchange failed: $e');
      // Clean up the Appwrite session since we can't complete login
      try { await _account.deleteSession(sessionId: 'current'); } catch (_) {}
      state = state.copyWith(
        isLoading: false,
        error: 'Server unavailable. Please try again.',
      );
    }
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
        error: _friendlyAppwriteError(e, action: 'oauthLogin'),
      );
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[Auth] OAuth login exchange failed: $e');
      try {
        await _account.deleteSession(sessionId: 'current');
      } catch (_) {}
      state = state.copyWith(isLoading: false, error: _friendlyApiError(e));
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] OAuth login exchange failed: $e');
      try { await _account.deleteSession(sessionId: 'current'); } catch (_) {}
      state = state.copyWith(
        isLoading: false,
        error: 'Server unavailable. Please try again.',
      );
    }
  }

  /// Facebook Login. Two-step: (1) native FB SDK gets access token for Ads
  /// attribution + App Events matching, (2) Appwrite OAuth creates the actual
  /// session + backend JWT exchange via the existing OAuth path.
  ///
  /// We call the native SDK first because FB's attribution model depends on
  /// seeing a native login event to deduplicate installs vs. organic users.
  /// Failure of the native step is non-fatal — Appwrite OAuth still runs.
  Future<void> loginWithFacebook() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Best-effort native SDK login for Ads attribution. Token result is
      // not used here because Appwrite handles the actual session.
      await FacebookService.instance.signIn();
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] FB SDK pre-step failed (continuing): $e');
    }
    // Delegate to the shared OAuth path — same exchange + role handling.
    await loginWithOAuth(OAuthProvider.facebook);
    if (state.status == AuthStatus.authenticated) {
      unawaited(FacebookService.instance.logCompletedRegistration(method: 'facebook'));
    }
  }

  /// Set the role the user selected on the role selection screen (before login)
  void setSelectedRole(String role) {
    if (state.selectedRole == role) return; // no-op if already set
    state = state.copyWith(selectedRole: role);
    if (kDebugMode) debugPrint('[Auth] Selected role set to: $role');
  }

  /// Complete onboarding — save profile + role-specific data to backend, mark as onboarded
  Future<void> completeOnboarding({
    required String name,
    String? email,
    String? phone,
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
      if (phone != null && phone.isNotEmpty) {
        body['phone'] = phone;
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
      if (kDebugMode) {
        debugPrint('[Auth] Onboarding profile saved via /auth/onboard');
      }

      // For customers, auto-create a saved address from onboarding data
      if (state.userRole == 'customer' && address != null && address.isNotEmpty) {
        try {
          final hasValidCoords =
              latitude != null &&
              longitude != null &&
              latitude >= -90 &&
              latitude <= 90 &&
              longitude >= -180 &&
              longitude <= 180 &&
              (latitude != 0 || longitude != 0);

          final body = <String, dynamic>{
            'label': 'Home',
            'full_address': address,
            'landmark': '',
            'is_default': true,
          };
          if (hasValidCoords) {
            body['latitude'] = latitude;
            body['longitude'] = longitude;
          }

          await _apiClient.post('/users/me/addresses', body: body);
          if (kDebugMode) {
            debugPrint('[Auth] Auto-created saved address from onboarding');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[Auth] Auto-create saved address failed (non-critical): $e',
            );
          }
        }
      }

      // Mark as onboarded locally ONLY after successful API call
      await _secureStorage.write(key: _kOnboardedKey, value: 'true');
      state = state.copyWith(isNewUser: false);
      if (kDebugMode) debugPrint('[Auth] Onboarding complete');
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[Auth] Onboarding save failed (API): $e');
      // Convert to a friendly message so callers don't see raw exception text.
      throw Exception(_friendlyApiError(e));
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Onboarding save failed: $e');
      final msg = e.toString();
      // If already a converted Exception with a friendly message, pass through.
      // Otherwise check for known error patterns.
      if (_looksLikeNetworkIssue(msg.toLowerCase())) {
        throw Exception(
          'Unable to connect right now. Please check your internet connection and try again.',
        );
      }
      rethrow; // Let caller show error — do NOT mark as onboarded
    }
  }

  /// Logout
  Future<void> logout() async {
    if (kDebugMode) debugPrint('[Auth] logout() called');
    state = state.copyWith(isLoading: true);

    // Blacklist JWT on Go backend (best-effort)
    try {
      await _apiClient.delete('/auth/logout');
      if (kDebugMode) {
        debugPrint('[Auth] Backend logout successful (JWT blacklisted)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Auth] Backend logout failed (non-critical): $e');
      }
    }

    // Delete Appwrite session
    try {
      await _account.deleteSession(sessionId: 'current');
      if (kDebugMode) debugPrint('[Auth] Appwrite session deleted');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Auth] Session delete error (may be expired): $e');
      }
    }
    _apiClient.clearAuthToken();
    await _apiClient.clearPersistedToken();
    // Clear persisted role and onboarded flag
    try {
      await _secureStorage.delete(key: _kRoleStorageKey);
      await _secureStorage.delete(key: _kOnboardedKey);
    } catch (_) {}
    state = const AuthState(status: AuthStatus.unauthenticated);
    if (kDebugMode) debugPrint('[Auth] State set to unauthenticated');
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

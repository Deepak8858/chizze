import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/appwrite_service.dart';

/// Auth state — represents the current user's authentication state
enum AuthStatus { initial, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final models.User? user;
  final String? error;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    models.User? user,
    String? error,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

/// Auth Notifier — manages login, signup, logout, session checks
class AuthNotifier extends StateNotifier<AuthState> {
  final Account _account;

  AuthNotifier(this._account) : super(const AuthState()) {
    checkSession();
  }

  /// Check if user has an active session
  Future<void> checkSession() async {
    state = state.copyWith(isLoading: true);
    try {
      final user = await _account.get();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isLoading: false,
      );
    } catch (e) {
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
      final token = await _account.createPhoneToken(
        userId: ID.unique(),
        phone: phone,
      );
      state = state.copyWith(isLoading: false);
      return token.userId;
    } on AppwriteException catch (e) {
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
      await _account.createSession(userId: userId, secret: otp);
      final user = await _account.get();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isLoading: false,
      );
    } on AppwriteException catch (e) {
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
    } on AppwriteException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message ?? 'OAuth login failed',
      );
    }
  }

  /// Logout
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      await _account.deleteSession(sessionId: 'current');
    } catch (_) {
      // Session may already be expired
    }
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Auth provider — global auth state for the entire app
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final account = ref.watch(appwriteAccountProvider);
  return AuthNotifier(account);
});

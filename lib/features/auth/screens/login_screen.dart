import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:appwrite/enums.dart';
import '../../../core/theme/theme.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_logo.dart';

/// Login screen — Phone OTP + Email + Social login
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showEmailLogin = false;
  bool _roleSet = false;
  String _selectedRole = 'customer';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set role SYNCHRONOUSLY on first frame — no postFrameCallback race
    if (!_roleSet) {
      _roleSet = true;
      _selectedRole = _getSelectedRole(context);
      ref.read(authProvider.notifier).setSelectedRole(_selectedRole);

      // Kick off GPS warm-up in the background while the user types the phone
      // number / waits for OTP. By the time onboarding opens, the first real
      // GPS fix is usually already cached — customers see their address
      // instantly instead of watching a spinner.
      if (_selectedRole == 'customer') {
        ref.read(locationServiceProvider).warmUp();
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Get the selected role from route extra (passed from role selection screen)
  String _getSelectedRole(BuildContext context) {
    try {
      final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
      return extra?['role'] as String? ?? 'customer';
    } catch (_) {
      return 'customer';
    }
  }

  String? _extractIndianTenDigitPhone(String input) {
    final digitsOnly = input.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length == 10) {
      return digitsOnly;
    }
    if (digitsOnly.length == 12 && digitsOnly.startsWith('91')) {
      return digitsOnly.substring(2);
    }
    return null;
  }

  String _toE164IndianPhone(String localPhone) {
    return '+91$localPhone';
  }

  void _showError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final selectedRole = _selectedRole;

    final roleLabel_ = switch (selectedRole) {
      'restaurant_owner' => 'Restaurant Partner',
      'delivery_partner' => 'Delivery Partner',
      _ => '',
    };

    // Listen for auth state changes
    ref.listen<AuthState>(authProvider, (prev, next) {
      // Auth success → router redirect will handle navigation based on role + onboarding
      if (prev?.status != AuthStatus.authenticated &&
          next.status == AuthStatus.authenticated) {
        if (kDebugMode) {
          debugPrint('[Login] Auth success! Router redirect will navigate.');
        }
        return;
      }
      // Error → show snackbar
      if (next.error != null) {
        if (kDebugMode) debugPrint('[Login] Error: ${next.error}');
        _showError(next.error!);
        ref.read(authProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.massive),

              // ─── Brand Header ───
              _buildBrandHeader(roleLabel_),

              const SizedBox(height: AppSpacing.huge),

              // ─── Phone Login ───
              if (!_showEmailLogin) ...[
                _buildPhoneLogin(authState),
                const SizedBox(height: AppSpacing.xl),
                _buildDivider(),
                const SizedBox(height: AppSpacing.xl),
                _buildSocialLogins(authState),
                const SizedBox(height: AppSpacing.xl),
                _buildEmailToggle(),
              ],

              // ─── Email Login ───
              if (_showEmailLogin) ...[
                _buildEmailLogin(authState),
                const SizedBox(height: AppSpacing.base),
                _buildPhoneToggle(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader(String roleLabel) {
    return Semantics(
      header: true,
      label: roleLabel.isNotEmpty
          ? 'Welcome to Chizze. Sign in as $roleLabel'
          : 'Welcome to Chizze. Sign in to order your favorite food',
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo
        ExcludeSemantics(
          child: const AppLogo(size: 72, borderRadius: 18)
              .animate()
              .scale(duration: 400.ms, curve: Curves.easeOutBack),
        ),

        const SizedBox(height: AppSpacing.xl),

        ExcludeSemantics(
        child: Text(
          'Welcome to',
          style: AppTypography.body2,
        ).animate(delay: 200.ms).fadeIn(),
        ),

        ExcludeSemantics(
        child: Text(
          'Chizze',
          style: AppTypography.h1.copyWith(fontSize: 32),
        ).animate(delay: 300.ms).fadeIn().slideX(begin: -0.1),
        ),

        const SizedBox(height: AppSpacing.sm),

        ExcludeSemantics(
        child: Text(
          roleLabel.isNotEmpty
              ? 'Sign in as $roleLabel'
              : 'Sign in to order your favorite food',
          style: AppTypography.body2,
        ).animate(delay: 400.ms).fadeIn(),
        ),
      ],
    ),
    );
  }

  Widget _buildPhoneLogin(AuthState authState) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Phone Number', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),

          // Phone input
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            style: AppTypography.body1,
            decoration: InputDecoration(
              hintText: '9876543210',
              prefixIcon: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text('🇮🇳', style: TextStyle(fontSize: 20)),
              ),
              prefixText: '+91 ',
              counterText: '',
            ),
          ),

          const SizedBox(height: AppSpacing.base),

          // Send OTP button
          ChizzeButton(
            label: 'Send OTP',
            isLoading: authState.isLoading,
            onPressed: () async {
              final inputPhone = _phoneController.text.trim();
              if (inputPhone.isEmpty) {
                _showError('Please enter your phone number to continue.');
                return;
              }

              final localPhone = _extractIndianTenDigitPhone(inputPhone);
              if (localPhone == null) {
                _showError('Please enter a valid 10-digit mobile number.');
                return;
              }

              final formattedPhone = _toE164IndianPhone(localPhone);

              final userId = await ref
                  .read(authProvider.notifier)
                  .sendPhoneOTP(formattedPhone);

              if (userId != null && mounted) {
                context.push(
                  '/otp',
                  extra: {'phone': formattedPhone, 'userId': userId},
                );
              }
            },
          ),
        ],
      ),
    ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Text('or continue with', style: AppTypography.caption),
        ),
        const Expanded(child: Divider(color: AppColors.divider)),
      ],
    );
  }

  Widget _buildSocialLogins(AuthState authState) {
    return Row(
      children: [
        // Google
        Expanded(
          child: _SocialButton(
            icon: Icons.g_mobiledata_rounded,
            label: 'Google',
            onTap: authState.isLoading
                ? null
                : () {
                    ref
                        .read(authProvider.notifier)
                        .loginWithOAuth(OAuthProvider.google);
                  },
          ),
        ),

        const SizedBox(width: AppSpacing.md),

        // Apple
        Expanded(
          child: _SocialButton(
            icon: Icons.apple_rounded,
            label: 'Apple',
            onTap: authState.isLoading
                ? null
                : () {
                    ref
                        .read(authProvider.notifier)
                        .loginWithOAuth(OAuthProvider.apple);
                  },
          ),
        ),

        const SizedBox(width: AppSpacing.md),

        // Facebook
        Expanded(
          child: _SocialButton(
            icon: Icons.facebook_rounded,
            label: 'Facebook',
            onTap: authState.isLoading
                ? null
                : () {
                    ref
                        .read(authProvider.notifier)
                        .loginWithFacebook();
                  },
          ),
        ),
      ],
    ).animate(delay: 600.ms).fadeIn();
  }

  Widget _buildEmailToggle() {
    return Center(
      child: TextButton(
        onPressed: () => setState(() => _showEmailLogin = true),
        child: Text(
          'Login with Email instead',
          style: AppTypography.caption.copyWith(color: AppColors.primary),
        ),
      ),
    ).animate(delay: 700.ms).fadeIn();
  }

  Widget _buildEmailLogin(AuthState authState) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: AppTypography.body1,
            decoration: const InputDecoration(
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),

          const SizedBox(height: AppSpacing.base),

          Text('Password', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _passwordController,
            obscureText: true,
            style: AppTypography.body1,
            decoration: const InputDecoration(
              hintText: '••••••••',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          ChizzeButton(
            label: 'Login',
            isLoading: authState.isLoading,
            onPressed: () {
              final email = _emailController.text.trim();
              final password = _passwordController.text;

              if (email.isEmpty) {
                _showError('Please enter your email address.');
                return;
              }

              final isValidEmail = RegExp(
                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
              ).hasMatch(email);
              if (!isValidEmail) {
                _showError('Please enter a valid email address.');
                return;
              }

              if (password.isEmpty) {
                _showError('Please enter your password.');
                return;
              }

              ref
                  .read(authProvider.notifier)
                  .loginWithEmail(
                    email, password,
                  );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneToggle() {
    return Center(
      child: TextButton(
        onPressed: () => setState(() => _showEmailLogin = false),
        child: Text(
          'Login with Phone instead',
          style: AppTypography.caption.copyWith(color: AppColors.primary),
        ),
      ),
    );
  }
}

/// Social login button (Google, Apple)
class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _SocialButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Sign in with $label',
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: AppColors.textPrimary),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: AppTypography.buttonSmall),
          ],
        ),
      ),
    ),
    );
  }
}

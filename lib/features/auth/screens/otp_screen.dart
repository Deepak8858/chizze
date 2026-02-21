import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../../../shared/widgets/glass_card.dart';

/// OTP verification screen — 6-digit code entry
class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final String userId;

  const OtpScreen({super.key, required this.phone, required this.userId});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isVerifying = false;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _onOtpChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    // Auto-submit when all 6 digits are entered
    if (_otp.length == 6 && !_isVerifying) {
      _verifyOTP();
    }
  }

  void _verifyOTP() {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);
    debugPrint('[OTP] Verifying OTP for userId=${widget.userId}');
    ref.read(authProvider.notifier).verifyPhoneOTP(widget.userId, _otp);
  }

  void _clearOtp() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Listen for auth state changes
    ref.listen<AuthState>(authProvider, (prev, next) {
      // Auth success → router redirect will handle navigation based on role + onboarding
      if (prev?.status != AuthStatus.authenticated &&
          next.status == AuthStatus.authenticated) {
        debugPrint('[OTP] Auth success! Router redirect will navigate.');
        // Trigger GoRouter redirect by navigating to root
        if (mounted) context.go('/');
        return;
      }
      // Error → show snackbar, reset verify flag, clear OTP
      if (next.error != null) {
        debugPrint('[OTP] Error: ${next.error}');
        setState(() => _isVerifying = false);
        _clearOtp();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
        ref.read(authProvider.notifier).clearError();
      }
      // Loading finished without success → reset flag
      if (prev?.isLoading == true && !next.isLoading && next.status != AuthStatus.authenticated) {
        setState(() => _isVerifying = false);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),

              Text(
                'Verify your number',
                style: AppTypography.h2,
              ).animate().fadeIn().slideX(begin: -0.1),

              const SizedBox(height: AppSpacing.sm),

              RichText(
                text: TextSpan(
                  text: 'Enter the 6-digit code sent to ',
                  style: AppTypography.body2,
                  children: [
                    TextSpan(
                      text: widget.phone,
                      style: AppTypography.body1.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ).animate(delay: 100.ms).fadeIn(),

              const SizedBox(height: AppSpacing.xxl),

              // ─── OTP Input Boxes ───
              GlassCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 44,
                      height: 52,
                      child: TextField(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        style: AppTypography.h2.copyWith(
                          color: AppColors.primary,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.surfaceElevated,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (value) => _onOtpChanged(index, value),
                      ),
                    );
                  }),
                ),
              ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1),

              const SizedBox(height: AppSpacing.xl),

              // ─── Verify Button ───
              ChizzeButton(
                label: 'Verify OTP',
                isLoading: authState.isLoading || _isVerifying,
                onPressed: _otp.length == 6 && !_isVerifying ? _verifyOTP : null,
              ).animate(delay: 300.ms).fadeIn(),

              const SizedBox(height: AppSpacing.xl),

              // ─── Resend ───
              Center(
                child: TextButton(
                  onPressed: authState.isLoading
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await ref
                              .read(authProvider.notifier)
                              .sendPhoneOTP(widget.phone);
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('OTP resent!')),
                            );
                          }
                        },
                  child: Text(
                    'Didn\'t receive code? Resend',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ).animate(delay: 400.ms).fadeIn(),
            ],
          ),
        ),
      ),
    );
  }
}

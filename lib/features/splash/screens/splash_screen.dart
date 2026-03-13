import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/app_logo.dart';

/// Animated splash screen with Chizze branding
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            const AppLogo(size: 110, borderRadius: 26)
                .animate()
                .scale(duration: 600.ms, curve: Curves.easeOutBack)
                .fadeIn(duration: 400.ms),

            const SizedBox(height: AppSpacing.xl),

            // App name
            Text(
                  'Chizze',
                  style: AppTypography.h1.copyWith(
                    fontSize: 36,
                    letterSpacing: -1,
                  ),
                )
                .animate(delay: 300.ms)
                .fadeIn(duration: 500.ms)
                .slideY(begin: 0.3, end: 0, duration: 500.ms),

            const SizedBox(height: AppSpacing.sm),

            // Tagline
            Text(
              'Delicious food, delivered fast',
              style: AppTypography.body2,
            ).animate(delay: 500.ms).fadeIn(duration: 500.ms),

            const SizedBox(height: AppSpacing.huge),

            // Loading indicator
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            ).animate(delay: 700.ms).fadeIn(duration: 300.ms),
          ],
        ),
      ),
    );
  }
}

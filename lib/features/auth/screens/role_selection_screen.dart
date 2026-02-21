import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';

/// Role selection screen — first screen for unauthenticated users.
/// Lets user pick: Customer, Restaurant Owner, or Delivery Partner.
class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.massive),

              // ─── Brand Header ───
              _buildHeader(),

              const SizedBox(height: AppSpacing.huge),

              // ─── Role Cards ───
              Text(
                'How would you like to use Chizze?',
                style: AppTypography.h3,
              ).animate(delay: 400.ms).fadeIn(),

              const SizedBox(height: AppSpacing.xl),

              _RoleCard(
                icon: Icons.fastfood_rounded,
                title: 'Order Food',
                subtitle: 'Browse restaurants & order your favourite meals',
                gradient: AppColors.primaryGradient,
                onTap: () => context.go('/login', extra: {'role': 'customer'}),
              ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.1),

              const SizedBox(height: AppSpacing.base),

              _RoleCard(
                icon: Icons.store_rounded,
                title: 'Restaurant Partner',
                subtitle: 'Manage your restaurant, menu & orders',
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B35), Color(0xFFFF8F65)],
                ),
                onTap: () => context.go('/login', extra: {'role': 'restaurant_owner'}),
              ).animate(delay: 600.ms).fadeIn().slideY(begin: 0.1),

              const SizedBox(height: AppSpacing.base),

              _RoleCard(
                icon: Icons.delivery_dining_rounded,
                title: 'Delivery Partner',
                subtitle: 'Deliver food & earn on your schedule',
                gradient: const LinearGradient(
                  colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                ),
                onTap: () => context.go('/login', extra: {'role': 'delivery_partner'}),
              ).animate(delay: 700.ms).fadeIn().slideY(begin: 0.1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.restaurant_rounded,
            color: Colors.white,
            size: 28,
          ),
        ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),

        const SizedBox(height: AppSpacing.xl),

        Text(
          'Welcome to',
          style: AppTypography.body2,
        ).animate(delay: 200.ms).fadeIn(),

        Text(
          'Chizze',
          style: AppTypography.h1.copyWith(fontSize: 32),
        ).animate(delay: 300.ms).fadeIn().slideX(begin: -0.1),
      ],
    );
  }
}

/// A tappable card for role selection
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.h3.copyWith(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.caption,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

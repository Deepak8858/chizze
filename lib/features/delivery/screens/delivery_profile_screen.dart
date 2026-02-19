import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/delivery_provider.dart';

/// Delivery partner profile — stats, vehicle, support
class DeliveryProfileScreen extends ConsumerWidget {
  const DeliveryProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = ref.watch(deliveryProvider).partner;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            // ─── Avatar & Name ───
            _buildProfileHeader(partner.name, partner.rating),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Stats ───
            _buildStatsRow(partner.totalDeliveries, partner.totalEarnings),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Vehicle Info ───
            _buildVehicleCard(partner.vehicleType, partner.vehicleNumber),
            const SizedBox(height: AppSpacing.xl),

            // ─── Menu Items ───
            _buildMenuItem(
              Icons.account_balance_wallet_rounded,
              'Bank Details',
            ),
            _buildMenuItem(Icons.description_rounded, 'Documents'),
            _buildMenuItem(Icons.schedule_rounded, 'Availability'),
            _buildMenuItem(Icons.headset_mic_rounded, 'Support'),
            _buildMenuItem(Icons.info_outline_rounded, 'About Chizze'),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Logout ───
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.logout_rounded, color: AppColors.error),
              label: Text(
                'Logout',
                style: AppTypography.body2.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(String name, double rating) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: AppTypography.h1.copyWith(fontSize: 32),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(name, style: AppTypography.h2.copyWith(fontSize: 20)),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.star_rounded,
              size: 18,
              color: AppColors.ratingStar,
            ),
            const SizedBox(width: 4),
            Text(
              '$rating',
              style: AppTypography.body1.copyWith(
                color: AppColors.ratingStar,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(' rating', style: AppTypography.caption),
          ],
        ),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildStatsRow(int deliveries, double earnings) {
    return Row(
      children: [
        Expanded(
          child: GlassCard(
            child: Column(
              children: [
                const Text('📦', style: TextStyle(fontSize: 24)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '$deliveries',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.primary,
                    fontSize: 20,
                  ),
                ),
                Text('Deliveries', style: AppTypography.overline),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: GlassCard(
            child: Column(
              children: [
                const Text('💰', style: TextStyle(fontSize: 24)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '₹${(earnings / 1000).toStringAsFixed(1)}K',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.success,
                    fontSize: 20,
                  ),
                ),
                Text('Total Earned', style: AppTypography.overline),
              ],
            ),
          ),
        ),
      ],
    ).animate(delay: 200.ms).fadeIn();
  }

  Widget _buildVehicleCard(String type, String number) {
    final emoji = type == 'bike'
        ? '🏍️'
        : type == 'scooter'
        ? '🛵'
        : type == 'bicycle'
        ? '🚲'
        : '🚗';
    final label = type[0].toUpperCase() + type.substring(1);

    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.body1.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(number, style: AppTypography.caption),
              ],
            ),
          ),
          const Icon(
            Icons.edit_rounded,
            size: 18,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn();
  }

  Widget _buildMenuItem(IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ListTile(
        leading: Icon(icon, size: 22, color: AppColors.textSecondary),
        title: Text(label, style: AppTypography.body2),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: AppColors.textTertiary,
        ),
        onTap: () {},
        dense: true,
      ),
    );
  }
}

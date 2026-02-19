import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/coupons_provider.dart';

/// Coupons & offers screen
class CouponsScreen extends ConsumerWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cState = ref.watch(couponsProvider);
    final coupons = cState.available;

    final active = coupons.where((c) => c.isUsable).toList();
    final expired = coupons.where((c) => !c.isUsable).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Coupons & Offers')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          // ─── Applied coupon banner ───
          if (cState.appliedCoupon != null)
            _buildAppliedBanner(context, ref, cState.appliedCoupon!),

          // ─── Active Coupons ───
          if (active.isNotEmpty) ...[
            Text(
              'Available',
              style: AppTypography.overline.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...active.asMap().entries.map(
              (e) => _buildCouponCard(context, ref, e.value, e.key, true),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],

          // ─── Expired / Inactive ───
          if (expired.isNotEmpty) ...[
            Text(
              'Expired / Used',
              style: AppTypography.overline.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...expired.asMap().entries.map(
              (e) => _buildCouponCard(
                context,
                ref,
                e.value,
                e.key + active.length,
                false,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppliedBanner(
    BuildContext context,
    WidgetRef ref,
    Coupon coupon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.success.withValues(alpha: 0.15),
              AppColors.success.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.success),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${coupon.code} applied — ${coupon.title}',
                style: AppTypography.body2.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(couponsProvider.notifier).removeCoupon(),
              child: const Text('Remove', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    ).animate().fadeIn();
  }

  Widget _buildCouponCard(
    BuildContext context,
    WidgetRef ref,
    Coupon coupon,
    int index,
    bool isActive,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Opacity(
        opacity: isActive ? 1.0 : 0.5,
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Discount badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: isActive
                          ? AppColors.primaryGradient
                          : const LinearGradient(
                              colors: [Color(0xFF555555), Color(0xFF333333)],
                            ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      coupon.title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          coupon.description,
                          style: AppTypography.body2.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (coupon.restaurantId != null)
                          Text(
                            '🏪 Restaurant specific',
                            style: AppTypography.overline.copyWith(
                              fontSize: 9,
                              color: AppColors.info,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Code + details
              Row(
                children: [
                  // Dashed code box
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: coupon.code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Code "${coupon.code}" copied!'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.primary,
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            coupon.code,
                            style: AppTypography.buttonSmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.copy_rounded,
                            size: 12,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Details
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Min ₹${coupon.minOrder.toInt()}',
                        style: AppTypography.overline.copyWith(fontSize: 9),
                      ),
                      if (coupon.maxDiscount > 0)
                        Text(
                          'Max ₹${coupon.maxDiscount.toInt()} off',
                          style: AppTypography.overline.copyWith(fontSize: 9),
                        ),
                      Text(
                        isActive ? '${coupon.daysRemaining}d left' : 'Expired',
                        style: AppTypography.overline.copyWith(
                          fontSize: 9,
                          color: isActive ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (isActive) ...[
                const Divider(color: AppColors.divider, height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      ref.read(couponsProvider.notifier).applyCoupon(coupon.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${coupon.code} applied!'),
                          backgroundColor: AppColors.success,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Apply Coupon',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ).animate(delay: (index * 60).ms).fadeIn().slideY(begin: 0.02);
  }
}

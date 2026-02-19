import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../models/delivery_partner.dart';
import '../providers/delivery_provider.dart';

/// Delivery dashboard — online toggle, metrics, incoming requests
class DeliveryDashboardScreen extends ConsumerStatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  ConsumerState<DeliveryDashboardScreen> createState() =>
      _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState
    extends ConsumerState<DeliveryDashboardScreen> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dState = ref.watch(deliveryProvider);
    final partner = dState.partner;
    final metrics = dState.metrics;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header ───
              _buildHeader(partner),
              const SizedBox(height: AppSpacing.xxl),

              // ─── Online Toggle ───
              _buildOnlineToggle(partner),
              const SizedBox(height: AppSpacing.xxl),

              // ─── Metrics ───
              if (partner.isOnline) ...[
                _buildMetrics(metrics),
                const SizedBox(height: AppSpacing.xxl),

                // ─── Weekly Goal ───
                _buildWeeklyGoal(metrics),
                const SizedBox(height: AppSpacing.xxl),

                // ─── Incoming Request / Active Delivery ───
                if (dState.hasActiveDelivery)
                  _buildActiveDeliveryBanner(dState)
                else if (dState.hasIncomingRequest)
                  _buildIncomingRequest(dState.incomingRequest!)
                else
                  _buildWaitingForOrders(),

                const SizedBox(height: AppSpacing.xxl),

                // ─── Quick Actions ───
                _buildQuickActions(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(DeliveryPartner partner) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Center(
            child: Text('🛵', style: TextStyle(fontSize: 24)),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                partner.name,
                style: AppTypography.h2.copyWith(fontSize: 20),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: AppColors.ratingStar,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${partner.rating}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ratingStar,
                    ),
                  ),
                  Text(
                    ' · ${partner.totalDeliveries} deliveries',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏍️', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                partner.vehicleNumber,
                style: AppTypography.overline.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildOnlineToggle(DeliveryPartner partner) {
    return GestureDetector(
      onTap: () => ref.read(deliveryProvider.notifier).toggleOnline(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          gradient: partner.isOnline
              ? LinearGradient(
                  colors: [
                    AppColors.success.withValues(alpha: 0.2),
                    AppColors.success.withValues(alpha: 0.05),
                  ],
                )
              : LinearGradient(
                  colors: [
                    AppColors.error.withValues(alpha: 0.15),
                    AppColors.error.withValues(alpha: 0.05),
                  ],
                ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: partner.isOnline ? AppColors.success : AppColors.error,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: partner.isOnline
                    ? AppColors.success.withValues(alpha: 0.2)
                    : AppColors.error.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                partner.isOnline
                    ? Icons.power_settings_new_rounded
                    : Icons.power_off_rounded,
                size: 32,
                color: partner.isOnline ? AppColors.success : AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              partner.isOnline ? "You're Online" : "You're Offline",
              style: AppTypography.h3.copyWith(
                color: partner.isOnline ? AppColors.success : AppColors.error,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              partner.isOnline
                  ? 'Tap to go offline'
                  : 'Tap to start accepting deliveries',
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    ).animate(delay: 200.ms).fadeIn().scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildMetrics(DeliveryMetrics metrics) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            emoji: '💰',
            label: 'Earnings',
            value: '₹${metrics.todayEarnings.toInt()}',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MetricCard(
            emoji: '📦',
            label: 'Deliveries',
            value: '${metrics.todayDeliveries}',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MetricCard(
            emoji: '📍',
            label: 'Distance',
            value: '${metrics.todayDistanceKm.toStringAsFixed(1)} km',
            color: AppColors.info,
          ),
        ),
      ],
    ).animate(delay: 300.ms).fadeIn();
  }

  Widget _buildWeeklyGoal(DeliveryMetrics metrics) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly Goal 🎯',
                style: AppTypography.body1.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${metrics.weeklyCompleted}/${metrics.weeklyGoal}',
                style: AppTypography.caption.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: metrics.weeklyProgress,
              minHeight: 10,
              backgroundColor: AppColors.surfaceElevated,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          if (metrics.weeklyProgress >= 1.0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '🎉 Goal completed! Bonus unlocked!',
              style: AppTypography.caption.copyWith(color: AppColors.success),
            ),
          ],
        ],
      ),
    ).animate(delay: 400.ms).fadeIn();
  }

  Widget _buildIncomingRequest(DeliveryRequest request) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text('🔔', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New Delivery Request!',
                      style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(request.restaurantName, style: AppTypography.caption),
                  ],
                ),
              ),
              // Countdown
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: request.secondsRemaining < 10
                      ? AppColors.error.withValues(alpha: 0.15)
                      : AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: request.secondsRemaining < 10
                        ? AppColors.error
                        : AppColors.warning,
                  ),
                ),
                child: Text(
                  '${request.secondsRemaining}s',
                  style: AppTypography.buttonSmall.copyWith(
                    color: request.secondsRemaining < 10
                        ? AppColors.error
                        : AppColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.divider, height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '₹${request.estimatedEarning.toInt()}',
                      style: AppTypography.h3.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                    Text(
                      'Earning',
                      style: AppTypography.overline.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 30, color: AppColors.divider),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '${request.distanceKm} km',
                      style: AppTypography.h3.copyWith(color: AppColors.info),
                    ),
                    Text(
                      'Distance',
                      style: AppTypography.overline.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Addresses
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        request.restaurantAddress,
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 16,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        request.customerAddress,
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      ref.read(deliveryProvider.notifier).rejectRequest(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () {
                    ref.read(deliveryProvider.notifier).acceptRequest();
                    context.go('/delivery/active');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Accept Delivery',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.05);
  }

  Widget _buildActiveDeliveryBanner(DeliveryState dState) {
    final step = dState.activeDelivery!.currentStep;
    return GestureDetector(
      onTap: () => context.go('/delivery/active'),
      child: GlassCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(step.emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Delivery',
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    step.label,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    ).animate().fadeIn().shimmer(
      delay: 1000.ms,
      duration: 1500.ms,
      color: AppColors.primary.withValues(alpha: 0.1),
    );
  }

  Widget _buildWaitingForOrders() {
    return GlassCard(
      child: Column(
        children: [
          const Text('📡', style: TextStyle(fontSize: 40)),
          const SizedBox(height: AppSpacing.md),
          Text('Looking for deliveries...', style: AppTypography.body1),
          const SizedBox(height: 4),
          Text(
            'Stay online — new orders coming soon',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          // Debug button to simulate request
          TextButton.icon(
            onPressed: () =>
                ref.read(deliveryProvider.notifier).simulateNewRequest(),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text(
              'Simulate Request',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      ('📦', 'Active', '/delivery/active'),
      ('💰', 'Earnings', '/delivery/earnings'),
      ('👤', 'Profile', '/delivery/profile'),
      ('🆘', 'Support', '/delivery/dashboard'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: AppTypography.h3.copyWith(fontSize: 16)),
        const SizedBox(height: AppSpacing.md),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.md,
          children: actions.map((a) {
            return GestureDetector(
              onTap: () => context.go(a.$3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Center(
                      child: Text(a.$1, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    a.$2,
                    style: AppTypography.overline.copyWith(fontSize: 10),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    ).animate(delay: 500.ms).fadeIn();
  }
}

class _MetricCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: AppTypography.h3.copyWith(color: color, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.overline.copyWith(fontSize: 9),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

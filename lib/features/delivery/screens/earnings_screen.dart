import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/earnings_provider.dart';

/// Earnings screen — chart, trips, incentives, payouts
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earnings = ref.watch(earningsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Earnings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Summary ───
            _buildSummary(earnings),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Weekly Chart ───
            Text('This Week', style: AppTypography.h3.copyWith(fontSize: 16)),
            const SizedBox(height: AppSpacing.md),
            _WeeklyChart(data: earnings.weeklyData),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Incentives ───
            _buildIncentives(earnings),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Recent Trips ───
            Text(
              'Recent Trips',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            ...earnings.recentTrips.asMap().entries.map(
              (e) => _buildTripCard(e.value, e.key),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ─── Payouts ───
            Text('Payouts', style: AppTypography.h3.copyWith(fontSize: 16)),
            const SizedBox(height: AppSpacing.md),
            ...earnings.payouts.map(_buildPayoutCard),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(EarningsState earnings) {
    return Row(
      children: [
        Expanded(
          child: GlassCard(
            child: Column(
              children: [
                const Text('💰', style: TextStyle(fontSize: 22)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '₹${earnings.weeklyTotal.toInt()}',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.success,
                    fontSize: 18,
                  ),
                ),
                Text('This Week', style: AppTypography.overline),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: GlassCard(
            child: Column(
              children: [
                const Text('📅', style: TextStyle(fontSize: 22)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '₹${(earnings.monthlyTotal / 1000).toStringAsFixed(1)}K',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.primary,
                    fontSize: 18,
                  ),
                ),
                Text('This Month', style: AppTypography.overline),
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildIncentives(EarningsState earnings) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bonuses & Incentives 🎁',
            style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '₹${earnings.incentiveEarned.toInt()}',
                        style: AppTypography.h3.copyWith(
                          color: AppColors.success,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Incentives',
                        style: AppTypography.overline.copyWith(fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '₹${earnings.surgeEarned.toInt()}',
                        style: AppTypography.h3.copyWith(
                          color: AppColors.primary,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Surge',
                        style: AppTypography.overline.copyWith(fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn();
  }

  Widget _buildTripCard(TripEarning trip, int index) {
    final time = _formatTime(trip.completedAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('🛵', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          trip.restaurantName,
                          style: AppTypography.body2.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (trip.hasSurge)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '⚡ Surge',
                            style: AppTypography.overline.copyWith(
                              color: AppColors.primary,
                              fontSize: 8,
                            ),
                          ),
                        ),
                      if (trip.tipAmount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+₹${trip.tipAmount.toInt()} tip',
                            style: AppTypography.overline.copyWith(
                              color: AppColors.success,
                              fontSize: 8,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${trip.distanceKm} km · ${trip.durationMin} min · $time',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            Text('₹${trip.amount.toInt()}', style: AppTypography.price),
          ],
        ),
      ),
    ).animate(delay: (index * 60).ms).fadeIn().slideX(begin: 0.02);
  }

  Widget _buildPayoutCard(PayoutRecord payout) {
    final statusColor = payout.status == 'completed'
        ? AppColors.success
        : payout.status == 'processing'
        ? AppColors.warning
        : AppColors.textTertiary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                payout.status == 'completed'
                    ? Icons.check_circle_rounded
                    : Icons.pending_rounded,
                size: 20,
                color: statusColor,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${payout.orderCount} orders',
                    style: AppTypography.body2.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    payout.status[0].toUpperCase() + payout.status.substring(1),
                    style: AppTypography.caption.copyWith(color: statusColor),
                  ),
                ],
              ),
            ),
            Text('₹${payout.amount.toInt()}', style: AppTypography.price),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Weekly earnings bar chart
class _WeeklyChart extends StatelessWidget {
  final List<DailyEarning> data;
  const _WeeklyChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxAmount = data.map((d) => d.amount).reduce(max);

    return GlassCard(
      child: SizedBox(
        height: 160,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.map((day) {
            final fraction = maxAmount > 0 ? day.amount / maxAmount : 0.0;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '₹${day.amount.toInt()}',
                      style: AppTypography.overline.copyWith(fontSize: 8),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      height: 100 * fraction,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.success,
                            AppColors.success.withValues(alpha: 0.5),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      day.day,
                      style: AppTypography.overline.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ).animate(delay: 200.ms).fadeIn();
  }
}

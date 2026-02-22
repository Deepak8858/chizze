import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../providers/earnings_provider.dart';

/// Earnings screen — period selector, chart, trips, payouts
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earnings = ref.watch(earningsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Earnings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () => ref.read(earningsProvider.notifier).refresh(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: earnings.isLoading
          ? const EarningsSkeleton()
          : RefreshIndicator(
              onRefresh: () => ref.read(earningsProvider.notifier).refresh(),
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── Period Selector ───
                    _PeriodSelector(
                      selected: earnings.selectedPeriod,
                      onChanged: (p) =>
                          ref.read(earningsProvider.notifier).selectPeriod(p),
                      onCustom: () => _pickCustomRange(context, ref),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // ─── Summary Cards ───
                    _buildSummary(earnings),
                    const SizedBox(height: AppSpacing.xxl),

                    // ─── Weekly Chart ───
                    if (earnings.weeklyData.isNotEmpty) ...[
                      Text(
                        'This Week',
                        style: AppTypography.h3.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _WeeklyChart(data: earnings.weeklyData),
                      const SizedBox(height: AppSpacing.xxl),
                    ],

                    // ─── Earnings Breakdown ───
                    _buildBreakdown(earnings),
                    const SizedBox(height: AppSpacing.xxl),

                    // ─── Recent Trips ───
                    if (earnings.recentTrips.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Trips',
                            style: AppTypography.h3.copyWith(fontSize: 16),
                          ),
                          Text(
                            '${earnings.totalTrips} total',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ...earnings.recentTrips.asMap().entries.map(
                        (e) => _buildTripCard(e.value, e.key),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                    ],

                    // ─── Payouts ───
                    _PayoutSection(
                      payouts: earnings.payouts,
                      isLoading: earnings.isPayoutsLoading,
                      isRequesting: earnings.isRequestingPayout,
                      onRequestPayout: () =>
                          _handleRequestPayout(context, ref),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
    );
  }

  // ─── Custom range picker ────────────────────────────────────────

  Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (range != null && context.mounted) {
      ref.read(earningsProvider.notifier).setCustomRange(
        range.start,
        range.end,
      );
    }
  }

  // ─── Request payout ─────────────────────────────────────────────

  Future<void> _handleRequestPayout(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Request Payout', style: AppTypography.h3),
        content: Text(
          'Request an instant withdrawal of your current balance?',
          style: AppTypography.body2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            child: const Text('Request'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ok = await ref.read(earningsProvider.notifier).requestPayout();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Payout requested successfully!'
                  : 'Failed to request payout',
            ),
            backgroundColor: ok ? AppColors.success : AppColors.error,
          ),
        );
      }
    }
  }

  // ─── Summary ────────────────────────────────────────────────────

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

  // ─── Breakdown ──────────────────────────────────────────────────

  Widget _buildBreakdown(EarningsState earnings) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Breakdown',
            style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _BreakdownTile(
                  label: 'Tips',
                  value: '₹${earnings.totalTips.toInt()}',
                  color: AppColors.success,
                  icon: Icons.volunteer_activism_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _BreakdownTile(
                  label: 'Avg/Trip',
                  value: '₹${earnings.weeklyAvgPerTrip.toInt()}',
                  color: AppColors.info,
                  icon: Icons.analytics_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _BreakdownTile(
                  label: 'Trips',
                  value: '${earnings.totalTrips}',
                  color: AppColors.primary,
                  icon: Icons.delivery_dining_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate(delay: 200.ms).fadeIn();
  }

  // ─── Trip card ──────────────────────────────────────────────────

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

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Period Selector Widget ────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  final EarningsPeriod selected;
  final ValueChanged<EarningsPeriod> onChanged;
  final VoidCallback onCustom;

  const _PeriodSelector({
    required this.selected,
    required this.onChanged,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: EarningsPeriod.values.map((period) {
          final isSelected = period == selected;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: GestureDetector(
              onTap: () {
                if (period == EarningsPeriod.custom) {
                  onCustom();
                } else {
                  onChanged(period);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.primaryGradient : null,
                  color: isSelected ? null : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: isSelected
                      ? null
                      : Border.all(color: AppColors.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (period == EarningsPeriod.custom) ...[
                      Icon(
                        Icons.date_range_rounded,
                        size: 14,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      period.label,
                      style: AppTypography.buttonSmall.copyWith(
                        color: isSelected
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ).animate().fadeIn(delay: 50.ms);
  }
}

// ─── Breakdown Tile Widget ─────────────────────────────────────────

class _BreakdownTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _BreakdownTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.h3.copyWith(color: color, fontSize: 15),
          ),
          Text(
            label,
            style: AppTypography.overline.copyWith(fontSize: 9),
          ),
        ],
      ),
    );
  }
}

// ─── Payout Section Widget ─────────────────────────────────────────

class _PayoutSection extends StatelessWidget {
  final List<PayoutRecord> payouts;
  final bool isLoading;
  final bool isRequesting;
  final VoidCallback onRequestPayout;

  const _PayoutSection({
    required this.payouts,
    required this.isLoading,
    required this.isRequesting,
    required this.onRequestPayout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Payouts',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            TextButton.icon(
              onPressed: isRequesting ? null : onRequestPayout,
              icon: isRequesting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.account_balance_rounded, size: 16),
              label: Text(
                isRequesting ? 'Requesting...' : 'Request Payout',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (payouts.isEmpty)
          GlassCard(
            child: Center(
              child: Column(
                children: [
                  const Text('📋', style: TextStyle(fontSize: 28)),
                  const SizedBox(height: AppSpacing.sm),
                  Text('No payouts yet', style: AppTypography.body2),
                  Text(
                    'Complete deliveries to start earning',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
          )
        else
          ...payouts.map(_buildPayoutCard),
      ],
    ).animate(delay: 400.ms).fadeIn();
  }

  Widget _buildPayoutCard(PayoutRecord payout) {
    final statusColor = payout.isCompleted
        ? AppColors.success
        : payout.isProcessing
            ? AppColors.warning
            : payout.isFailed
                ? AppColors.error
                : AppColors.textTertiary;

    final statusIcon = payout.isCompleted
        ? Icons.check_circle_rounded
        : payout.isProcessing
            ? Icons.pending_rounded
            : payout.isFailed
                ? Icons.error_rounded
                : Icons.schedule_rounded;

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
              child: Icon(statusIcon, size: 20, color: statusColor),
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
                    payout.status[0].toUpperCase() +
                        payout.status.substring(1),
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
}

// ─── Weekly Chart Widget ───────────────────────────────────────────

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

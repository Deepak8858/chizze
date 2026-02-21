import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../providers/analytics_provider.dart';

/// Partner analytics — revenue chart, top items, peak hours
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Analytics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Summary Cards ───
            _buildSummaryCards(analytics),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Revenue Chart ───
            Text(
              'Weekly Revenue',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            _RevenueChart(data: analytics.revenueData),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Top Selling Items ───
            Text(
              'Top Selling Items',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.md),
            ...analytics.topItems.asMap().entries.map((entry) {
              return _buildTopItemCard(entry.value, entry.key);
            }),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Peak Hours ───
            Text('Peak Hours', style: AppTypography.h3.copyWith(fontSize: 16)),
            const SizedBox(height: AppSpacing.md),
            _PeakHoursChart(data: analytics.peakHours),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(AnalyticsState analytics) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            emoji: '💰',
            label: 'Total Revenue',
            value: '₹${(analytics.totalRevenue / 1000).toStringAsFixed(1)}K',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _SummaryCard(
            emoji: '📦',
            label: 'Total Orders',
            value: '${analytics.totalOrders}',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _SummaryCard(
            emoji: '📊',
            label: 'Avg Order',
            value: '₹${analytics.avgOrderValue.toInt()}',
            color: AppColors.info,
          ),
        ),
      ],
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildTopItemCard(TopItem item, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        child: Row(
          children: [
            // Rank
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: index < 3
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '#${index + 1}',
                  style: AppTypography.buttonSmall.copyWith(
                    color: index < 3
                        ? AppColors.primary
                        : AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Veg dot
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                border: Border.all(
                  color: item.isVeg ? AppColors.veg : AppColors.nonVeg,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: item.isVeg ? AppColors.veg : AppColors.nonVeg,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),

            // Name + order count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: AppTypography.body2.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${item.orderCount} orders',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),

            Text(
              '₹${(item.revenue / 1000).toStringAsFixed(1)}K',
              style: AppTypography.price,
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 80).ms).fadeIn().slideX(begin: 0.03);
  }
}

class _SummaryCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
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
          Text(emoji, style: const TextStyle(fontSize: 20)),
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

/// Custom painted revenue bar chart
class _RevenueChart extends StatelessWidget {
  final List<DailyRevenue> data;
  const _RevenueChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return GlassCard(
        child: SizedBox(
          height: 180,
          child: Center(
            child: Text('No revenue data yet', style: AppTypography.body2.copyWith(color: AppColors.textSecondary)),
          ),
        ),
      );
    }

    final maxAmount = data.map((d) => d.amount).reduce(max);

    return GlassCard(
      child: SizedBox(
        height: 180,
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
                      '${(day.amount / 1000).toStringAsFixed(0)}K',
                      style: AppTypography.overline.copyWith(
                        fontSize: 8,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      height: 120 * fraction,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.primary,
                            AppColors.primary.withValues(alpha: 0.6),
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

/// Peak hours horizontal bar chart
class _PeakHoursChart extends StatelessWidget {
  final List<HourlyVolume> data;
  const _PeakHoursChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxOrders = data.map((d) => d.orders).reduce(max);

    return GlassCard(
      child: Column(
        children: data.map((hv) {
          final fraction = maxOrders > 0 ? hv.orders / maxOrders : 0.0;
          final isPeak = fraction > 0.7;
          final timeLabel =
              '${hv.hour > 12 ? hv.hour - 12 : hv.hour}${hv.hour >= 12 ? 'PM' : 'AM'}';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    timeLabel,
                    style: AppTypography.overline.copyWith(fontSize: 10),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 14,
                      backgroundColor: AppColors.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation(
                        isPeak
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${hv.orders}',
                    style: AppTypography.overline.copyWith(
                      fontSize: 10,
                      color: isPeak
                          ? AppColors.primary
                          : AppColors.textTertiary,
                      fontWeight: isPeak ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    ).animate(delay: 400.ms).fadeIn();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../providers/scheduled_orders_provider.dart';

/// Scheduled orders screen — view & cancel upcoming scheduled orders
class ScheduledOrdersScreen extends ConsumerWidget {
  const ScheduledOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scheduledOrdersProvider);

    // Listen for messages
    ref.listen<ScheduledOrdersState>(scheduledOrdersProvider, (prev, next) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.successMessage!),
            backgroundColor: AppColors.success,
          ),
        );
      }
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    final upcoming =
        state.orders.where((o) => !o.isCancelled).toList()
          ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    final cancelled = state.orders.where((o) => o.isCancelled).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Scheduled Orders')),
      body: state.isLoading
          ? ListSkeleton(
              itemCount: 4,
              itemBuilder: (_, _) => const OrderCardSkeleton(),
            )
          : state.orders.isEmpty
              ? _buildEmpty(context)
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(scheduledOrdersProvider.notifier).fetch(),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: [
                      if (upcoming.isNotEmpty) ...[
                        Text(
                          'Upcoming',
                          style: AppTypography.overline.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...upcoming.asMap().entries.map(
                          (e) => _buildOrderCard(context, ref, e.value, e.key),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (cancelled.isNotEmpty) ...[
                        Text(
                          'Cancelled',
                          style: AppTypography.overline.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...cancelled.asMap().entries.map(
                          (e) => _buildOrderCard(
                            context,
                            ref,
                            e.value,
                            e.key + upcoming.length,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return EmptyStateWidget.noScheduledOrders();
  }

  Widget _buildOrderCard(
    BuildContext context,
    WidgetRef ref,
    ScheduledOrder order,
    int index,
  ) {
    final isCancelled = order.isCancelled;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        onTap: () => context.push('/restaurant/${order.restaurantId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isCancelled
                        ? AppColors.error.withValues(alpha: 0.1)
                        : AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      isCancelled
                          ? Icons.cancel_rounded
                          : Icons.schedule_rounded,
                      color: isCancelled ? AppColors.error : AppColors.primary,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.restaurantName,
                        style: AppTypography.body1.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: isCancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        '${order.itemCount} items · ₹${order.totalAmount.toInt()}',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.status[0].toUpperCase() + order.status.substring(1),
                    style: AppTypography.overline.copyWith(
                      color: _statusColor(order.status),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _formatScheduledTime(order.scheduledTime),
                    style: AppTypography.body2,
                  ),
                ],
              ),
            ),
            if (!isCancelled) ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _showCancelDialog(context, ref, order.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMd,
                      ),
                    ),
                  ),
                  child: const Text('Cancel Order'),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate(delay: (index * 80).ms).fadeIn().slideY(begin: 0.03);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  void _showCancelDialog(BuildContext context, WidgetRef ref, String orderId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Scheduled Order?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(scheduledOrdersProvider.notifier).cancel(orderId);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );
  }

  String _formatScheduledTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    final isTomorrow = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day + 1;

    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    if (isToday) return 'Today at $time';
    if (isTomorrow) return 'Tomorrow at $time';
    return '${dt.day} ${months[dt.month - 1]} at $time';
  }
}

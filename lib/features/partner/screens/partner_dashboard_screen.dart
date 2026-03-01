import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../../../features/orders/models/order.dart';
import '../providers/partner_provider.dart';
import '../models/partner_order.dart';

/// Partner dashboard — metrics, active queue, quick actions
class PartnerDashboardScreen extends ConsumerWidget {
  const PartnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerState = ref.watch(partnerProvider);
    final metrics = partnerState.metrics;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: partnerState.isLoading
            ? const EarningsSkeleton()
            : SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Connection Status ───
              if (partnerState.connectionStatus !=
                  RealtimeConnectionStatus.connected)
                _buildConnectionBanner(partnerState.connectionStatus),

              // ─── New Orders Alert ───
              if (partnerState.unacknowledgedNewOrders > 0)
                _buildNewOrderBanner(
                  context,
                  ref,
                  partnerState.unacknowledgedNewOrders,
                ),

              // ─── Header ───
              _buildHeader(ref, partnerState),

              const SizedBox(height: AppSpacing.xxl),

              // ─── Metrics ───
              _buildMetricsRow(metrics),

              const SizedBox(height: AppSpacing.xxl),

              // ─── Active Orders ───
              _buildActiveOrdersSection(context, ref, partnerState),

              const SizedBox(height: AppSpacing.xxl),

              // ─── Quick Actions ───
              _buildQuickActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(WidgetRef ref, PartnerState partnerState) {
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
            child: Text('🍳', style: TextStyle(fontSize: 24)),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                partnerState.restaurantName ?? 'Restaurant Dashboard',
                style: AppTypography.h2.copyWith(fontSize: 20),
              ),
              Text('Restaurant Dashboard', style: AppTypography.caption),
            ],
          ),
        ),

        // Online/Offline toggle
        Semantics(
          toggled: partnerState.isOnline,
          label: partnerState.isOnline ? 'Online, tap to go offline' : 'Offline, tap to go online',
          button: true,
          child: GestureDetector(
          onTap: () => ref.read(partnerProvider.notifier).toggleOnline(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: partnerState.isOnline
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              border: Border.all(
                color: partnerState.isOnline
                    ? AppColors.success
                    : AppColors.error,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: partnerState.isOnline
                        ? AppColors.success
                        : AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  partnerState.isOnline ? 'Online' : 'Offline',
                  style: AppTypography.overline.copyWith(
                    color: partnerState.isOnline
                        ? AppColors.success
                        : AppColors.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildMetricsRow(PartnerMetrics metrics) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            emoji: '💰',
            label: "Today's Revenue",
            value: '₹${(metrics.todayRevenue / 1000).toStringAsFixed(1)}K',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MetricCard(
            emoji: '📦',
            label: 'Orders',
            value: '${metrics.todayOrders}',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _MetricCard(
            emoji: '⭐',
            label: 'Rating',
            value: metrics.avgRating.toStringAsFixed(1),
            color: AppColors.ratingStar,
          ),
        ),
      ],
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.05);
  }

  Widget _buildActiveOrdersSection(
    BuildContext context,
    WidgetRef ref,
    PartnerState partnerState,
  ) {
    final activeOrders = partnerState.activeOrders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Active Orders',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
            if (activeOrders.isNotEmpty)
              GestureDetector(
                onTap: () => context.go('/partner/orders'),
                child: Text(
                  'View All',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (activeOrders.isEmpty)
          GlassCard(
            child: EmptyStateWidget.noPartnerOrders(),
          )
        else
          ...activeOrders.take(3).toList().asMap().entries.map((entry) {
            final po = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _QuickOrderCard(
                partnerOrder: po,
                onAccept: () =>
                    ref.read(partnerProvider.notifier).acceptOrder(po.order.id),
                onReject: () => _showQuickRejectDialog(context, ref, po.order.id),
                onTap: () => context.go('/partner/orders'),
              ),
            ).animate(delay: (entry.key * 80).ms).fadeIn().slideX(begin: 0.03);
          }),
      ],
    );
  }

  void _showQuickRejectDialog(BuildContext context, WidgetRef ref, String orderId) {
    const reasons = [
      'Too busy right now',
      'Item unavailable',
      'Kitchen closing soon',
      'Cannot deliver to this area',
      'Other',
    ];
    String selectedReason = '';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Reject Order'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                  mainAxisSize: MainAxisSize.min,
                  children: reasons.map((reason) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Radio<String>(
                      value: reason,
                          groupValue: selectedReason,
                          onChanged: (String? val) =>
                              setDialogState(() => selectedReason = val ?? ''),
                      activeColor: AppColors.primary,
                    ),
                    title: Text(reason, style: AppTypography.body2.copyWith(color: Colors.white)),
                    onTap: () => setDialogState(() => selectedReason = reason),
                  )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selectedReason.isEmpty
                  ? null
                  : () {
                      ref.read(partnerProvider.notifier).rejectOrder(orderId, selectedReason);
                      Navigator.pop(context);
                    },
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      ('📋', 'Orders', '/partner/orders'),
      ('🍽️', 'Menu', '/partner/menu'),
      ('📊', 'Analytics', '/partner/analytics'),
      ('⚙️', 'Settings', '/partner/settings'),
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
          children: actions.map((action) {
            return GestureDetector(
              onTap: () => context.go(action.$3),
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
                      child: Text(
                        action.$1,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    action.$2,
                    style: AppTypography.overline.copyWith(fontSize: 10),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    ).animate(delay: 400.ms).fadeIn();
  }

  /// Connection status banner — shows when Realtime is degraded
  Widget _buildConnectionBanner(RealtimeConnectionStatus status) {
    final isPolling = status == RealtimeConnectionStatus.polling;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: (isPolling ? AppColors.warning : AppColors.error)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: (isPolling ? AppColors.warning : AppColors.error)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPolling ? Icons.sync_rounded : Icons.cloud_off_rounded,
            size: 16,
            color: isPolling ? AppColors.warning : AppColors.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isPolling
                  ? 'Live updates limited — refreshing every 15s'
                  : 'Connection lost — updates paused',
              style: AppTypography.caption.copyWith(
                color: isPolling ? AppColors.warning : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  /// New order alert banner
  Widget _buildNewOrderBanner(
      BuildContext context, WidgetRef ref, int count) {
    return GestureDetector(
      onTap: () {
        ref.read(partnerProvider.notifier).acknowledgeNewOrders();
        context.go('/partner/orders');
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.15),
              AppColors.primary.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('🔔', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count new order${count > 1 ? 's' : ''}!',
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'Tap to view and accept',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).shake(
          hz: 3,
          duration: 600.ms,
          offset: const Offset(2, 0),
        );
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
    return Semantics(
      label: '$label: $value',
      child: GlassCard(
      child: Column(
        children: [
          ExcludeSemantics(child: Text(emoji, style: const TextStyle(fontSize: 24))),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: AppTypography.h3.copyWith(color: color, fontSize: 18),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.overline.copyWith(fontSize: 9),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
    );
  }
}

class _QuickOrderCard extends StatelessWidget {
  final PartnerOrder partnerOrder;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onTap;

  const _QuickOrderCard({
    required this.partnerOrder,
    required this.onAccept,
    required this.onReject,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final order = partnerOrder.order;
    final itemsSummary = order.items.map((i) => '${i.name} times ${i.quantity}').join(', ');

    return Semantics(
      label: 'Order ${order.orderNumber}, $itemsSummary, '
          'total \u20b9${order.grandTotal.toInt()}, status ${order.status.label}',
      child: GestureDetector(
      onTap: onTap,
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExcludeSemantics(child: Text(order.status.emoji, style: const TextStyle(fontSize: 20))),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    order.orderNumber,
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.status.label,
                    style: AppTypography.overline.copyWith(
                      color: _statusColor,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              order.items.map((i) => '${i.name} × ${i.quantity}').join(', '),
              style: AppTypography.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₹${order.grandTotal.toInt()}',
                  style: AppTypography.price,
                ),
                if (partnerOrder.isNew)
                  Row(
                    children: [
                      SizedBox(
                        height: 30,
                        child: TextButton(
                          onPressed: onReject,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Reject',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 30,
                        child: ElevatedButton(
                          onPressed: onAccept,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Accept',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }

  Color get _statusColor {
    switch (partnerOrder.order.status) {
      case OrderStatus.placed:
        return AppColors.warning;
      case OrderStatus.confirmed:
      case OrderStatus.preparing:
        return AppColors.info;
      case OrderStatus.ready:
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }
}

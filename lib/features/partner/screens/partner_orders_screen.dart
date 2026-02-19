import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../../../features/orders/models/order.dart';
import '../models/partner_order.dart';
import '../providers/partner_provider.dart';

/// Partner order management — tabs for New, Preparing, Ready, Completed
class PartnerOrdersScreen extends ConsumerStatefulWidget {
  const PartnerOrdersScreen({super.key});

  @override
  ConsumerState<PartnerOrdersScreen> createState() =>
      _PartnerOrdersScreenState();
}

class _PartnerOrdersScreenState extends ConsumerState<PartnerOrdersScreen> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Refresh countdown display every second
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
    final partnerState = ref.watch(partnerProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Order Management'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('New'),
                    if (partnerState.newOrders.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${partnerState.newOrders.length}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Tab(text: 'Preparing (${partnerState.preparingOrders.length})'),
              Tab(text: 'Ready (${partnerState.readyOrders.length})'),
              Tab(text: 'Completed (${partnerState.completedOrders.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // New orders
            _buildOrderList(
              partnerState.newOrders,
              'No new orders',
              'Waiting for orders',
            ),

            // Preparing
            _buildOrderList(
              partnerState.preparingOrders,
              'None preparing',
              'Accepted orders being prepared will show here',
            ),

            // Ready
            _buildOrderList(
              partnerState.readyOrders,
              'None ready',
              'Orders ready for pickup will show here',
            ),

            // Completed
            _buildOrderList(
              partnerState.completedOrders,
              'No completed orders',
              'Completed orders will appear here',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList(
    List<PartnerOrder> orders,
    String emptyTitle,
    String emptySubtitle,
  ) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📭', style: TextStyle(fontSize: 48)),
            const SizedBox(height: AppSpacing.xl),
            Text(emptyTitle, style: AppTypography.h3),
            const SizedBox(height: AppSpacing.sm),
            Text(
              emptySubtitle,
              style: AppTypography.body2,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.xl),
      itemCount: orders.length,
      itemBuilder: (context, index) => _buildOrderCard(orders[index], index),
    );
  }

  Widget _buildOrderCard(PartnerOrder po, int index) {
    final order = po.order;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with timer
            Row(
              children: [
                Text(order.status.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.orderNumber,
                        style: AppTypography.body1.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '₹${order.grandTotal.toInt()} · ${order.paymentMethod.toUpperCase()}',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),

                // Countdown timer for new orders
                if (po.isNew && po.secondsRemaining > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: po.secondsRemaining < 30
                          ? AppColors.error.withValues(alpha: 0.15)
                          : AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: po.secondsRemaining < 30
                            ? AppColors.error
                            : AppColors.warning,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_rounded,
                          size: 14,
                          color: po.secondsRemaining < 30
                              ? AppColors.error
                              : AppColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${po.secondsRemaining}s',
                          style: AppTypography.buttonSmall.copyWith(
                            color: po.secondsRemaining < 30
                                ? AppColors.error
                                : AppColors.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const Divider(color: AppColors.divider, height: AppSpacing.xl),

            // Items
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: item.isVeg ? AppColors.veg : AppColors.nonVeg,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: item.isVeg
                                ? AppColors.veg
                                : AppColors.nonVeg,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${item.name} × ${item.quantity}',
                        style: AppTypography.body2,
                      ),
                    ),
                    Text(
                      '₹${(item.price * item.quantity).toInt()}',
                      style: AppTypography.body2,
                    ),
                  ],
                ),
              ),
            ),

            // Special instructions
            if (order.specialInstructions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.note_rounded,
                      size: 14,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        order.specialInstructions,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // Actions
            _buildActionButtons(po),
          ],
        ),
      ),
    ).animate(delay: (index * 80).ms).fadeIn().slideY(begin: 0.03);
  }

  Widget _buildActionButtons(PartnerOrder po) {
    if (po.isNew) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _showRejectDialog(po.order.id),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
              child: const Text('Reject'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: ChizzeButton(
              label: 'Accept Order',
              icon: Icons.check_rounded,
              onPressed: () =>
                  ref.read(partnerProvider.notifier).acceptOrder(po.order.id),
            ),
          ),
        ],
      );
    }

    if (po.order.status == OrderStatus.confirmed ||
        po.order.status == OrderStatus.preparing) {
      return ChizzeButton(
        label: po.order.status == OrderStatus.confirmed
            ? 'Start Preparing'
            : 'Mark Ready for Pickup',
        icon: po.order.status == OrderStatus.confirmed
            ? Icons.restaurant_rounded
            : Icons.check_circle_rounded,
        onPressed: () {
          if (po.order.status == OrderStatus.confirmed) {
            ref.read(partnerProvider.notifier).markPreparing(po.order.id);
          } else {
            ref.read(partnerProvider.notifier).markReady(po.order.id);
          }
        },
      );
    }

    if (po.order.status == OrderStatus.ready) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Waiting for pickup',
              style: AppTypography.body2.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  void _showRejectDialog(String orderId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Reject Order?'),
        content: const Text('Are you sure you want to reject this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(partnerProvider.notifier)
                  .rejectOrder(orderId, 'Too busy');
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}

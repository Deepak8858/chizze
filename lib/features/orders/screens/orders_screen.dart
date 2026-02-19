import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';

/// Orders history screen — active + past orders
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersState = ref.watch(ordersProvider);
    final activeOrders = ordersState.activeOrders;
    final pastOrders = ordersState.pastOrders;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('My Orders'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Active (${activeOrders.length})'),
              Tab(text: 'Past (${pastOrders.length})'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Active orders
            activeOrders.isEmpty
                ? _buildEmptyState(
                    'No active orders',
                    'Your current orders will appear here',
                    Icons.delivery_dining_rounded,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    itemCount: activeOrders.length,
                    itemBuilder: (context, index) => _buildOrderCard(
                      context,
                      activeOrders[index],
                      index,
                      isActive: true,
                    ),
                  ),

            // Past orders
            pastOrders.isEmpty
                ? _buildEmptyState(
                    'No past orders',
                    'Your order history will appear here',
                    Icons.receipt_long_rounded,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    itemCount: pastOrders.length,
                    itemBuilder: (context, index) => _buildOrderCard(
                      context,
                      pastOrders[index],
                      index,
                      isActive: false,
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.xl),
          Text(title, style: AppTypography.h3),
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle, style: AppTypography.body2),
        ],
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    Order order,
    int index, {
    required bool isActive,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        onTap: () {
          if (isActive) {
            context.push('/order-tracking/${order.id}');
          } else {
            context.push('/order-detail/${order.id}');
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(order.status.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.restaurantName,
                        style: AppTypography.body1.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(order.orderNumber, style: AppTypography.caption),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.status.label,
                    style: AppTypography.overline.copyWith(
                      color: _statusColor(order.status),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(color: AppColors.divider, height: AppSpacing.xl),

            // Items preview
            ...order.items
                .take(2)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '${item.name} × ${item.quantity}',
                      style: AppTypography.body2,
                    ),
                  ),
                ),
            if (order.items.length > 2)
              Text(
                '+${order.items.length - 2} more items',
                style: AppTypography.caption.copyWith(color: AppColors.primary),
              ),

            const SizedBox(height: AppSpacing.md),

            // Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDate(order.placedAt), style: AppTypography.caption),
                Text(
                  '₹${order.grandTotal.toInt()}',
                  style: AppTypography.price,
                ),
              ],
            ),

            // Reorder button for past orders
            if (!isActive && order.status == OrderStatus.delivered) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reorder coming soon!')),
                        );
                      },
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: const Text('Reorder'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/review/${order.id}'),
                      icon: const Icon(Icons.star_rounded, size: 16),
                      label: const Text('Rate'),
                    ),
                  ),
                ],
              ),
            ],

            // Track button for active orders
            if (isActive) ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/order-tracking/${order.id}'),
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: const Text('Track Order'),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate(delay: (index * 80).ms).fadeIn().slideY(begin: 0.03);
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.placed:
      case OrderStatus.confirmed:
        return AppColors.info;
      case OrderStatus.preparing:
      case OrderStatus.ready:
        return AppColors.warning;
      case OrderStatus.pickedUp:
      case OrderStatus.outForDelivery:
        return AppColors.primary;
      case OrderStatus.delivered:
        return AppColors.success;
      case OrderStatus.cancelled:
        return AppColors.error;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }
}

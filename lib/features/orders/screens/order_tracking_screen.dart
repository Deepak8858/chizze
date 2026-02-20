import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../../../shared/widgets/delivery_map.dart';
import '../models/order.dart';
import '../providers/orders_provider.dart';
import '../providers/rider_location_provider.dart';

/// Real-time order tracking screen
class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  Timer? _demoTimer;
  bool _trackingStarted = false;

  @override
  void initState() {
    super.initState();
    _startDemoProgression();
    // Start rider tracking for the live map
    ref.read(riderLocationProvider.notifier).trackRider('mock_rider');
    _trackingStarted = true;
  }

  void _startDemoProgression() {
    int step = 0;
    final statuses = [
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.pickedUp,
      OrderStatus.outForDelivery,
      OrderStatus.delivered,
    ];

    _demoTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (step < statuses.length) {
        ref
            .read(ordersProvider.notifier)
            .updateOrderStatus(widget.orderId, statuses[step]);
        step++;
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    if (_trackingStarted) {
      // Use a post-frame callback to safely read the provider
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(riderLocationProvider.notifier).stopTracking();
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersState = ref.watch(ordersProvider);
    final order = ordersState.orders
        .where((o) => o.id == widget.orderId)
        .firstOrNull;

    if (order == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Order Tracking')),
        body: const Center(child: Text('Order not found')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Order #${order.orderNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Support coming soon!')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Live Map ───
            if (order.status.index >= OrderStatus.pickedUp.index &&
                order.status != OrderStatus.cancelled)
              Builder(
                builder: (context) {
                  final riderLocation = ref.watch(riderLocationProvider);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    child: DeliveryMap(
                      height: 220,
                      trackRider: true,
                      markers: [
                        const MapMarker(
                          type: MapMarkerType.restaurant,
                          latitude: 17.4486,
                          longitude: 78.3810,
                          label: 'Restaurant',
                        ),
                        MapMarker(
                          type: MapMarkerType.rider,
                          latitude: riderLocation?.latitude ?? 17.4440,
                          longitude: riderLocation?.longitude ?? 78.3860,
                          label: order.deliveryPartnerName ?? 'Rider',
                        ),
                        const MapMarker(
                          type: MapMarkerType.customer,
                          latitude: 17.4401,
                          longitude: 78.3911,
                          label: 'You',
                        ),
                      ],
                    ).animate().fadeIn(duration: 400.ms),
                  );
                },
              ),

            // ─── Status Header ───
            _buildStatusHeader(order),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Progress Timeline ───
            _buildProgressTimeline(order),

            const SizedBox(height: AppSpacing.xxl),

            // ─── ETA Card ───
            _buildETACard(order),

            const SizedBox(height: AppSpacing.xl),

            // ─── Delivery Partner ───
            if (order.status.index >= OrderStatus.pickedUp.index)
              _buildDeliveryPartner(order),

            const SizedBox(height: AppSpacing.xl),

            // ─── Order Items ───
            _buildOrderItems(order),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Actions ───
            if (order.status == OrderStatus.delivered) ...[
              ChizzeButton(
                label: 'Rate this Order',
                icon: Icons.star_rounded,
                onPressed: () => context.push('/review/${order.id}'),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            Center(
              child: TextButton(
                onPressed: () => context.go('/home'),
                child: Text(
                  'Back to Home',
                  style: AppTypography.button.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(Order order) {
    return GlassCard(
      child: Row(
        children: [
          Text(order.status.emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.status.label, style: AppTypography.h2),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _statusDescription(order.status),
                  style: AppTypography.body2,
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildProgressTimeline(Order order) {
    final allStatuses = [
      OrderStatus.placed,
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.pickedUp,
      OrderStatus.outForDelivery,
      OrderStatus.delivered,
    ];

    return Column(
      children: allStatuses.asMap().entries.map((entry) {
        final index = entry.key;
        final status = entry.value;
        final isCompleted = order.status.index >= status.index;
        final isCurrent = order.status == status;
        final isLast = index == allStatuses.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline dot + line
            Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: isCurrent ? 28 : 20,
                  height: isCurrent ? 28 : 20,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.primary
                        : AppColors.surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCompleted
                          ? AppColors.primary
                          : AppColors.divider,
                      width: isCurrent ? 3 : 1.5,
                    ),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: isCompleted
                      ? const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.white,
                        )
                      : null,
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 32,
                    color: isCompleted ? AppColors.primary : AppColors.divider,
                  ),
              ],
            ),

            const SizedBox(width: AppSpacing.md),

            // Label
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: isCurrent ? 3 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${status.emoji} ${status.label}',
                      style: AppTypography.body1.copyWith(
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isCompleted
                            ? Colors.white
                            : AppColors.textTertiary,
                      ),
                    ),
                    if (!isLast) const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildETACard(Order order) {
    final etaMin = order.status == OrderStatus.delivered
        ? 0
        : order.estimatedDeliveryMin;

    return GlassCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.access_time_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.status == OrderStatus.delivered
                      ? 'Delivered!'
                      : 'Estimated Delivery',
                  style: AppTypography.caption,
                ),
                Text(
                  order.status == OrderStatus.delivered
                      ? '✅ Your order has arrived'
                      : '$etaMin min',
                  style: AppTypography.h3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryPartner(Order order) {
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                order.deliveryPartnerName?.isNotEmpty == true
                    ? order.deliveryPartnerName![0]
                    : 'D',
                style: AppTypography.h3.copyWith(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.deliveryPartnerName ?? 'Delivery Partner',
                  style: AppTypography.body1.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text('Your delivery partner', style: AppTypography.caption),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone_rounded, color: AppColors.success),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Calling partner...')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat_rounded, color: AppColors.info),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chat coming soon!')),
              );
            },
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideX(begin: 0.05);
  }

  Widget _buildOrderItems(Order order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Order from ${order.restaurantName}',
          style: AppTypography.h3.copyWith(fontSize: 16),
        ),
        const SizedBox(height: AppSpacing.md),
        ...order.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                        color: item.isVeg ? AppColors.veg : AppColors.nonVeg,
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
        const Divider(color: AppColors.divider),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total',
              style: AppTypography.body1.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '₹${order.grandTotal.toInt()}',
              style: AppTypography.priceLarge,
            ),
          ],
        ),
      ],
    );
  }

  String _statusDescription(OrderStatus status) {
    switch (status) {
      case OrderStatus.placed:
        return 'Waiting for restaurant to confirm';
      case OrderStatus.confirmed:
        return 'Restaurant has accepted your order';
      case OrderStatus.preparing:
        return 'Chef is preparing your food';
      case OrderStatus.ready:
        return 'Food is packed and ready for pickup';
      case OrderStatus.pickedUp:
        return 'Delivery partner has picked up your order';
      case OrderStatus.outForDelivery:
        return 'Your food is on the way!';
      case OrderStatus.delivered:
        return 'Enjoy your meal! 🍽️';
      case OrderStatus.cancelled:
        return 'This order was cancelled';
    }
  }
}

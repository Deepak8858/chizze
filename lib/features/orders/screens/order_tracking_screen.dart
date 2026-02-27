import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/route_service.dart';
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
  bool _trackingStarted = false;
  String? _lastKnownRiderId;
  bool _fetchAttempted = false;
  Timer? _pollTimer;

  List<List<double>>? _routeCoordinates;
  double? _lastRouteOriginLat;
  double? _lastRouteOriginLng;
  double? _lastRouteDestLat;
  double? _lastRouteDestLng;

  void _fetchRouteIfNeeded(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) {
    if (_lastRouteOriginLat != null &&
        (originLat - _lastRouteOriginLat!).abs() < 0.0005 &&
        (originLng - _lastRouteOriginLng!).abs() < 0.0005 &&
        (destLat - _lastRouteDestLat!).abs() < 0.0005 &&
        (destLng - _lastRouteDestLng!).abs() < 0.0005) {
      return;
    }
    _lastRouteOriginLat = originLat;
    _lastRouteOriginLng = originLng;
    _lastRouteDestLat = destLat;
    _lastRouteDestLng = destLng;

    RouteService.instance
        .getRoute(
          originLat: originLat,
          originLng: originLng,
          destLat: destLat,
          destLng: destLng,
        )
        .then((coords) {
          if (mounted && coords != null) {
            setState(() => _routeCoordinates = coords);
          }
        });
  }

  /// Polling interval for fetching the latest order status.
  /// Acts as a fallback when Appwrite Realtime / WebSocket push is unreliable.
  static const _pollInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    // If order is not in local state, fetch it from the API
    _ensureOrderLoaded();
    // Start rider tracking using the order's actual rider ID
    _startTracking();
    // Start periodic polling as a reliable fallback for push channels
    _startPolling();
  }

  void _ensureOrderLoaded() {
    final ordersState = ref.read(ordersProvider);
    final order = ordersState.orders
        .where((o) => o.id == widget.orderId)
        .firstOrNull;
    if (order == null && !_fetchAttempted) {
      _fetchAttempted = true;
      ref.read(ordersProvider.notifier).fetchOrderById(widget.orderId);
    }
  }

  void _startTracking() {
    final ordersState = ref.read(ordersProvider);
    final order = ordersState.orders
        .where((o) => o.id == widget.orderId)
        .firstOrNull;
    final riderId = order?.deliveryPartnerId;
    if (riderId != null && riderId.isNotEmpty && riderId != _lastKnownRiderId) {
      if (_trackingStarted) {
        ref.read(riderLocationProvider.notifier).stopTracking();
      }
      ref.read(riderLocationProvider.notifier).trackRider(riderId);
      _trackingStarted = true;
      _lastKnownRiderId = riderId;
    }
  }

  /// Periodically fetch the latest order from the API. This guarantees the
  /// customer sees status changes even when Appwrite Realtime or WebSocket
  /// push channels are temporarily disconnected.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      // Stop polling once the order reaches a terminal state
      final order = ref
          .read(ordersProvider)
          .orders
          .where((o) => o.id == widget.orderId)
          .firstOrNull;
      if (order != null && !order.status.isActive) {
        _stopPolling();
        return;
      }
      ref.read(ordersProvider.notifier).fetchOrderById(widget.orderId);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _stopPolling();
    if (_trackingStarted) {
      ref.read(riderLocationProvider.notifier).stopTracking();
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
      // Show loading while we fetch the order from the API
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Order Tracking')),
        body: ordersState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Order not found'),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        ref.read(ordersProvider.notifier).fetchOrderById(widget.orderId);
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
      );
    }

    // Restart tracking when a delivery partner is assigned or changes
    final currentRiderId = order.deliveryPartnerId;
    if (currentRiderId != null &&
        currentRiderId.isNotEmpty &&
        currentRiderId != _lastKnownRiderId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startTracking());
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
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(ordersProvider.notifier)
            .fetchOrderById(widget.orderId)
            .then((_) {}),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Live Map ───
            if (order.status.index >= OrderStatus.pickedUp.index &&
                order.status != OrderStatus.cancelled &&
                order.restaurantLatitude != null &&
                order.restaurantLongitude != null &&
                order.deliveryLatitude != null &&
                order.deliveryLongitude != null)
              Builder(
                builder: (context) {
                  final riderLocation = ref.watch(riderLocationProvider);
                  // Use midpoint of restaurant and customer as rider fallback
                  final fallbackLat = (order.restaurantLatitude! + order.deliveryLatitude!) / 2;
                  final fallbackLng = (order.restaurantLongitude! + order.deliveryLongitude!) / 2;
                    // Fetch route between rider and customer
                    final rLat = riderLocation?.latitude ?? fallbackLat;
                    final rLng = riderLocation?.longitude ?? fallbackLng;
                    _fetchRouteIfNeeded(
                      rLat,
                      rLng,
                      order.deliveryLatitude!,
                      order.deliveryLongitude!,
                    );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    child: DeliveryMap(
                      height: 220,
                      trackRider: true,
                        routeCoordinates: _routeCoordinates,
                      markers: [
                        MapMarker(
                          type: MapMarkerType.restaurant,
                          latitude: order.restaurantLatitude!,
                          longitude: order.restaurantLongitude!,
                          label: order.restaurantName,
                        ),
                        MapMarker(
                          type: MapMarkerType.rider,
                          latitude: riderLocation?.latitude ?? fallbackLat,
                          longitude: riderLocation?.longitude ?? fallbackLng,
                          label: order.deliveryPartnerName ?? 'Rider',
                        ),
                        MapMarker(
                          type: MapMarkerType.customer,
                          latitude: order.deliveryLatitude!,
                          longitude: order.deliveryLongitude!,
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
            if (order.deliveryPartnerId != null &&
                order.deliveryPartnerId!.isNotEmpty)
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
                  _statusDescription(order.status, order: order),
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
            onPressed: () async {
              final phone = order.deliveryPartnerPhone;
              if (phone != null && phone.isNotEmpty) {
                await Permission.phone.request();
                launchUrl(Uri.parse('tel:$phone'));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Phone number not available yet'),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat_rounded, color: AppColors.info),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('In-app chat coming soon! Use the phone button to call your rider.'),
                ),
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

  String _statusDescription(OrderStatus status, {Order? order}) {
    switch (status) {
      case OrderStatus.placed:
        return 'Waiting for restaurant to confirm';
      case OrderStatus.confirmed:
        return 'Restaurant has accepted your order';
      case OrderStatus.preparing:
        return 'Chef is preparing your food';
      case OrderStatus.ready:
        if (order?.deliveryPartnerId != null &&
            order!.deliveryPartnerId!.isNotEmpty) {
          final name = order.deliveryPartnerName ?? 'A delivery partner';
          return '$name is on the way to pick up your order';
        }
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

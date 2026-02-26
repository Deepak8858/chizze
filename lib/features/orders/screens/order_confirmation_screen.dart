import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../providers/orders_provider.dart';

/// Post-payment order confirmation with animated success
class OrderConfirmationScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderConfirmationScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends ConsumerState<OrderConfirmationScreen> {
  bool _fetchAttempted = false;

  @override
  void initState() {
    super.initState();
    _ensureOrderLoaded();
  }

  void _ensureOrderLoaded() {
    final ordersState = ref.read(ordersProvider);
    final order = ordersState.orders.where((o) => o.id == widget.orderId).firstOrNull;
    if (order == null && !_fetchAttempted) {
      _fetchAttempted = true;
      ref.read(ordersProvider.notifier).fetchOrderById(widget.orderId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersState = ref.watch(ordersProvider);
    final order = ordersState.orders.where((o) => o.id == widget.orderId).firstOrNull;
    final orderId = widget.orderId;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // ─── Success Animation ───
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 64,
                  color: AppColors.success,
                ),
              ).animate().scale(
                begin: const Offset(0.5, 0.5),
                duration: 500.ms,
                curve: Curves.elasticOut,
              ),

              const SizedBox(height: AppSpacing.xxl),

              Text(
                'Order Placed! 🎉',
                style: AppTypography.h1,
              ).animate(delay: 300.ms).fadeIn(),

              const SizedBox(height: AppSpacing.md),

              Text(
                order != null
                    ? 'Order #${order.orderNumber}'
                    : 'Your order has been placed',
                style: AppTypography.body1.copyWith(color: AppColors.primary),
              ).animate(delay: 400.ms).fadeIn(),

              const SizedBox(height: AppSpacing.sm),

              Text(
                'Your food is being prepared and will\nreach you in ~${order?.estimatedDeliveryMin ?? 35} minutes',
                style: AppTypography.body2,
                textAlign: TextAlign.center,
              ).animate(delay: 500.ms).fadeIn(),

              const SizedBox(height: AppSpacing.xxl),

              // ─── Order Details Card ───
              if (order != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    children: [
                      _DetailRow('Restaurant', order.restaurantName),
                      _DetailRow('Items', '${order.items.length} items'),
                      _DetailRow(
                        'Payment',
                        order.paymentMethod == 'cod'
                            ? 'Cash on Delivery'
                            : 'Paid Online',
                      ),
                      const Divider(
                        color: AppColors.divider,
                        height: AppSpacing.xl,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total',
                            style: AppTypography.body1.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '₹${order.grandTotal.toInt()}',
                            style: AppTypography.priceLarge,
                          ),
                        ],
                      ),
                    ],
                  ),
                ).animate(delay: 600.ms).fadeIn().slideY(begin: 0.1),

              const Spacer(),

              // ─── Actions ───
              ChizzeButton(
                label: 'Track Order',
                icon: Icons.delivery_dining_rounded,
                onPressed: () => context.go('/order-tracking/$orderId'),
              ).animate(delay: 700.ms).fadeIn(),

              const SizedBox(height: AppSpacing.md),

              TextButton(
                onPressed: () => context.go('/home'),
                child: Text(
                  'Back to Home',
                  style: AppTypography.button.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ).animate(delay: 800.ms).fadeIn(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body2),
          Text(
            value,
            style: AppTypography.body2.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

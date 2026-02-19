import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../../cart/providers/cart_provider.dart';
import '../providers/payment_provider.dart';
import '../../orders/providers/orders_provider.dart';

/// Payment method selection + Razorpay checkout
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String _selectedMethod = 'razorpay'; // razorpay | cod
  double _tip = 0;

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final paymentState = ref.watch(paymentProvider);

    // Listen for payment success → navigate to confirmation
    ref.listen<PaymentState>(paymentProvider, (prev, next) {
      if (next.isSuccess && !(prev?.isSuccess ?? false)) {
        final order = ref
            .read(paymentProvider.notifier)
            .createOrderFromCart(cartState);
        ref.read(ordersProvider.notifier).addOrder(order);
        context.go('/order-confirmation/${order.id}');
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Payment')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Order Summary ───
                  _buildOrderSummary(cartState),

                  const SizedBox(height: AppSpacing.xxl),

                  // ─── Tip ───
                  _buildTipSection(),

                  const SizedBox(height: AppSpacing.xxl),

                  // ─── Payment Method ───
                  Text(
                    'Payment Method',
                    style: AppTypography.h3.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  _PaymentMethodCard(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Pay Online',
                    subtitle: 'UPI · Cards · Wallets · Net Banking',
                    isSelected: _selectedMethod == 'razorpay',
                    onTap: () => setState(() => _selectedMethod = 'razorpay'),
                    badge: 'Razorpay',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _PaymentMethodCard(
                    icon: Icons.money_rounded,
                    label: 'Cash on Delivery',
                    subtitle: 'Pay when your food arrives',
                    isSelected: _selectedMethod == 'cod',
                    onTap: () => setState(() => _selectedMethod = 'cod'),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // ─── Error ───
                  if (paymentState.error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.base),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              paymentState.error!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ─── Pay Button ───
          _buildPayBar(cartState, paymentState),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(CartState cartState) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.restaurant_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  cartState.restaurantName ?? 'Restaurant',
                  style: AppTypography.body1.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${cartState.totalItems} items',
                style: AppTypography.caption,
              ),
            ],
          ),
          const Divider(color: AppColors.divider, height: AppSpacing.xl),
          ...cartState.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  _VegDot(isVeg: item.menuItem.isVeg),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${item.menuItem.name} × ${item.quantity}',
                      style: AppTypography.body2,
                    ),
                  ),
                  Text(
                    '₹${item.totalPrice.toInt()}',
                    style: AppTypography.body2,
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: AppColors.divider, height: AppSpacing.xl),
          _PriceRow('Item Total', '₹${cartState.itemTotal.toInt()}'),
          _PriceRow(
            'Delivery Fee',
            cartState.deliveryFee == 0
                ? 'FREE'
                : '₹${cartState.deliveryFee.toInt()}',
            color: cartState.deliveryFee == 0 ? AppColors.success : null,
          ),
          _PriceRow('Platform Fee', '₹${cartState.platformFee.toInt()}'),
          _PriceRow('GST', '₹${cartState.gst.toInt()}'),
          if (_tip > 0) _PriceRow('Delivery Tip', '₹${_tip.toInt()}'),
          if (cartState.discount > 0)
            _PriceRow(
              'Discount',
              '-₹${cartState.discount.toInt()}',
              color: AppColors.success,
            ),
        ],
      ),
    );
  }

  Widget _buildTipSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🙏', style: TextStyle(fontSize: 18)),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Tip your delivery partner',
              style: AppTypography.body1.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your kindness means a lot! 100% goes to them.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [0, 20, 30, 50].map((amount) {
            final isSelected = _tip == amount.toDouble();
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: amount != 50 ? AppSpacing.sm : 0,
                ),
                child: GestureDetector(
                  onTap: () => setState(() => _tip = amount.toDouble()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        amount == 0 ? 'None' : '₹$amount',
                        style: AppTypography.buttonSmall.copyWith(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPayBar(CartState cartState, PaymentState paymentState) {
    final total = cartState.grandTotal + _tip;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total', style: AppTypography.caption),
              Text(
                '₹${total.toInt()}',
                style: AppTypography.priceLarge.copyWith(fontSize: 22),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.xl),
          Expanded(
            child: ChizzeButton(
              label: paymentState.isProcessing
                  ? 'Processing...'
                  : _selectedMethod == 'cod'
                  ? 'Place COD Order'
                  : 'Pay Now',
              icon: _selectedMethod == 'cod'
                  ? Icons.check_rounded
                  : Icons.lock_rounded,
              isLoading: paymentState.isProcessing,
              onPressed: paymentState.isProcessing
                  ? null
                  : () => _handlePayment(cartState, total),
            ),
          ),
        ],
      ),
    );
  }

  void _handlePayment(CartState cartState, double total) {
    if (_selectedMethod == 'cod') {
      // COD — create order directly
      final order = ref
          .read(paymentProvider.notifier)
          .createOrderFromCart(cartState);
      ref.read(ordersProvider.notifier).addOrder(order);
      ref.read(cartProvider.notifier).clearCart();
      context.go('/order-confirmation/${order.id}');
    } else {
      // Razorpay — open payment gateway
      ref
          .read(paymentProvider.notifier)
          .startPayment(
            amount: total,
            customerEmail: 'customer@chizze.in',
            customerPhone: '+919876543210',
            customerName: 'Chizze Customer',
            description: 'Order from ${cartState.restaurantName}',
            onSuccess: () {
              // handled in ref.listen above
            },
          );
    }
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badge;

  const _PaymentMethodCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: AppTypography.body1.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: AppTypography.overline.copyWith(
                              color: AppColors.info,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.caption),
                ],
              ),
            ),
            Radio<bool>(
              value: true,
              groupValue: isSelected,
              onChanged: (_) => onTap(),
              activeColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _VegDot extends StatelessWidget {
  final bool isVeg;
  const _VegDot({required this.isVeg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        border: Border.all(
          color: isVeg ? AppColors.veg : AppColors.nonVeg,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: isVeg ? AppColors.veg : AppColors.nonVeg,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _PriceRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body2),
          Text(
            value,
            style: AppTypography.body2.copyWith(
              color: color ?? Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../../cart/providers/cart_provider.dart';
import '../../profile/providers/address_provider.dart';
import '../../profile/providers/user_profile_provider.dart';
import '../providers/payment_provider.dart';
import '../../orders/providers/orders_provider.dart';
import '../../orders/models/order.dart';

/// Payment method selection + Razorpay checkout
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String _selectedMethod = 'online'; // online | cod
  double _tip = 0;

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final paymentState = ref.watch(paymentProvider);

    // Listen for payment success → navigate to confirmation
    ref.listen<PaymentState>(paymentProvider, (prev, next) {
      if (next.isSuccess && !(prev?.isSuccess ?? false)) {
        final orderId = next.orderId ?? '';
        ref.read(cartProvider.notifier).clearCart();
        // Fetch the newly created order so it's available immediately
        ref.read(ordersProvider.notifier).fetchOrderById(orderId);
        context.go('/order-confirmation/$orderId');
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
                  // ─── Delivery Address ───
                  _buildDeliveryAddressSection(context, ref),

                  const SizedBox(height: AppSpacing.xxl),

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
                    isSelected: _selectedMethod == 'online',
                    onTap: () => setState(() => _selectedMethod = 'online'),
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

  Widget _buildDeliveryAddressSection(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressProvider);
    final profile = ref.watch(userProfileProvider);
    final defaultAddr = addresses.where((a) => a.isDefault).firstOrNull ??
        (addresses.isNotEmpty ? addresses.first : null);

    final label = defaultAddr?.label ?? 'Home';
    final addressText = defaultAddr?.fullAddress ??
        (profile.address.isNotEmpty ? profile.address : null);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Delivering to',
                style: AppTypography.body1.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/addresses'),
                child: Text(
                  addressText != null ? 'Change' : 'Add Address',
                  style: AppTypography.buttonSmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (addressText != null) ...[
            Text(
              label,
              style: AppTypography.body2.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              addressText,
              style: AppTypography.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Center(
                child: Text(
                  'No delivery address set. Tap "Add Address" above.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ),
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

  Future<void> _handlePayment(CartState cartState, double total) async {
    final authState = ref.read(authProvider);
    final userName = authState.user?.name ?? 'Chizze Customer';
    final userEmail = authState.user?.email ?? '';
    final userPhone = authState.user?.phone ?? '';

    // Get default delivery address — fall back to user profile address
    final addresses = ref.read(addressProvider);
    final profile = ref.read(userProfileProvider);
    var defaultAddress = addresses.isNotEmpty
        ? addresses.firstWhere(
            (a) => a.isDefault,
            orElse: () => addresses.first,
          )
        : null;

    // If no saved address exists but profile has address data, auto-create one
    if (defaultAddress == null && profile.address.isNotEmpty) {
      final created = await ref.read(addressProvider.notifier).addAddressAsync(
        SavedAddress(
          id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          label: 'Home',
          fullAddress: profile.address,
          latitude: profile.latitude,
          longitude: profile.longitude,
          isDefault: true,
        ),
      );
      if (created != null) {
        defaultAddress = created;
      }
    }

    final deliveryAddressId = defaultAddress?.id ?? '';

    if (deliveryAddressId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a delivery address first')),
      );
      context.push('/addresses');
      return;
    }

    final paymentMethod = _selectedMethod == 'cod' ? 'cod' : 'online';

    // Step 1: Create order on backend
    final orderDoc = await ref.read(paymentProvider.notifier).placeBackendOrder(
          cartState: cartState,
          paymentMethod: paymentMethod,
          deliveryAddressId: deliveryAddressId,
          tip: _tip,
          idempotencyKey:
              'order_${DateTime.now().millisecondsSinceEpoch}_${cartState.restaurantId}',
        );

    if (orderDoc == null) return; // error already set in state

    final orderId = orderDoc['\$id'] as String? ?? '';

    if (!mounted) return;

    if (_selectedMethod == 'cod') {
      // COD — order already placed, add to local state immediately & navigate
      ref.read(cartProvider.notifier).clearCart();
      ref.read(ordersProvider.notifier).addOrder(Order.fromMap(orderDoc));
      ref.read(ordersProvider.notifier).fetchOrders(); // background refresh
      context.go('/order-confirmation/$orderId');
    } else {
      // Razorpay — initiate payment with the backend order ID
      await ref.read(paymentProvider.notifier).startPayment(
            orderId: orderId,
            amount: total,
            customerEmail: userEmail,
            customerPhone: userPhone,
            customerName: userName,
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
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
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
              color: color ?? Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

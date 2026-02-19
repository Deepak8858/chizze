import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../providers/cart_provider.dart';

/// Cart & Checkout screen
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartProvider);

    if (cartState.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Cart')),
        body: _buildEmptyCart(context),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(cartState.restaurantName ?? 'Cart'),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clearCart();
            },
            child: Text(
              'Clear',
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Cart Items ───
                  ...cartState.items.asMap().entries.map((entry) {
                    return _buildCartItemCard(ref, entry.value, entry.key);
                  }),

                  const SizedBox(height: AppSpacing.xl),

                  // ─── Special Instructions ───
                  _buildSpecialInstructions(ref, cartState),

                  const SizedBox(height: AppSpacing.xl),

                  // ─── Delivery Instructions ───
                  _buildDeliveryInstructions(ref, cartState),

                  const SizedBox(height: AppSpacing.xl),

                  // ─── Bill Summary ───
                  _buildBillSummary(cartState),
                ],
              ),
            ),
          ),

          // ─── Checkout Bar ───
          _buildCheckoutBar(context, cartState),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🛒', style: TextStyle(fontSize: 64)),
          const SizedBox(height: AppSpacing.xl),
          Text('Your cart is empty', style: AppTypography.h3),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Add items from a restaurant to\nstart building your order',
            style: AppTypography.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          SizedBox(
            width: 200,
            child: ChizzeButton(
              label: 'Browse Restaurants',
              onPressed: () => context.go('/home'),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildCartItemCard(WidgetRef ref, CartItem item, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Veg badge
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                border: Border.all(
                  color: item.menuItem.isVeg ? AppColors.veg : AppColors.nonVeg,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Center(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: item.menuItem.isVeg
                        ? AppColors.veg
                        : AppColors.nonVeg,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),

            const SizedBox(width: AppSpacing.md),

            // Name & customizations
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.menuItem.name,
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.selectedCustomizations.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.selectedCustomizations.entries
                          .expand((e) => e.value.map((o) => o.name))
                          .join(', '),
                      style: AppTypography.caption.copyWith(fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '₹${item.totalPrice.toInt()}',
                    style: AppTypography.price.copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),

            // Quantity controls
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _QuantityButton(
                    icon: Icons.remove,
                    onTap: () {
                      ref
                          .read(cartProvider.notifier)
                          .updateQuantity(item.cartKey, item.quantity - 1);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '${item.quantity}',
                      style: AppTypography.buttonSmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  _QuantityButton(
                    icon: Icons.add,
                    onTap: () {
                      ref
                          .read(cartProvider.notifier)
                          .updateQuantity(item.cartKey, item.quantity + 1);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 60).ms).fadeIn();
  }

  Widget _buildSpecialInstructions(WidgetRef ref, CartState cartState) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.edit_note_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Special Instructions',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            style: AppTypography.body2.copyWith(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'E.g. Less spicy, extra sauce...',
              filled: false,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              isDense: true,
            ),
            maxLines: 2,
            onChanged: (value) {
              ref.read(cartProvider.notifier).setSpecialInstructions(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryInstructions(WidgetRef ref, CartState cartState) {
    final options = [
      ('Leave at door', Icons.door_front_door_rounded),
      ('Call on arrival', Icons.phone_in_talk_rounded),
      ('No contact', Icons.front_hand_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery Instructions',
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: options.map((option) {
            final isSelected = cartState.deliveryInstructions == option.$1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: option != options.last ? AppSpacing.sm : 0,
                ),
                child: GestureDetector(
                  onTap: () {
                    ref
                        .read(cartProvider.notifier)
                        .setDeliveryInstructions(isSelected ? '' : option.$1);
                  },
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
                    child: Column(
                      children: [
                        Icon(
                          option.$2,
                          size: 22,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textTertiary,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          option.$1,
                          style: AppTypography.overline.copyWith(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            fontSize: 9,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
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

  Widget _buildBillSummary(CartState cartState) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bill Details', style: AppTypography.h3.copyWith(fontSize: 16)),
          const SizedBox(height: AppSpacing.base),
          _BillRow(
            label: 'Item Total',
            value: '₹${cartState.itemTotal.toInt()}',
          ),
          _BillRow(
            label: 'Delivery Fee',
            value: cartState.deliveryFee == 0
                ? 'FREE'
                : '₹${cartState.deliveryFee.toInt()}',
            valueColor: cartState.deliveryFee == 0 ? AppColors.success : null,
          ),
          _BillRow(
            label: 'Platform Fee',
            value: '₹${cartState.platformFee.toInt()}',
          ),
          _BillRow(label: 'GST (5%)', value: '₹${cartState.gst.toInt()}'),
          if (cartState.discount > 0)
            _BillRow(
              label: 'Discount (${cartState.couponCode})',
              value: '-₹${cartState.discount.toInt()}',
              valueColor: AppColors.success,
            ),
          const Divider(color: AppColors.divider, height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Grand Total',
                style: AppTypography.body1.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '₹${cartState.grandTotal.toInt()}',
                style: AppTypography.priceLarge.copyWith(fontSize: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutBar(BuildContext context, CartState cartState) {
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
      child: ChizzeButton(
        label: 'Proceed to Payment · ₹${cartState.grandTotal.toInt()}',
        icon: Icons.lock_rounded,
        onPressed: () => context.push('/payment'),
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QuantityButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 16, color: AppColors.primary),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _BillRow({required this.label, required this.value, this.valueColor});

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
            style: AppTypography.body2.copyWith(
              color: valueColor ?? Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

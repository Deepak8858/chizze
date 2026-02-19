import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../models/delivery_partner.dart';
import '../providers/delivery_provider.dart';

/// Active delivery — step-by-step flow with order info
class ActiveDeliveryScreen extends ConsumerWidget {
  const ActiveDeliveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dState = ref.watch(deliveryProvider);
    final delivery = dState.activeDelivery;

    if (delivery == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Active Delivery')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📭', style: TextStyle(fontSize: 48)),
              const SizedBox(height: AppSpacing.xl),
              Text('No active delivery', style: AppTypography.h3),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Accept a delivery request first',
                style: AppTypography.body2,
              ),
              const SizedBox(height: AppSpacing.xl),
              ChizzeButton(
                label: 'Go to Dashboard',
                icon: Icons.dashboard_rounded,
                onPressed: () => context.go('/delivery/dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    final request = delivery.request;
    final step = delivery.currentStep;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(request.order.orderNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_rounded),
            onPressed: () {},
            tooltip: 'Call Support',
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
                  // ─── Step Progress ───
                  _buildStepProgress(step),
                  const SizedBox(height: AppSpacing.xxl),

                  // ─── Current Step Info ───
                  _buildCurrentStepCard(step, request),
                  const SizedBox(height: AppSpacing.xl),

                  // ─── Order Items ───
                  _buildOrderItems(request),
                  const SizedBox(height: AppSpacing.xl),

                  // ─── Earning Info ───
                  _buildEarningCard(request),
                ],
              ),
            ),
          ),

          // ─── Bottom Action ───
          _buildBottomAction(context, ref, delivery),
        ],
      ),
    );
  }

  Widget _buildStepProgress(DeliveryStep currentStep) {
    return GlassCard(
      child: Row(
        children: DeliveryStep.values.map((step) {
          final idx = DeliveryStep.values.indexOf(step);
          final currentIdx = DeliveryStep.values.indexOf(currentStep);
          final isCompleted = idx < currentIdx;
          final isCurrent = idx == currentIdx;

          return Expanded(
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.success
                        : isCurrent
                        ? AppColors.primary
                        : AppColors.surfaceElevated,
                    shape: BoxShape.circle,
                    border: isCurrent
                        ? Border.all(color: AppColors.primary, width: 2)
                        : null,
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          )
                        : Text(
                            step.emoji,
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  step.label.split(' ').first,
                  style: AppTypography.overline.copyWith(
                    fontSize: 8,
                    color: isCurrent
                        ? AppColors.primary
                        : isCompleted
                        ? AppColors.success
                        : AppColors.textTertiary,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildCurrentStepCard(DeliveryStep step, DeliveryRequest request) {
    final isRestaurantStep =
        step == DeliveryStep.goToRestaurant || step == DeliveryStep.pickUp;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(step.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.label,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      isRestaurantStep ? request.restaurantName : 'Customer',
                      style: AppTypography.body2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.divider, height: AppSpacing.xl),
          // Address
          Row(
            children: [
              Icon(
                isRestaurantStep
                    ? Icons.storefront_rounded
                    : Icons.location_on_rounded,
                size: 18,
                color: isRestaurantStep ? AppColors.primary : AppColors.success,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isRestaurantStep
                      ? request.restaurantAddress
                      : request.customerAddress,
                  style: AppTypography.body2,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.navigation_rounded, size: 16),
                  label: const Text('Navigate'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.phone_rounded, size: 16),
                  label: Text(isRestaurantStep ? 'Call' : 'Call'),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.03);
  }

  Widget _buildOrderItems(DeliveryRequest request) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Order Items', style: AppTypography.h3.copyWith(fontSize: 16)),
        const SizedBox(height: AppSpacing.md),
        GlassCard(
          child: Column(
            children: request.order.items.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
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
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        '${item.name} × ${item.quantity}',
                        style: AppTypography.body2,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    ).animate(delay: 300.ms).fadeIn();
  }

  Widget _buildEarningCard(DeliveryRequest request) {
    return GlassCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text(
                  '₹${request.estimatedEarning.toInt()}',
                  style: AppTypography.h3.copyWith(color: AppColors.success),
                ),
                Text('Earning', style: AppTypography.overline),
              ],
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.divider),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${request.distanceKm} km',
                  style: AppTypography.h3.copyWith(color: AppColors.info),
                ),
                Text('Distance', style: AppTypography.overline),
              ],
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.divider),
          Expanded(
            child: Column(
              children: [
                Text(
                  request.order.paymentMethod.toUpperCase(),
                  style: AppTypography.h3.copyWith(
                    color: AppColors.primary,
                    fontSize: 14,
                  ),
                ),
                Text('Payment', style: AppTypography.overline),
              ],
            ),
          ),
        ],
      ),
    ).animate(delay: 400.ms).fadeIn();
  }

  Widget _buildBottomAction(
    BuildContext context,
    WidgetRef ref,
    ActiveDelivery delivery,
  ) {
    final nextStep = delivery.nextStep;
    final isLastStep = nextStep == null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: SafeArea(
        child: ChizzeButton(
          label: isLastStep
              ? '✅  Mark as Delivered'
              : '${nextStep.emoji}  ${nextStep.label}',
          onPressed: () {
            if (isLastStep) {
              ref.read(deliveryProvider.notifier).completeDelivery();
              _showDeliveryComplete(context);
            } else {
              ref.read(deliveryProvider.notifier).advanceStep();
            }
          },
        ),
      ),
    );
  }

  void _showDeliveryComplete(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: AppSpacing.md),
            Text('Delivery Complete!', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Great job! Earnings have been updated.',
              style: AppTypography.body2,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/delivery/dashboard');
            },
            child: const Text('Back to Dashboard'),
          ),
        ],
      ),
    );
  }
}

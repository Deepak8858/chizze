import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../providers/orders_provider.dart';

/// Post-delivery review & rating screen
class ReviewScreen extends ConsumerStatefulWidget {
  final String orderId;
  const ReviewScreen({super.key, required this.orderId});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _foodRating = 0;
  int _deliveryRating = 0;
  final _reviewController = TextEditingController();
  final _selectedTags = <String>{};

  final _tags = [
    '😋 Great Food',
    '🚀 Fast Delivery',
    '📦 Well Packed',
    '😊 Polite Rider',
    '👨‍🍳 Fresh & Hot',
    '💰 Worth Price',
  ];

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersState = ref.watch(ordersProvider);
    final order = ordersState.orders
        .where((o) => o.id == widget.orderId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Rate Your Order')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Restaurant Info ───
            if (order != null)
              GlassCard(
                child: Row(
                  children: [
                    const Text('🍽️', style: TextStyle(fontSize: 32)),
                    const SizedBox(width: AppSpacing.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.restaurantName,
                          style: AppTypography.h3.copyWith(fontSize: 16),
                        ),
                        Text(
                          'Order #${order.orderNumber}',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Food Rating ───
            Center(child: Text('How was the food?', style: AppTypography.h3)),
            const SizedBox(height: AppSpacing.md),
            _buildStarRating(
              rating: _foodRating,
              onChanged: (r) => setState(() => _foodRating = r),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Delivery Rating ───
            Center(
              child: Text('How was the delivery?', style: AppTypography.h3),
            ),
            const SizedBox(height: AppSpacing.md),
            _buildStarRating(
              rating: _deliveryRating,
              onChanged: (r) => setState(() => _deliveryRating = r),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Tags ───
            Text(
              'What was good?',
              style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _tags.map((tag) {
                final isSelected = _selectedTags.contains(tag);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedTags.remove(tag);
                      } else {
                        _selectedTags.add(tag);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                    ),
                    child: Text(
                      tag,
                      style: AppTypography.caption.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Review Text ───
            Text(
              'Write a review (optional)',
              style: AppTypography.body1.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reviewController,
              style: AppTypography.body2.copyWith(color: Colors.white),
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Share your experience with this order...',
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // ─── Submit ───
            ChizzeButton(
              label: 'Submit Review',
              icon: Icons.send_rounded,
              onPressed: _foodRating > 0
                  ? () {
                      // TODO: Submit to Appwrite
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Thanks for your review! 🎉'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                      context.go('/home');
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRating({
    required int rating,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        return GestureDetector(
          onTap: () => onChanged(starIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedScale(
              scale: rating >= starIndex ? 1.2 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                rating >= starIndex
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 42,
                color: rating >= starIndex
                    ? AppColors.ratingStar
                    : AppColors.textTertiary,
              ),
            ),
          ),
        );
      }),
    ).animate().fadeIn(delay: 100.ms);
  }
}

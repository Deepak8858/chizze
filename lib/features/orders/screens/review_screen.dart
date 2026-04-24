import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
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
  bool _isSubmitting = false;
  bool _isLoading = true;
  bool _alreadyReviewed = false; // true when backend confirms order has a review
  String? _error;

  // Retry state
  Map<String, dynamic>? _lastSubmissionData;

  final _tags = [
    '😋 Great Food',
    '🚀 Fast Delivery',
    '📦 Well Packed',
    '😊 Polite Rider',
    '👨‍🍳 Fresh & Hot',
    '💰 Worth Price',
  ];

  @override
  void initState() {
    super.initState();
    _initializeOrderData();
  }

  /// Validate order status and refresh data on screen load
  Future<void> _initializeOrderData() async {
    final ordersNotifier = ref.read(ordersProvider.notifier);

    // Force refresh order to get latest status
    final order = await ordersNotifier.refreshOrderById(widget.orderId);

    if (!mounted) return;

    if (order == null) {
      setState(() {
        _error = 'Order not found';
        _isLoading = false;
      });
      return;
    }

    // Validate order status - only delivered/completed orders can be reviewed
    if (order.status.name != 'delivered' && order.status.name != 'completed') {
      setState(() {
        _error = 'This order has not been delivered yet';
        _isLoading = false;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) context.go('/home');
      });
      return;
    }

    // If the server says this order already has a review, skip the form
    // and show the already-reviewed state directly.
    if (order.hasReview == true) {
      setState(() {
        _alreadyReviewed = true;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = false);
  }

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _alreadyReviewed
          ? _buildAlreadyReviewedState()
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: AppColors.error),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: AppTypography.body1,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
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
                  Center(
                    child: Text('How was the food?', style: AppTypography.h3),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildStarRating(
                    rating: _foodRating,
                    onChanged: (r) => setState(() => _foodRating = r),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // ─── Delivery Rating ───
                  Center(
                    child: Text(
                      'How was the delivery?',
                      style: AppTypography.h3,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Helper text explaining delivery rating is optional
                  Center(
                    child: Text(
                      '(Optional - if not rated, food rating will be used)',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
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
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
                    label: _isSubmitting ? 'Submitting...' : 'Submit Review',
                    icon: Icons.send_rounded,
                    onPressed: _foodRating > 0 && !_isSubmitting
                        ? _submitReview
                        : null,
                  ),

                  // ─── Retry Button (if previous submission failed) ───
                  if (_lastSubmissionData != null && !_isSubmitting) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _retrySubmission,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry Last Submission'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: BorderSide(color: AppColors.warning),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  /// Shows when the order has already been reviewed — no form, clean confirmation.
  Widget _buildAlreadyReviewedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('✅', style: TextStyle(fontSize: 64))
                .animate()
                .scale(begin: const Offset(0.5, 0.5), duration: 400.ms, curve: Curves.elasticOut),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Already Reviewed',
              style: AppTypography.h2,
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: AppSpacing.md),
            Text(
              'You have already submitted a review for this order.\nThank you for your feedback!',
              style: AppTypography.body2.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 300.ms),
            const SizedBox(height: AppSpacing.xxl),
            ChizzeButton(
              label: 'Back to Orders',
              icon: Icons.receipt_long_rounded,
              onPressed: () => context.go('/orders'),
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _buildSubmissionData() {
    final payload = <String, dynamic>{
      'food_rating': _foodRating,
      'review_text': _reviewController.text.trim(),
      'tags': _selectedTags.toList(),
    };

    if (_deliveryRating > 0) {
      payload['delivery_rating'] = _deliveryRating;
    }

    return payload;
  }

  /// Submit review to backend
  Future<void> _submitReview() async {
    setState(() => _isSubmitting = true);

    final submissionData = _buildSubmissionData();

    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        '${ApiConfig.orders}/${widget.orderId}/review',
        body: submissionData,
      );

      if (!mounted) return;
      // Update local order state immediately so the "Rate now" button
      // changes to "Reviewed" without requiring a manual refresh.
      ref.read(ordersProvider.notifier).markOrderAsReviewed(widget.orderId);
      setState(() {
        _isSubmitting = false;
        _lastSubmissionData = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks for your review! 🎉'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/orders');
    } catch (e) {
      if (!mounted) return;
      final alreadyReviewed = _isAlreadyReviewed(e);
      setState(() {
        _isSubmitting = false;
        // Duplicate submission isn't retry-able — clear the retry slot.
        _lastSubmissionData = alreadyReviewed ? null : submissionData;
      });
      if (alreadyReviewed) {
        // Show in-screen already-reviewed state instead of a transient snackbar
        setState(() => _alreadyReviewed = true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          backgroundColor: AppColors.error,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _retrySubmission,
          ),
        ),
      );
    }
  }

  /// Retry failed submission with saved data
  Future<void> _retrySubmission() async {
    if (_lastSubmissionData == null) return;

    setState(() => _isSubmitting = true);

    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        '${ApiConfig.orders}/${widget.orderId}/review',
        body: _lastSubmissionData!,
      );

      if (!mounted) return;
      ref.read(ordersProvider.notifier).markOrderAsReviewed(widget.orderId);
      setState(() {
        _isSubmitting = false;
        _lastSubmissionData = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks for your review! 🎉'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/orders');
    } catch (e) {
      if (!mounted) return;
      final alreadyReviewed = _isAlreadyReviewed(e);
      setState(() {
        _isSubmitting = false;
        if (alreadyReviewed) _lastSubmissionData = null;
      });
      if (alreadyReviewed) {
        setState(() => _alreadyReviewed = true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Map an ApiException / network failure to a short user-facing sentence.
  /// Shows the backend's `error` field verbatim for 4xx so the customer sees
  /// the actual reason ("order not delivered yet"), and a plain offline
  /// message for network drops instead of a Dart exception dump.
  String _friendlyError(Object e) {
    if (e is ApiException) {
      if (e.statusCode == 0) {
        return 'No internet connection. Your review will submit when you reconnect.';
      }
      if (e.statusCode >= 500) {
        return 'Server error. Please try again in a moment.';
      }
      return e.message.isNotEmpty ? e.message : 'Could not submit review';
    }
    return 'Could not submit review. Please try again.';
  }

  bool _isAlreadyReviewed(Object e) {
    if (e is! ApiException) return false;
    if (e.statusCode != 400) return false;
    return e.message.toLowerCase().contains('already reviewed');
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

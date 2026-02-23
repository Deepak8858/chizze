import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';
import '../../core/theme/theme.dart';

/// Animated empty state with icon or Lottie animation, title, subtitle, and optional action button.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? lottieAsset;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.actionLabel,
    this.onAction,
    this.lottieAsset,
  });

  // ─── Prebuilt empty states ───

  /// No favorites
  factory EmptyStateWidget.favorites({VoidCallback? onExplore}) =>
      EmptyStateWidget(
        icon: Icons.favorite_outline_rounded,
        title: 'No favorites yet',
        subtitle: 'Tap the heart on restaurants you love\nto see them here.',
        actionLabel: 'Explore Restaurants',
        onAction: onExplore,
      );

  /// No active orders
  factory EmptyStateWidget.noActiveOrders({VoidCallback? onOrder}) =>
      EmptyStateWidget(
        icon: Icons.receipt_long_outlined,
        title: 'No active orders',
        subtitle: 'Your current orders will appear here.',
        actionLabel: 'Order Now',
        onAction: onOrder,
        lottieAsset: 'assets/animations/no_orders.json',
      );

  /// No past orders
  factory EmptyStateWidget.noPastOrders() => const EmptyStateWidget(
        icon: Icons.history_rounded,
        title: 'No past orders',
        subtitle: 'Your order history will show up here.',
        lottieAsset: 'assets/animations/no_orders.json',
      );

  /// No scheduled orders
  factory EmptyStateWidget.noScheduledOrders() => const EmptyStateWidget(
        icon: Icons.schedule_rounded,
        title: 'No scheduled orders',
        subtitle: 'Schedule an order to eat later\nand it\'ll appear here.',
        lottieAsset: 'assets/animations/no_orders.json',
      );

  /// No notifications
  factory EmptyStateWidget.noNotifications() => const EmptyStateWidget(
        icon: Icons.notifications_none_rounded,
        title: 'No notifications yet',
        subtitle: 'We\'ll let you know when something\nimportant happens.',
        lottieAsset: 'assets/animations/no_notifications.json',
      );

  /// No search results
  factory EmptyStateWidget.noSearchResults(String query) => EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: 'No results found',
        subtitle: 'Nothing matches "$query".\nTry a different search.',
        lottieAsset: 'assets/animations/no_results.json',
      );

  /// Empty cart
  factory EmptyStateWidget.emptyCart({VoidCallback? onBrowse}) =>
      EmptyStateWidget(
        icon: Icons.shopping_cart_outlined,
        title: 'Your cart is empty',
        subtitle: 'Add items from a restaurant\nto get started.',
        actionLabel: 'Browse Restaurants',
        onAction: onBrowse,
        lottieAsset: 'assets/animations/empty_cart.json',
      );

  /// No partner orders
  factory EmptyStateWidget.noPartnerOrders() => const EmptyStateWidget(
        icon: Icons.store_mall_directory_outlined,
        title: 'No orders right now',
        subtitle: 'New orders will appear here\nautomatically.',
      );

  /// No completed partner orders
  factory EmptyStateWidget.noCompletedOrders() => const EmptyStateWidget(
        icon: Icons.check_circle_outline_rounded,
        title: 'No completed orders',
        subtitle: 'Completed orders will be listed here.',
      );

  /// No offers
  factory EmptyStateWidget.noOffers() => const EmptyStateWidget(
        icon: Icons.local_offer_outlined,
        title: 'No offers available',
        subtitle: 'Check back later for\nexciting deals!',
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. $subtitle',
      explicitChildNodes: false,
      child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lottie animation or animated icon
            ExcludeSemantics(
            child: lottieAsset != null ?
              SizedBox(
                width: 120,
                height: 120,
                child: Lottie.asset(
                  lottieAsset!,
                  repeat: true,
                  animate: true,
                ),
              )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: -0.2, end: 0, duration: 400.ms)
            : Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 48,
                  color: AppColors.primary,
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(
                    begin: const Offset(1.0, 1.0),
                    end: const Offset(1.08, 1.08),
                    duration: 2000.ms,
                    curve: Curves.easeInOut,
                  )
                  .then()
                  .animate() // Entry animation
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: -0.2, end: 0, duration: 400.ms),
            ),

            const SizedBox(height: AppSpacing.xl),

            ExcludeSemantics(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
            ),

            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              ExcludeSemantics(
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
              ),
            ],

            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xxl),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                    vertical: AppSpacing.md,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                ),
                child: Text(actionLabel!),
              ).animate().fadeIn(delay: 450.ms, duration: 400.ms).slideY(
                    begin: 0.3,
                    end: 0,
                    delay: 450.ms,
                    duration: 400.ms,
                  ),
            ],
          ],
        ),
      ),
    ),
    );
  }
}

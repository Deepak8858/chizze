import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/theme.dart';

/// Animated empty state with icon, title, subtitle, and optional action button.
/// Uses flutter_animate for smooth entry animations instead of requiring
/// external Lottie JSON files (which can be swapped in later).
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.actionLabel,
    this.onAction,
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
      );

  /// No past orders
  factory EmptyStateWidget.noPastOrders() => const EmptyStateWidget(
        icon: Icons.history_rounded,
        title: 'No past orders',
        subtitle: 'Your order history will show up here.',
      );

  /// No scheduled orders
  factory EmptyStateWidget.noScheduledOrders() => const EmptyStateWidget(
        icon: Icons.schedule_rounded,
        title: 'No scheduled orders',
        subtitle: 'Schedule an order to eat later\nand it\'ll appear here.',
      );

  /// No notifications
  factory EmptyStateWidget.noNotifications() => const EmptyStateWidget(
        icon: Icons.notifications_none_rounded,
        title: 'No notifications yet',
        subtitle: 'We\'ll let you know when something\nimportant happens.',
      );

  /// No search results
  factory EmptyStateWidget.noSearchResults(String query) => EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: 'No results found',
        subtitle: 'Nothing matches "$query".\nTry a different search.',
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon with pulsing effect
            Container(
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

            const SizedBox(height: AppSpacing.xl),

            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 150.ms, duration: 400.ms),

            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
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
    );
  }
}

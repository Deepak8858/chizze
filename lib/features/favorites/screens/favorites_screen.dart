import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../providers/favorites_provider.dart';
import '../../home/models/restaurant.dart';

/// Favorites screen — shows user's saved restaurants
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(favoritesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ─── Header ───
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.base,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Favorites',
                      style: AppTypography.h2.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (state.favorites.isNotEmpty)
                      Text(
                        '${state.favoriteIds.length} saved',
                        style: AppTypography.caption.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ─── Content ───
            if (state.isLoading)
              SliverFillRemaining(
                child: ListSkeleton(
                  itemCount: 4,
                  itemBuilder: (_, _) => const RestaurantCardSkeleton(),
                ),
              )
            else if (state.favorites.isEmpty)
              SliverFillRemaining(
                child: _buildEmptyState(context, isDark),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.base,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final restaurant = state.favorites[index];
                      return _FavoriteRestaurantCard(
                        restaurant: restaurant,
                        onRemove: () => ref
                            .read(favoritesProvider.notifier)
                            .removeFavorite(restaurant.id),
                        onTap: () =>
                            context.push('/restaurant/${restaurant.id}'),
                      )
                          .animate()
                          .fadeIn(
                            delay: Duration(milliseconds: index * 80),
                            duration: 400.ms,
                          )
                          .slideY(
                            begin: 0.1,
                            end: 0,
                            delay: Duration(milliseconds: index * 80),
                            duration: 400.ms,
                            curve: Curves.easeOutCubic,
                          );
                    },
                    childCount: state.favorites.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return EmptyStateWidget.favorites(
      onExplore: () => GoRouter.of(context).go('/home'),
    );
  }
}

/// Individual favorite restaurant card with swipe-to-remove
class _FavoriteRestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const _FavoriteRestaurantCard({
    required this.restaurant,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: Key(restaurant.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        margin: const EdgeInsets.only(bottom: AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Icon(
          Icons.delete_rounded,
          color: AppColors.error,
          size: 28,
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.base),
          child: GlassCard(
            child: Row(
              children: [
                // Restaurant image
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusMd),
                  child: Container(
                    width: 88,
                    height: 88,
                    color: isDark
                        ? AppColors.surfaceElevated
                        : AppColors.lightSurfaceElevated,
                    child: restaurant.coverImageUrl.isNotEmpty
                        ? Image.network(
                            restaurant.coverImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _buildPlaceholder(isDark),
                          )
                        : _buildPlaceholder(isDark),
                  ),
                ),
                const SizedBox(width: AppSpacing.base),

                // Restaurant info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restaurant.name,
                        style: AppTypography.body1.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        restaurant.cuisines.join(' · '),
                        style: AppTypography.caption.copyWith(
                          color: isDark
                              ? AppColors.textSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            restaurant.rating.toStringAsFixed(1),
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.base),
                          Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: isDark
                                ? AppColors.textTertiary
                                : AppColors.lightTextTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${restaurant.avgDeliveryTimeMin} min',
                            style: AppTypography.caption.copyWith(
                              color: isDark
                                  ? AppColors.textSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Favorite button
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.favorite_rounded,
                    color: AppColors.error,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    return Center(
      child: Icon(
        Icons.restaurant_rounded,
        size: 32,
        color: isDark ? AppColors.textTertiary : AppColors.lightTextTertiary,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_loader.dart';
import '../providers/restaurant_provider.dart';
import '../models/restaurant.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../../coupons/providers/coupons_provider.dart';
import '../../profile/providers/user_profile_provider.dart';
import '../../profile/providers/address_provider.dart';

/// Customer home screen — restaurant discovery feed
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final profile = ref.watch(userProfileProvider);
    // Prefer profile name from backend (always set during onboarding),
    // fall back to Appwrite account name, then generic greeting.
    final userName = profile.name.isNotEmpty
        ? profile.name
        : (authState.user?.name ?? 'Foodie');
    final restaurantState = ref.watch(restaurantProvider);
    final restaurants = restaurantState.restaurants;

    // Get delivery address: prefer default saved address, fall back to profile address
    final addresses = ref.watch(addressProvider);
    final defaultAddr = addresses.where((a) => a.isDefault).firstOrNull ?? 
                        (addresses.isNotEmpty ? addresses.first : null);
    final deliveryLabel = defaultAddr?.label ?? 'Home';
    final deliveryAddress = defaultAddr?.fullAddress ?? 
                           (profile.address.isNotEmpty ? profile.address : 'Set delivery address');

    return Scaffold(
      backgroundColor: AppColors.background,
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
                child: _buildHeader(context, userName, deliveryLabel, deliveryAddress),
              ),
            ),

            // ─── Search Bar ───
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.sm,
                ),
                child: _buildSearchBar(context),
              ),
            ),

            // ─── Category Chips ───
            SliverToBoxAdapter(
              child: SizedBox(height: 100, child: _buildCategories(context)),
            ),

            // ─── Promo Banner ───
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.sm,
                ),
                child: _buildPromoBanner(),
              ),
            ),

            // ─── Offers For You ───
            SliverToBoxAdapter(
              child: _buildSectionHeader('Offers For You', 'View All', () {
                context.push('/coupons');
              }),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 130,
                child: _buildOffersCarousel(context, ref),
              ),
            ),

            // ─── Section: Top Picks ───
            SliverToBoxAdapter(
              child: _buildSectionHeader('Top Picks for You', 'See All', () {
                context.go('/search');
              }),
            ),

            // ─── Restaurant Cards ───
            if (restaurantState.isLoading && restaurants.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, _) => const RestaurantCardSkeleton(),
                    childCount: 4,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildRestaurantCard(context, ref, restaurants[index], index),
                    childCount: restaurants.length,
                  ),
                ),
              ),

            // Bottom spacing
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSpacing.massive),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String userName, String deliveryLabel, String deliveryAddress) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => context.push('/addresses'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Deliver to',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$deliveryLabel · $deliveryAddress',
                  style: AppTypography.body1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              userName.isNotEmpty ? userName[0].toUpperCase() : 'C',
              style: AppTypography.h3.copyWith(fontSize: 16),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildSearchBar(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search restaurants or dishes',
      child: GestureDetector(
        onTap: () => context.go('/search'),
        child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: AppColors.textTertiary, size: 22,
                 semanticLabel: 'Search'),
            const SizedBox(width: AppSpacing.md),
            Text(
              'Search restaurants or dishes...',
              style: AppTypography.body2.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        ),
      ),
    ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.05);
  }

  Widget _buildCategories(BuildContext context) {
    final categories = [
      ('🍕', 'Pizza'),
      ('🍔', 'Burgers'),
      ('🍜', 'Chinese'),
      ('🍛', 'Indian'),
      ('🥗', 'Healthy'),
      ('☕', 'Cafe'),
      ('🍰', 'Desserts'),
      ('🥤', 'Drinks'),
    ];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final (emoji, name) = categories[index];
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: Semantics(
            button: true,
            label: 'Browse $name restaurants',
            child: GestureDetector(
              onTap: () => context.go('/search'),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(name, style: AppTypography.caption),
              ],
            ),
          ),
          ),
        ).animate(delay: (100 + index * 50).ms).fadeIn().slideX(begin: 0.2);
      },
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('50% OFF', style: AppTypography.h1.copyWith(fontSize: 28)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'on your first order!\nUse code: CHIZZE50',
                  style: AppTypography.body2.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.local_offer_rounded,
            size: 48,
            color: Colors.white24,
          ),
        ],
      ),
    ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1);
  }

  Widget _buildOffersCarousel(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(couponsProvider).available.where((c) => c.isUsable).take(5).toList();

    if (coupons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.local_offer_outlined,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No offers right now',
                        style: AppTypography.body1.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Check back soon for exciting deals!',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final gradients = [
      [const Color(0xFFFF6B6B), const Color(0xFFFF8E53)],
      [const Color(0xFF4ECDC4), const Color(0xFF2BC0E4)],
      [const Color(0xFFA770EF), const Color(0xFFCF8BF3)],
      [const Color(0xFFFFD93D), const Color(0xFFFF6B6B)],
      [const Color(0xFF6C5CE7), const Color(0xFFA29BFE)],
    ];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      itemCount: coupons.length,
      itemBuilder: (context, index) {
        final coupon = coupons[index];
        final colors = gradients[index % gradients.length];
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: GestureDetector(
            onTap: () => context.push('/coupons'),
            child: Container(
              width: 200,
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${coupon.discountPercent.toInt()}% OFF',
                    style: AppTypography.h2.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    coupon.title,
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          coupon.code,
                          style: AppTypography.overline.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${coupon.daysRemaining}d left',
                        style: AppTypography.overline.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ).animate(delay: (200 + index * 80).ms).fadeIn().slideX(begin: 0.15);
      },
    );
  }

  Widget _buildSectionHeader(String title, String action, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppTypography.h3),
          GestureDetector(
            onTap: onTap,
            child: Semantics(
              button: true,
              label: '$action $title',
              child: Text(
                action,
                style: AppTypography.caption.copyWith(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantCard(
    BuildContext context,
    WidgetRef ref,
    Restaurant restaurant,
    int index,
  ) {
    final isFav = ref.watch(favoritesProvider).favoriteIds.contains(restaurant.id);
    final emoji = _cuisineEmoji(restaurant.cuisines.first);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: GlassCard(
        onTap: () => context.push('/restaurant/${restaurant.id}'),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.radiusLg),
                ),
              ),
              child: Stack(
                children: [
                  if (restaurant.coverImageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppSpacing.radiusLg),
                      ),
                      child: Image.network(
                        restaurant.coverImageUrl,
                        width: double.infinity,
                        height: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(emoji, style: const TextStyle(fontSize: 48)),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 48)),
                    ),
                  if (restaurant.isPromoted)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Promoted',
                          style: AppTypography.overline.copyWith(
                            color: Colors.white,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                  if (restaurant.isFeatured)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '⭐ Featured',
                          style: AppTypography.overline.copyWith(
                            color: Colors.black,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                  // Heart / Favorite button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Semantics(
                      button: true,
                      label: isFav ? 'Remove from favorites' : 'Add to favorites',
                      child: GestureDetector(
                        onTap: () => ref.read(favoritesProvider.notifier).toggleFavorite(restaurant.id),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isFav ? AppColors.primary : Colors.white,
                            size: 20,
                            semanticLabel: isFav ? 'Favorited' : 'Not favorited',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          style: AppTypography.h3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: restaurant.rating >= 4.0
                              ? AppColors.success
                              : AppColors.warning,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Text(
                              restaurant.rating.toStringAsFixed(1),
                              style: AppTypography.badge,
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: Colors.white,
                              semanticLabel: 'stars',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    restaurant.cuisines
                        .map((c) => c.replaceAll('_', ' '))
                        .join(' · '),
                    style: AppTypography.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: AppColors.textTertiary,
                        semanticLabel: 'Delivery time',
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${restaurant.avgDeliveryTimeMin} min',
                        style: AppTypography.caption,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text('·', style: AppTypography.caption),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        '₹${restaurant.priceForTwo} for two',
                        style: AppTypography.caption,
                      ),
                      if (restaurant.isVegOnly) ...[
                        const SizedBox(width: AppSpacing.md),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.veg.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'VEG',
                            style: AppTypography.overline.copyWith(
                              color: AppColors.veg,
                              fontSize: 8,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: (400 + index * 100).ms).fadeIn().slideY(begin: 0.05);
  }

  String _cuisineEmoji(String cuisine) {
    const map = {
      'biryani': '🍛',
      'north_indian': '🍛',
      'mughlai': '🍖',
      'pizza': '🍕',
      'italian': '🍝',
      'pasta': '🍝',
      'chinese': '🍜',
      'indo_chinese': '🥡',
      'thai': '🍜',
      'healthy': '🥗',
      'salads': '🥙',
      'continental': '🍽️',
      'cafe': '☕',
      'snacks': '🍟',
      'beverages': '🥤',
    };
    return map[cuisine] ?? '🍽️';
  }
}

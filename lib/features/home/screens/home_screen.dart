import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_loader.dart';

/// Customer home screen — restaurant discovery feed
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final userName = authState.user?.name ?? 'Foodie';

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
                child: _buildHeader(context, userName),
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
              child: SizedBox(height: 100, child: _buildCategories()),
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

            // ─── Section: Top Picks ───
            SliverToBoxAdapter(
              child: _buildSectionHeader('Top Picks for You', 'See All'),
            ),

            // ─── Restaurant Cards ───
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildRestaurantCard(index),
                  childCount: 5,
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

  Widget _buildHeader(BuildContext context, String userName) {
    return Row(
      children: [
        Expanded(
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
                'Home · HSR Layout, Bengaluru',
                style: AppTypography.body1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // Profile avatar
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
    return GestureDetector(
      onTap: () {
        // TODO: Navigate to search screen
      },
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
            Icon(Icons.search_rounded, color: AppColors.textTertiary, size: 22),
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
    ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.05);
  }

  Widget _buildCategories() {
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

  Widget _buildSectionHeader(String title, String action) {
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
          Text(
            action,
            style: AppTypography.caption.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantCard(int index) {
    final restaurants = [
      ('Burger King', '4.2', '25-30 min', '₹150 for two', '🍔'),
      ('Pizza Hut', '4.0', '30-35 min', '₹200 for two', '🍕'),
      ('Biryani Blues', '4.5', '35-40 min', '₹250 for two', '🍛'),
      ('Starbucks', '4.3', '15-20 min', '₹300 for two', '☕'),
      ('Subway', '3.9', '20-25 min', '₹180 for two', '🥗'),
    ];

    final (name, rating, time, price, emoji) = restaurants[index % 5];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: GlassCard(
        onTap: () {
          // TODO: Navigate to restaurant detail
        },
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.radiusLg),
                ),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 48)),
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
                      Text(name, style: AppTypography.h3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Text(rating, style: AppTypography.badge),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(time, style: AppTypography.caption),
                      const SizedBox(width: AppSpacing.md),
                      Text('·', style: AppTypography.caption),
                      const SizedBox(width: AppSpacing.md),
                      Text(price, style: AppTypography.caption),
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
}

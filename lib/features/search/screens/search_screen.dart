import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../home/models/restaurant.dart';
import '../../home/providers/restaurant_provider.dart';

/// Search state
final searchQueryProvider = StateProvider<String>((ref) => '');
final searchFilterProvider = StateProvider<SearchFilters>(
  (ref) => const SearchFilters(),
);

class SearchFilters {
  final String? cuisine;
  final bool vegOnly;
  final String sortBy; // relevance, rating, delivery_time, cost_low, cost_high
  final double minRating;

  const SearchFilters({
    this.cuisine,
    this.vegOnly = false,
    this.sortBy = 'relevance',
    this.minRating = 0,
  });

  SearchFilters copyWith({
    String? cuisine,
    bool? vegOnly,
    String? sortBy,
    double? minRating,
  }) {
    return SearchFilters(
      cuisine: cuisine ?? this.cuisine,
      vegOnly: vegOnly ?? this.vegOnly,
      sortBy: sortBy ?? this.sortBy,
      minRating: minRating ?? this.minRating,
    );
  }
}

/// Filtered restaurants provider
final filteredRestaurantsProvider = Provider<List<Restaurant>>((ref) {
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final filters = ref.watch(searchFilterProvider);
  var restaurants = ref.watch(restaurantProvider).restaurants;

  // Text search
  if (query.isNotEmpty) {
    restaurants = restaurants.where((r) {
      return r.name.toLowerCase().contains(query) ||
          r.cuisines.any((c) => c.toLowerCase().contains(query)) ||
          r.description.toLowerCase().contains(query);
    }).toList();
  }

  // Cuisine filter
  if (filters.cuisine != null) {
    restaurants = restaurants
        .where((r) => r.cuisines.contains(filters.cuisine))
        .toList();
  }

  // Veg only filter
  if (filters.vegOnly) {
    restaurants = restaurants.where((r) => r.isVegOnly).toList();
  }

  // Min rating filter
  if (filters.minRating > 0) {
    restaurants = restaurants
        .where((r) => r.rating >= filters.minRating)
        .toList();
  }

  // Sorting
  switch (filters.sortBy) {
    case 'rating':
      restaurants.sort((a, b) => b.rating.compareTo(a.rating));
      break;
    case 'delivery_time':
      restaurants.sort(
        (a, b) => a.avgDeliveryTimeMin.compareTo(b.avgDeliveryTimeMin),
      );
      break;
    case 'cost_low':
      restaurants.sort((a, b) => a.priceForTwo.compareTo(b.priceForTwo));
      break;
    case 'cost_high':
      restaurants.sort((a, b) => b.priceForTwo.compareTo(a.priceForTwo));
      break;
  }

  return restaurants;
});

/// Search screen with filters
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(filteredRestaurantsProvider);
    final query = ref.watch(searchQueryProvider);
    final filters = ref.watch(searchFilterProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Search Bar ───
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                AppSpacing.base,
                AppSpacing.base,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => context.go('/home'),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      style: AppTypography.body1,
                      decoration: InputDecoration(
                        hintText: 'Search restaurants, cuisines...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 22),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(searchQueryProvider.notifier).state =
                                      '';
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.base,
                          vertical: AppSpacing.md,
                        ),
                      ),
                      onChanged: (value) {
                        ref.read(searchQueryProvider.notifier).state = value;
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ─── Filter Chips ───
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.sm,
                ),
                children: [
                  _FilterChip(
                    label: 'Sort',
                    icon: Icons.sort_rounded,
                    isActive: filters.sortBy != 'relevance',
                    onTap: () => _showSortSheet(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _FilterChip(
                    label: 'Pure Veg',
                    icon: Icons.eco_rounded,
                    isActive: filters.vegOnly,
                    onTap: () {
                      ref.read(searchFilterProvider.notifier).state = filters
                          .copyWith(vegOnly: !filters.vegOnly);
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _FilterChip(
                    label: 'Rating 4.0+',
                    icon: Icons.star_rounded,
                    isActive: filters.minRating >= 4.0,
                    onTap: () {
                      ref.read(searchFilterProvider.notifier).state = filters
                          .copyWith(
                            minRating: filters.minRating >= 4.0 ? 0 : 4.0,
                          );
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ..._buildCuisineChips(filters),
                ],
              ),
            ),

            // ─── Results ───
            Expanded(
              child: results.isEmpty
                  ? _buildEmptyState(query)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.base,
                      ),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        return _buildRestaurantCard(results[index], index);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCuisineChips(SearchFilters filters) {
    final cuisines = ['biryani', 'pizza', 'chinese', 'healthy', 'cafe'];
    return cuisines.map((cuisine) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: _FilterChip(
          label: cuisine[0].toUpperCase() + cuisine.substring(1),
          isActive: filters.cuisine == cuisine,
          onTap: () {
            ref.read(searchFilterProvider.notifier).state = filters.copyWith(
              cuisine: filters.cuisine == cuisine ? null : cuisine,
            );
          },
        ),
      );
    }).toList();
  }

  Widget _buildEmptyState(String query) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            query.isEmpty ? Icons.search_rounded : Icons.search_off_rounded,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            query.isEmpty
                ? 'Search for restaurants or cuisines'
                : 'No results for "$query"',
            style: AppTypography.body2,
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantCard(Restaurant restaurant, int index) {
    final emoji = _cuisineEmoji(restaurant.cuisines.first);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        onTap: () => context.push('/restaurant/${restaurant.id}'),
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            // Image
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(AppSpacing.radiusLg),
                ),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 36)),
              ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            restaurant.name,
                            style: AppTypography.h3.copyWith(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _RatingBadge(rating: restaurant.rating),
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
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${restaurant.avgDeliveryTimeMin} min',
                          style: AppTypography.caption,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          '₹${restaurant.priceForTwo} for two',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                    if (restaurant.isVegOnly)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.veg.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'PURE VEG',
                            style: AppTypography.overline.copyWith(
                              color: AppColors.veg,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 80).ms).fadeIn().slideX(begin: 0.05);
  }

  void _showSortSheet(BuildContext context) {
    final filters = ref.read(searchFilterProvider);
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sort by', style: AppTypography.h3),
              const SizedBox(height: AppSpacing.base),
              ...[
                ('relevance', 'Relevance (Default)'),
                ('rating', 'Rating: High to Low'),
                ('delivery_time', 'Delivery Time: Fast First'),
                ('cost_low', 'Cost: Low to High'),
                ('cost_high', 'Cost: High to Low'),
              ].map((option) {
                return ListTile(
                  title: Text(option.$2, style: AppTypography.body1),
                  trailing: filters.sortBy == option.$1
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () {
                    ref.read(searchFilterProvider.notifier).state = filters
                        .copyWith(sortBy: option.$1);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
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

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isActive;
  final VoidCallback? onTap;

  const _FilterChip({
    required this.label,
    this.icon,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: isActive ? AppColors.primary : AppColors.textSecondary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final double rating;
  const _RatingBadge({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: rating >= 4.0 ? AppColors.success : AppColors.warning,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rating.toStringAsFixed(1), style: AppTypography.badge),
          const SizedBox(width: 2),
          const Icon(Icons.star_rounded, size: 11, color: Colors.white),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/chizze_button.dart';
import '../../home/models/restaurant.dart';
import '../models/menu_item.dart';
import '../../cart/providers/cart_provider.dart';

/// Restaurant detail screen with menu
class RestaurantDetailScreen extends ConsumerStatefulWidget {
  final String restaurantId;

  const RestaurantDetailScreen({super.key, required this.restaurantId});

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends ConsumerState<RestaurantDetailScreen> {
  late final Restaurant restaurant;
  late final List<MenuCategory> categories;
  late final List<MenuItem> menuItems;
  bool _vegFilter = false;

  @override
  void initState() {
    super.initState();
    // Load mock data (will be replaced with Appwrite queries)
    restaurant = Restaurant.mockList.firstWhere(
      (r) => r.id == widget.restaurantId,
      orElse: () => Restaurant.mockList.first,
    );
    categories = MenuItem.mockCategoriesForRestaurant(widget.restaurantId);
    menuItems = MenuItem.mockListForRestaurant(widget.restaurantId);
  }

  List<MenuItem> get filteredItems {
    if (_vegFilter) return menuItems.where((i) => i.isVeg).toList();
    return menuItems;
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ─── Hero Header ───
              _buildHeroHeader(),

              // ─── Restaurant Info ───
              SliverToBoxAdapter(child: _buildRestaurantInfo()),

              // ─── Veg/Non-Veg Toggle ───
              SliverToBoxAdapter(child: _buildVegToggle()),

              // ─── Menu Sections ───
              ..._buildMenuSections(),

              // Bottom padding for cart bar
              SliverToBoxAdapter(
                child: SizedBox(height: cartState.isNotEmpty ? 100 : 32),
              ),
            ],
          ),

          // ─── Cart Bar (if items in cart) ───
          if (cartState.isNotEmpty) _buildCartBar(cartState),
        ],
      ),
    );
  }

  Widget _buildHeroHeader() {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: AppColors.background,
      leading: _CircleBackButton(),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: AppColors.surfaceElevated,
              child: Center(
                child: Text(
                  _cuisineEmoji(restaurant.cuisines.first),
                  style: const TextStyle(fontSize: 72),
                ),
              ),
            ),
            // Gradient overlay
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppColors.background],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestaurantInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name & Rating
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(restaurant.name, style: AppTypography.h1)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      restaurant.rating.toStringAsFixed(1),
                      style: AppTypography.button.copyWith(fontSize: 14),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xs),

          // Cuisines
          Text(
            restaurant.cuisines.map((c) => c.replaceAll('_', ' ')).join(' · '),
            style: AppTypography.body2,
          ),

          const SizedBox(height: AppSpacing.md),

          // Info chips
          Row(
            children: [
              _InfoChip(
                icon: Icons.access_time_rounded,
                text: '${restaurant.avgDeliveryTimeMin} min',
              ),
              const SizedBox(width: AppSpacing.md),
              _InfoChip(
                icon: Icons.currency_rupee_rounded,
                text: '₹${restaurant.priceForTwo} for two',
              ),
              const SizedBox(width: AppSpacing.md),
              _InfoChip(
                icon: Icons.star_rounded,
                text: '${restaurant.totalRatings} ratings',
              ),
            ],
          ),

          if (restaurant.isVegOnly)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.veg.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.veg.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _VegBadge(isVeg: true, size: 12),
                    const SizedBox(width: 6),
                    Text(
                      'Pure Vegetarian',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.veg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.base),
          const Divider(color: AppColors.divider),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildVegToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            'MENU',
            style: AppTypography.overline.copyWith(
              color: AppColors.primary,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          Text('Veg Only', style: AppTypography.caption),
          const SizedBox(width: AppSpacing.sm),
          Switch(
            value: _vegFilter,
            onChanged: (v) => setState(() => _vegFilter = v),
            activeColor: AppColors.veg,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMenuSections() {
    List<Widget> sections = [];

    for (int catIndex = 0; catIndex < categories.length; catIndex++) {
      final category = categories[catIndex];
      final items = filteredItems
          .where((i) => i.categoryId == category.id)
          .toList();

      if (items.isEmpty) continue;

      // Category header
      sections.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Text(category.name, style: AppTypography.h3),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '(${items.length})',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Menu items
      sections.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildMenuItemCard(items[index], index),
              childCount: items.length,
            ),
          ),
        ),
      );
    }

    return sections;
  }

  Widget _buildMenuItemCard(MenuItem item, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Veg/Non-veg badge + bestseller
                  Row(
                    children: [
                      _VegBadge(isVeg: item.isVeg),
                      if (item.isBestseller) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '★ Bestseller',
                            style: AppTypography.overline.copyWith(
                              color: AppColors.primary,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                      if (item.isMustTry) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Must Try',
                            style: AppTypography.overline.copyWith(
                              color: AppColors.warning,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  // Name
                  Text(
                    item.name,
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  // Price
                  Text('₹${item.price.toInt()}', style: AppTypography.price),
                  const SizedBox(height: AppSpacing.xs),

                  // Description
                  Text(
                    item.description,
                    style: AppTypography.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: AppSpacing.md),

            // Image + Add button
            Column(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Center(
                    child: Text(
                      item.isVeg ? '🥗' : '🍖',
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _AddButton(
                  onTap: () => _addToCart(item),
                  hasCustomizations: item.customizations.isNotEmpty,
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 60).ms).fadeIn().slideX(begin: 0.03);
  }

  void _addToCart(MenuItem item) {
    if (item.customizations.isNotEmpty) {
      _showCustomizationSheet(item);
    } else {
      ref
          .read(cartProvider.notifier)
          .addItem(
            CartItem(
              menuItem: item,
              restaurantId: restaurant.id,
              restaurantName: restaurant.name,
            ),
          );
      _showAddedSnackbar(item.name);
    }
  }

  void _showAddedSnackbar(String itemName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$itemName added to cart'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _showCustomizationSheet(MenuItem item) {
    final selectedOptions = <String, List<CustomizationOption>>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.85,
              builder: (context, scrollController) {
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: AppTypography.h3),
                      Text(
                        '₹${item.price.toInt()}',
                        style: AppTypography.price.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      const Divider(color: AppColors.divider),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: item.customizations.map((group) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: AppSpacing.base),
                                Row(
                                  children: [
                                    Text(
                                      group.name,
                                      style: AppTypography.body1.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (group.isRequired) ...[
                                      const SizedBox(width: AppSpacing.sm),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.error.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'Required',
                                          style: AppTypography.overline
                                              .copyWith(
                                                color: AppColors.error,
                                                fontSize: 9,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                ...group.options.map((option) {
                                  final isSelected =
                                      selectedOptions[group.name]?.contains(
                                        option,
                                      ) ??
                                      false;
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      option.name,
                                      style: AppTypography.body2.copyWith(
                                        color: Colors.white,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (option.price > 0)
                                          Text(
                                            '+₹${option.price.toInt()}',
                                            style: AppTypography.caption,
                                          ),
                                        const SizedBox(width: AppSpacing.sm),
                                        Checkbox(
                                          value: isSelected,
                                          activeColor: AppColors.primary,
                                          onChanged: (checked) {
                                            setSheetState(() {
                                              if (checked == true) {
                                                selectedOptions[group.name] = [
                                                  ...(selectedOptions[group
                                                          .name] ??
                                                      []),
                                                  option,
                                                ];
                                              } else {
                                                selectedOptions[group.name]
                                                    ?.remove(option);
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      ChizzeButton(
                        label: 'Add to Cart',
                        onPressed: () {
                          ref
                              .read(cartProvider.notifier)
                              .addItem(
                                CartItem(
                                  menuItem: item,
                                  restaurantId: restaurant.id,
                                  restaurantName: restaurant.name,
                                  selectedCustomizations: selectedOptions,
                                ),
                              );
                          Navigator.pop(context);
                          _showAddedSnackbar(item.name);
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCartBar(CartState cartState) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
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
          label:
              '${cartState.totalItems} items · ₹${cartState.itemTotal.toInt()} — View Cart',
          icon: Icons.shopping_bag_rounded,
          onPressed: () => context.push('/cart'),
        ),
      ).animate().slideY(begin: 1, duration: 300.ms, curve: Curves.easeOut),
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

// ─── Helper Widgets ───

class _CircleBackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: CircleAvatar(
        backgroundColor: AppColors.background.withValues(alpha: 0.7),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }
}

class _VegBadge extends StatelessWidget {
  final bool isVeg;
  final double size;
  const _VegBadge({required this.isVeg, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(
          color: isVeg ? AppColors.veg : AppColors.nonVeg,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Container(
          width: size * 0.45,
          height: size * 0.45,
          decoration: BoxDecoration(
            color: isVeg ? AppColors.veg : AppColors.nonVeg,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(text, style: AppTypography.caption),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool hasCustomizations;
  const _AddButton({required this.onTap, this.hasCustomizations = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary),
        ),
        child: Center(
          child: Text(
            hasCustomizations ? 'ADD +' : 'ADD',
            style: AppTypography.buttonSmall.copyWith(
              color: AppColors.primary,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../restaurant/models/menu_item.dart';

/// Menu management state for restaurant partner
class MenuManagementState {
  final List<MenuCategory> categories;
  final List<MenuItem> items;
  final bool isLoading;

  const MenuManagementState({
    this.categories = const [],
    this.items = const [],
    this.isLoading = false,
  });

  MenuManagementState copyWith({
    List<MenuCategory>? categories,
    List<MenuItem>? items,
    bool? isLoading,
  }) {
    return MenuManagementState(
      categories: categories ?? this.categories,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  List<MenuItem> itemsForCategory(String categoryId) =>
      items.where((i) => i.categoryId == categoryId).toList();
}

/// Menu management notifier — API-backed with mock fallback
class MenuManagementNotifier extends StateNotifier<MenuManagementState> {
  final ApiClient _api;

  MenuManagementNotifier(this._api) : super(const MenuManagementState()) {
    _loadData();
  }

  Future<void> _loadData() async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await _api.get(ApiConfig.partnerMenu);
      if (response.success && response.data != null) {
        // API returns menu items — parse them
        state = state.copyWith(isLoading: false);
        return;
      }
    } catch (_) {}

    // Fallback to mock data
    state = state.copyWith(
      categories: MenuItem.mockCategoriesForRestaurant('r1'),
      items: MenuItem.mockListForRestaurant('r1'),
      isLoading: false,
    );
  }

  // ─── Category Operations ───

  void addCategory(String name) {
    final newCategory = MenuCategory(
      id: 'cat_${DateTime.now().millisecondsSinceEpoch}',
      restaurantId: 'r1',
      name: name,
      sortOrder: state.categories.length,
    );
    state = state.copyWith(categories: [...state.categories, newCategory]);
  }

  void updateCategory(String categoryId, String newName) {
    final updated = state.categories.map((c) {
      if (c.id == categoryId) {
        return MenuCategory(
          id: c.id,
          restaurantId: c.restaurantId,
          name: newName,
          sortOrder: c.sortOrder,
          isActive: c.isActive,
        );
      }
      return c;
    }).toList();
    state = state.copyWith(categories: updated);
  }

  void toggleCategoryActive(String categoryId) {
    final updated = state.categories.map((c) {
      if (c.id == categoryId) {
        return MenuCategory(
          id: c.id,
          restaurantId: c.restaurantId,
          name: c.name,
          sortOrder: c.sortOrder,
          isActive: !c.isActive,
        );
      }
      return c;
    }).toList();
    state = state.copyWith(categories: updated);
  }

  void deleteCategory(String categoryId) {
    state = state.copyWith(
      categories: state.categories.where((c) => c.id != categoryId).toList(),
      items: state.items.where((i) => i.categoryId != categoryId).toList(),
    );
  }

  // ─── Item Operations ───

  void addItem({
    required String name,
    required String categoryId,
    required double price,
    String description = '',
    bool isVeg = false,
  }) {
    final newItem = MenuItem(
      id: 'item_${DateTime.now().millisecondsSinceEpoch}',
      restaurantId: 'r1',
      categoryId: categoryId,
      name: name,
      description: description,
      price: price,
      isVeg: isVeg,
    );
    state = state.copyWith(items: [...state.items, newItem]);

    // Push to API
    _api
        .post(
          ApiConfig.partnerMenu,
          body: {
            'name': name,
            'category_id': categoryId,
            'price': price,
            'description': description,
            'is_veg': isVeg,
          },
        )
        .ignore();
  }

  void updateItem(
    String itemId, {
    String? name,
    double? price,
    String? description,
    bool? isVeg,
    String? categoryId,
  }) {
    final updated = state.items.map((item) {
      if (item.id == itemId) {
        return MenuItem(
          id: item.id,
          restaurantId: item.restaurantId,
          categoryId: categoryId ?? item.categoryId,
          name: name ?? item.name,
          description: description ?? item.description,
          price: price ?? item.price,
          isVeg: isVeg ?? item.isVeg,
          isAvailable: item.isAvailable,
          isBestseller: item.isBestseller,
          isMustTry: item.isMustTry,
          customizations: item.customizations,
        );
      }
      return item;
    }).toList();
    state = state.copyWith(items: updated);

    // Push to API
    _api
        .put(
          '${ApiConfig.partnerMenu}/$itemId',
          body: {
            'name': ?name,
            'price': ?price,
            'description': ?description,
            'is_veg': ?isVeg,
          },
        )
        .ignore();
  }

  void toggleItemAvailability(String itemId) {
    MenuItem? toggled;
    final updated = state.items.map((item) {
      if (item.id == itemId) {
        toggled = MenuItem(
          id: item.id,
          restaurantId: item.restaurantId,
          categoryId: item.categoryId,
          name: item.name,
          description: item.description,
          price: item.price,
          isVeg: item.isVeg,
          isAvailable: !item.isAvailable,
          isBestseller: item.isBestseller,
          isMustTry: item.isMustTry,
          customizations: item.customizations,
        );
        return toggled!;
      }
      return item;
    }).toList();
    state = state.copyWith(items: updated);

    if (toggled != null) {
      _api
          .put(
            '${ApiConfig.partnerMenu}/$itemId',
            body: {'is_available': toggled!.isAvailable},
          )
          .ignore();
    }
  }

  void deleteItem(String itemId) {
    state = state.copyWith(
      items: state.items.where((i) => i.id != itemId).toList(),
    );
    _api.delete('${ApiConfig.partnerMenu}/$itemId').ignore();
  }
}

/// Menu management provider
final menuManagementProvider =
    StateNotifierProvider<MenuManagementNotifier, MenuManagementState>((ref) {
      final api = ref.watch(apiClientProvider);
      return MenuManagementNotifier(api);
    });

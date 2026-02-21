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
      // Fetch menu items and categories in parallel
      final results = await Future.wait([
        _api.get(ApiConfig.partnerMenu),
        _api.get(ApiConfig.partnerCategories),
      ]);

      final menuResponse = results[0];
      final catResponse = results[1];

      List<MenuItem> items = [];
      List<MenuCategory> categories = [];

      if (menuResponse.success && menuResponse.data != null) {
        final data = menuResponse.data;
        if (data is Map<String, dynamic>) {
          final itemsList = data['items'] ?? data['documents'] ?? [];
          if (itemsList is List) {
            items = itemsList
                .map((i) => MenuItem.fromMap(i as Map<String, dynamic>))
                .toList();
          }
        } else if (data is List) {
          items = data
              .map((i) => MenuItem.fromMap(i as Map<String, dynamic>))
              .toList();
        }
      }

      if (catResponse.success && catResponse.data != null) {
        final data = catResponse.data;
        if (data is Map<String, dynamic>) {
          final catsList = data['categories'] ?? data['documents'] ?? [];
          if (catsList is List) {
            categories = catsList
                .map((c) => MenuCategory.fromMap(c as Map<String, dynamic>))
                .toList();
          }
        } else if (data is List) {
          categories = data
              .map((c) => MenuCategory.fromMap(c as Map<String, dynamic>))
              .toList();
        }
      }

      if (items.isNotEmpty || categories.isNotEmpty) {
        state = state.copyWith(
          items: items,
          categories: categories,
          isLoading: false,
        );
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

  /// Refresh data from API
  Future<void> refresh() => _loadData();

  // ─── Category Operations ───

  Future<void> addCategory(String name) async {
    final tempCategory = MenuCategory(
      id: 'cat_${DateTime.now().millisecondsSinceEpoch}',
      restaurantId: '',
      name: name,
      sortOrder: state.categories.length,
    );
    state = state.copyWith(categories: [...state.categories, tempCategory]);

    try {
      final response = await _api.post(
        ApiConfig.partnerCategories,
        body: {'name': name, 'sort_order': state.categories.length - 1},
      );
      if (response.success && response.data != null) {
        final created = MenuCategory.fromMap(
          response.data as Map<String, dynamic>,
        );
        // Replace temp with real category
        final updated = state.categories.map((c) {
          return c.id == tempCategory.id ? created : c;
        }).toList();
        state = state.copyWith(categories: updated);
      }
    } catch (_) {}
  }

  Future<void> updateCategory(String categoryId, String newName) async {
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

    _api
        .put('${ApiConfig.partnerCategories}/$categoryId', body: {'name': newName})
        .ignore();
  }

  Future<void> toggleCategoryActive(String categoryId) async {
    MenuCategory? toggled;
    final updated = state.categories.map((c) {
      if (c.id == categoryId) {
        toggled = MenuCategory(
          id: c.id,
          restaurantId: c.restaurantId,
          name: c.name,
          sortOrder: c.sortOrder,
          isActive: !c.isActive,
        );
        return toggled!;
      }
      return c;
    }).toList();
    state = state.copyWith(categories: updated);

    if (toggled != null) {
      _api
          .put(
            '${ApiConfig.partnerCategories}/$categoryId',
            body: {'is_active': toggled!.isActive},
          )
          .ignore();
    }
  }

  Future<void> deleteCategory(String categoryId) async {
    state = state.copyWith(
      categories: state.categories.where((c) => c.id != categoryId).toList(),
      items: state.items.where((i) => i.categoryId != categoryId).toList(),
    );
    _api.delete('${ApiConfig.partnerCategories}/$categoryId').ignore();
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
      restaurantId: '',
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
        .then((response) {
      if (response.success && response.data != null) {
        final created = MenuItem.fromMap(
          response.data as Map<String, dynamic>,
        );
        final updated = state.items.map((i) {
          return i.id == newItem.id ? created : i;
        }).toList();
        state = state.copyWith(items: updated);
      }
    }).ignore();
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

    // Build body with only provided fields
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (price != null) body['price'] = price;
    if (description != null) body['description'] = description;
    if (isVeg != null) body['is_veg'] = isVeg;
    if (categoryId != null) body['category_id'] = categoryId;

    if (body.isNotEmpty) {
      _api.put('${ApiConfig.partnerMenu}/$itemId', body: body).ignore();
    }
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

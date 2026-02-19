import 'dart:convert';

/// Menu category model
class MenuCategory {
  final String id;
  final String restaurantId;
  final String name;
  final int sortOrder;
  final bool isActive;

  const MenuCategory({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory MenuCategory.fromMap(Map<String, dynamic> map) {
    return MenuCategory(
      id: map['\$id'] ?? '',
      restaurantId: map['restaurant_id'] ?? '',
      name: map['name'] ?? '',
      sortOrder: map['sort_order'] ?? 0,
      isActive: map['is_active'] ?? true,
    );
  }
}

/// Customization option within a group
class CustomizationOption {
  final String name;
  final double price;

  const CustomizationOption({required this.name, this.price = 0});

  factory CustomizationOption.fromMap(Map<String, dynamic> map) {
    return CustomizationOption(
      name: map['name'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'price': price};
}

/// Group of customization options (e.g. "Size", "Extra Toppings")
class CustomizationGroup {
  final String name;
  final List<CustomizationOption> options;
  final bool isRequired;
  final int maxSelections;

  const CustomizationGroup({
    required this.name,
    required this.options,
    this.isRequired = false,
    this.maxSelections = 1,
  });

  factory CustomizationGroup.fromMap(Map<String, dynamic> map) {
    return CustomizationGroup(
      name: map['group'] ?? map['name'] ?? '',
      options:
          (map['options'] as List<dynamic>?)
              ?.map((o) => CustomizationOption.fromMap(o))
              .toList() ??
          [],
      isRequired: map['is_required'] ?? false,
      maxSelections: map['max_selections'] ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
    'group': name,
    'options': options.map((o) => o.toMap()).toList(),
    'is_required': isRequired,
    'max_selections': maxSelections,
  };
}

/// Menu item model — maps to Appwrite `menu_items` collection
class MenuItem {
  final String id;
  final String restaurantId;
  final String categoryId;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final bool isVeg;
  final bool isAvailable;
  final bool isBestseller;
  final bool isMustTry;
  final String spiceLevel;
  final int preparationTimeMin;
  final List<CustomizationGroup> customizations;
  final int calories;
  final List<String> allergens;
  final int sortOrder;

  const MenuItem({
    required this.id,
    required this.restaurantId,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.price,
    this.imageUrl = '',
    required this.isVeg,
    this.isAvailable = true,
    this.isBestseller = false,
    this.isMustTry = false,
    this.spiceLevel = 'mild',
    this.preparationTimeMin = 20,
    this.customizations = const [],
    this.calories = 0,
    this.allergens = const [],
    this.sortOrder = 0,
  });

  factory MenuItem.fromMap(Map<String, dynamic> map) {
    List<CustomizationGroup> customizations = [];
    if (map['customizations'] != null) {
      try {
        final decoded = map['customizations'] is String
            ? jsonDecode(map['customizations'])
            : map['customizations'];
        if (decoded is List) {
          customizations = decoded
              .map((c) => CustomizationGroup.fromMap(c))
              .toList();
        }
      } catch (_) {}
    }

    return MenuItem(
      id: map['\$id'] ?? '',
      restaurantId: map['restaurant_id'] ?? '',
      categoryId: map['category_id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      imageUrl: map['image_url'] ?? '',
      isVeg: map['is_veg'] ?? false,
      isAvailable: map['is_available'] ?? true,
      isBestseller: map['is_bestseller'] ?? false,
      isMustTry: map['is_must_try'] ?? false,
      spiceLevel: map['spice_level'] ?? 'mild',
      preparationTimeMin: map['preparation_time_min'] ?? 20,
      customizations: customizations,
      calories: map['calories'] ?? 0,
      allergens: List<String>.from(map['allergens'] ?? []),
      sortOrder: map['sort_order'] ?? 0,
    );
  }

  /// Mock menu items for UI development
  static List<MenuItem> mockListForRestaurant(String restaurantId) => [
    MenuItem(
      id: '${restaurantId}_m1',
      restaurantId: restaurantId,
      categoryId: '${restaurantId}_c1',
      name: 'Chicken Biryani',
      description:
          'Fragrant basmati rice layered with tender chicken, aromatic spices & saffron',
      price: 299,
      isVeg: false,
      isBestseller: true,
      spiceLevel: 'medium',
      preparationTimeMin: 25,
      calories: 650,
      customizations: [
        CustomizationGroup(
          name: 'Portion',
          options: [
            CustomizationOption(name: 'Regular', price: 0),
            CustomizationOption(name: 'Large', price: 100),
          ],
          isRequired: true,
        ),
        CustomizationGroup(
          name: 'Extra',
          options: [
            CustomizationOption(name: 'Extra Raita', price: 30),
            CustomizationOption(name: 'Boiled Egg', price: 20),
            CustomizationOption(name: 'Salan', price: 40),
          ],
          maxSelections: 3,
        ),
      ],
    ),
    MenuItem(
      id: '${restaurantId}_m2',
      restaurantId: restaurantId,
      categoryId: '${restaurantId}_c1',
      name: 'Paneer Tikka',
      description:
          'Marinated cottage cheese grilled to perfection with mint chutney',
      price: 249,
      isVeg: true,
      isMustTry: true,
      spiceLevel: 'mild',
      preparationTimeMin: 15,
      calories: 380,
    ),
    MenuItem(
      id: '${restaurantId}_m3',
      restaurantId: restaurantId,
      categoryId: '${restaurantId}_c2',
      name: 'Butter Naan',
      description: 'Soft leavened bread brushed with butter',
      price: 59,
      isVeg: true,
      preparationTimeMin: 10,
      calories: 260,
    ),
    MenuItem(
      id: '${restaurantId}_m4',
      restaurantId: restaurantId,
      categoryId: '${restaurantId}_c2',
      name: 'Dal Makhani',
      description: 'Slow-cooked black lentils in creamy tomato gravy',
      price: 219,
      isVeg: true,
      isBestseller: true,
      spiceLevel: 'mild',
      preparationTimeMin: 20,
      calories: 420,
    ),
    MenuItem(
      id: '${restaurantId}_m5',
      restaurantId: restaurantId,
      categoryId: '${restaurantId}_c3',
      name: 'Gulab Jamun',
      description: 'Soft milk dumplings soaked in rose-flavored sugar syrup',
      price: 99,
      isVeg: true,
      preparationTimeMin: 5,
      calories: 320,
    ),
    MenuItem(
      id: '${restaurantId}_m6',
      restaurantId: restaurantId,
      categoryId: '${restaurantId}_c1',
      name: 'Tandoori Chicken',
      description:
          'Half chicken marinated in yogurt & spices, cooked in clay oven',
      price: 349,
      isVeg: false,
      isMustTry: true,
      spiceLevel: 'spicy',
      preparationTimeMin: 30,
      calories: 480,
    ),
  ];

  static List<MenuCategory> mockCategoriesForRestaurant(String restaurantId) =>
      [
        MenuCategory(
          id: '${restaurantId}_c1',
          restaurantId: restaurantId,
          name: 'Starters & Mains',
          sortOrder: 0,
        ),
        MenuCategory(
          id: '${restaurantId}_c2',
          restaurantId: restaurantId,
          name: 'Breads & Rice',
          sortOrder: 1,
        ),
        MenuCategory(
          id: '${restaurantId}_c3',
          restaurantId: restaurantId,
          name: 'Desserts',
          sortOrder: 2,
        ),
      ];
}

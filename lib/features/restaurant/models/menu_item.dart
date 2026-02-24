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

}

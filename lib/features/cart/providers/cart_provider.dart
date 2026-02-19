import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/menu_item.dart';

/// Cart item — a menu item with quantity and selected customizations
class CartItem {
  final MenuItem menuItem;
  final String restaurantId;
  final String restaurantName;
  final int quantity;
  final Map<String, List<CustomizationOption>> selectedCustomizations;

  const CartItem({
    required this.menuItem,
    required this.restaurantId,
    required this.restaurantName,
    this.quantity = 1,
    this.selectedCustomizations = const {},
  });

  CartItem copyWith({
    int? quantity,
    Map<String, List<CustomizationOption>>? selectedCustomizations,
  }) {
    return CartItem(
      menuItem: menuItem,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      quantity: quantity ?? this.quantity,
      selectedCustomizations:
          selectedCustomizations ?? this.selectedCustomizations,
    );
  }

  /// Total price including customization extras
  double get totalPrice {
    double customizationTotal = 0;
    for (final options in selectedCustomizations.values) {
      for (final option in options) {
        customizationTotal += option.price;
      }
    }
    return (menuItem.price + customizationTotal) * quantity;
  }

  /// Unique key combining item ID + customizations for cart deduplication
  String get cartKey {
    final customKey = selectedCustomizations.entries
        .map((e) => '${e.key}:${e.value.map((o) => o.name).join(",")}')
        .join('|');
    return '${menuItem.id}__$customKey';
  }
}

/// Cart state
class CartState {
  final List<CartItem> items;
  final String? restaurantId;
  final String? restaurantName;
  final String? couponCode;
  final double couponDiscount;
  final String deliveryInstructions;
  final String specialInstructions;

  const CartState({
    this.items = const [],
    this.restaurantId,
    this.restaurantName,
    this.couponCode,
    this.couponDiscount = 0,
    this.deliveryInstructions = '',
    this.specialInstructions = '',
  });

  CartState copyWith({
    List<CartItem>? items,
    String? restaurantId,
    String? restaurantName,
    String? couponCode,
    double? couponDiscount,
    String? deliveryInstructions,
    String? specialInstructions,
  }) {
    return CartState(
      items: items ?? this.items,
      restaurantId: restaurantId ?? this.restaurantId,
      restaurantName: restaurantName ?? this.restaurantName,
      couponCode: couponCode ?? this.couponCode,
      couponDiscount: couponDiscount ?? this.couponDiscount,
      deliveryInstructions: deliveryInstructions ?? this.deliveryInstructions,
      specialInstructions: specialInstructions ?? this.specialInstructions,
    );
  }

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);

  double get itemTotal => items.fold(0, (sum, item) => sum + item.totalPrice);
  double get deliveryFee => itemTotal > 500 ? 0 : 40; // Free above ₹500
  double get platformFee => 5;
  double get gst => (itemTotal * 0.05); // 5% GST
  double get discount => couponDiscount;
  double get grandTotal =>
      itemTotal + deliveryFee + platformFee + gst - discount;
}

/// Cart notifier
class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  /// Add item to cart — clears cart if switching restaurants
  void addItem(CartItem item) {
    // If cart has items from a different restaurant, clear first
    if (state.restaurantId != null && state.restaurantId != item.restaurantId) {
      // In real app, show confirmation dialog first
      state = CartState(
        restaurantId: item.restaurantId,
        restaurantName: item.restaurantName,
      );
    }

    final existingIndex = state.items.indexWhere(
      (i) => i.cartKey == item.cartKey,
    );

    List<CartItem> updatedItems;
    if (existingIndex >= 0) {
      updatedItems = [...state.items];
      updatedItems[existingIndex] = updatedItems[existingIndex].copyWith(
        quantity: updatedItems[existingIndex].quantity + item.quantity,
      );
    } else {
      updatedItems = [...state.items, item];
    }

    state = state.copyWith(
      items: updatedItems,
      restaurantId: item.restaurantId,
      restaurantName: item.restaurantName,
    );
  }

  /// Update quantity of an item
  void updateQuantity(String cartKey, int quantity) {
    if (quantity <= 0) {
      removeItem(cartKey);
      return;
    }

    final updatedItems = state.items.map((item) {
      if (item.cartKey == cartKey) {
        return item.copyWith(quantity: quantity);
      }
      return item;
    }).toList();

    state = state.copyWith(items: updatedItems);
  }

  /// Remove item from cart
  void removeItem(String cartKey) {
    final updatedItems = state.items
        .where((item) => item.cartKey != cartKey)
        .toList();

    if (updatedItems.isEmpty) {
      state = const CartState();
    } else {
      state = state.copyWith(items: updatedItems);
    }
  }

  /// Apply coupon
  void applyCoupon(String code, double discount) {
    state = state.copyWith(couponCode: code, couponDiscount: discount);
  }

  /// Remove coupon
  void removeCoupon() {
    state = state.copyWith(couponCode: null, couponDiscount: 0);
  }

  /// Set delivery instructions
  void setDeliveryInstructions(String instructions) {
    state = state.copyWith(deliveryInstructions: instructions);
  }

  /// Set special instructions
  void setSpecialInstructions(String instructions) {
    state = state.copyWith(specialInstructions: instructions);
  }

  /// Clear cart
  void clearCart() {
    state = const CartState();
  }
}

/// Global cart provider
final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});

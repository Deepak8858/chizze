/// Appwrite Cloud database & collection IDs
class AppwriteConstants {
  AppwriteConstants._();

  // Database
  static const String databaseId = 'chizze_db';

  // Collections
  static const String usersCollection = 'users';
  static const String addressesCollection = 'addresses';
  static const String restaurantsCollection = 'restaurants';
  static const String menuCategoriesCollection = 'menu_categories';
  static const String menuItemsCollection = 'menu_items';
  static const String ordersCollection = 'orders';
  static const String reviewsCollection = 'reviews';
  static const String couponsCollection = 'coupons';
  static const String notificationsCollection = 'notifications';
  static const String deliveryRequestsCollection = 'delivery_requests';
  static const String riderLocationsCollection = 'rider_locations';
  static const String paymentsCollection = 'payments';

  // Storage Buckets
  static const String restaurantImagesBucket = 'restaurant-images';
  static const String menuItemImagesBucket = 'menu-item-images';
  static const String userAvatarsBucket = 'user-avatars';
  static const String reviewPhotosBucket = 'review-photos';
  static const String promoBannersBucket = 'promo-banners';
}

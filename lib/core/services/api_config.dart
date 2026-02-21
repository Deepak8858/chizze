import '../../config/environment.dart';

/// API configuration constants for the Go backend
class ApiConfig {
  /// Base URL for the Go backend API — sourced from Environment config
  static String get baseUrl => Environment.apiBaseUrl;

  /// Request timeout in seconds
  static const int timeoutSeconds = 30;

  // ─── Endpoints ───

  // Auth
  static const String sendOtp = '/auth/send-otp';
  static const String verifyOtp = '/auth/verify-otp';
  static const String refreshToken = '/auth/refresh';
  static const String logout = '/auth/logout';

  // Users
  static const String profile = '/users/me';
  static const String addresses = '/users/me/addresses';

  // Restaurants
  static const String restaurants = '/restaurants';
  static const String nearbyRestaurants = '/restaurants/nearby';

  // Orders
  static const String orders = '/orders';

  // Payments
  static const String paymentInitiate = '/payments/initiate';
  static const String paymentVerify = '/payments/verify';

  // Coupons
  static const String coupons = '/coupons';
  static const String validateCoupon = '/cart/validate-coupon';

  // Notifications
  static const String notifications = '/notifications';

  // Partner
  static const String partnerDashboard = '/partner/dashboard';
  static const String partnerMenu = '/partner/menu';
  static const String partnerOrders = '/partner/orders';
  static const String partnerAnalytics = '/partner/analytics';
  static const String partnerCategories = '/partner/categories';
  static const String partnerRestaurantStatus = '/partner/restaurant/status';
  static const String partnerPerformance = '/partner/performance';

  // Delivery
  static const String deliveryDashboard = '/delivery/dashboard';
  static const String deliveryEarnings = '/delivery/earnings';
  static const String deliveryPerformance = '/delivery/performance';
  static const String deliveryStatus = '/delivery/status';
  static const String deliveryLocation = '/delivery/location';
  static const String deliveryOrders = '/delivery/orders';
}

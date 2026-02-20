/// API configuration constants for the Go backend
class ApiConfig {
  /// Base URL for the Go backend API
  /// Change to your deployed URL in production
  static const String baseUrl =
      'http://10.0.2.2:8080/api/v1'; // Android emulator → localhost
  // static const String baseUrl = 'http://localhost:8080/api/v1'; // iOS / Web

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
  static const String partnerMenu = '/partner/menu';
  static const String partnerOrders = '/partner/orders';
  static const String partnerAnalytics = '/partner/analytics';

  // Delivery
  static const String deliveryStatus = '/delivery/status';
  static const String deliveryLocation = '/delivery/location';
  static const String deliveryOrders = '/delivery/orders';
}

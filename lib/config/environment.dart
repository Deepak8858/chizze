/// Environment configuration — uses --dart-define for build-time config
///
/// Usage:
///   flutter run --dart-define=ENV=dev
///   flutter run --dart-define=ENV=staging --dart-define=API_URL=https://staging.chizze.in/api/v1
///   flutter build apk --dart-define=ENV=production --dart-define=API_URL=https://api.chizze.in/api/v1
class Environment {
  static const String appwriteProjectId = '6993347c0006ead7404d';
  static const String appwriteProjectName = 'chizze-restaurent';
  static const String appwritePublicEndpoint = 'https://sgp.cloud.appwrite.io/v1';

  /// Current environment (dev | staging | production)
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');

  /// API base URL — overridable via --dart-define=API_URL=...
  static const String _apiUrlOverride =
      String.fromEnvironment('API_URL', defaultValue: '');

  static String get apiBaseUrl {
    if (_apiUrlOverride.isNotEmpty) return _apiUrlOverride;
    switch (env) {
      case 'production':
        return 'https://api.chizze.in/api/v1';
      case 'staging':
        return 'https://staging.chizze.in/api/v1';
      default:
        // Dev — Android emulator: 10.0.2.2, real device: use your local IP
        return const String.fromEnvironment(
          'DEV_API_URL',
          defaultValue: 'http://10.0.2.2:8080/api/v1',
        );
    }
  }

  static bool get isProduction => env == 'production';
  static bool get isDev => env == 'dev';
  static bool get isStaging => env == 'staging';
}

/// Environment configuration — uses --dart-define for build-time config
///
/// Usage:
///   flutter run --dart-define=ENV=dev
///   flutter run --dart-define=ENV=staging --dart-define=API_URL=https://staging.chizze.in/api/v1
///   flutter build apk --dart-define=ENV=production --dart-define=API_URL=https://api.devdeepak.me/api/v1
class Environment {
  static const String appwriteProjectId = String.fromEnvironment(
    'APPWRITE_PROJECT_ID',
    defaultValue: '6993347c0006ead7404d',
  );
  static const String appwriteProjectName = 'chizze-restaurant';
  static const String appwritePublicEndpoint = String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: 'https://sgp.cloud.appwrite.io/v1',
  );

  /// Current environment (dev | staging | production)
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');

  /// API base URL — overridable via --dart-define=API_URL=...
  static const String _apiUrlOverride =
      String.fromEnvironment('API_URL', defaultValue: '');

  static String get apiBaseUrl {
    if (_apiUrlOverride.isNotEmpty) return _apiUrlOverride;
    switch (env) {
      case 'production':
        return 'https://api.devdeepak.me/api/v1';
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

  // ── Facebook SDK ──
  // App ID and Client Token come from Facebook Developer Console:
  //   App ID → Settings → Basic
  //   Client Token → Settings → Advanced → Client Token
  // The App ID is public (shipped in AndroidManifest/Info.plist), but the
  // Client Token can be overridden per-build if needed.
  static const String facebookAppId = String.fromEnvironment(
    'FB_APP_ID',
    defaultValue: '1871056600222264',
  );
  static const String facebookClientToken = String.fromEnvironment(
    'FB_CLIENT_TOKEN',
    defaultValue: 'eb2863427296c6f8551613aaee553ac6',
  );
  static const String facebookDisplayName = 'Chizze';
}

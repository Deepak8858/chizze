import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/theme.dart';
import 'core/router/app_router.dart';
import 'core/services/websocket_service.dart';
import 'core/services/api_client.dart';
import 'features/profile/providers/user_profile_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (non-fatal if config not present)
  try {
    await Firebase.initializeApp();
    debugPrint('[Firebase] Initialized successfully');
  } catch (e) {
    debugPrint('[Firebase] Not available: $e');
  }

  // Initialize offline cache (Hive)
  await cacheService.init();

  // Lock to portrait mode (mobile-only app)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Global error handler — catches uncaught Flutter exceptions
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[ErrorBoundary] ${details.exceptionAsString()}');
  };

  runApp(const ProviderScope(child: ChizzeApp()));
}

class ChizzeApp extends ConsumerWidget {
  const ChizzeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final isDark = ref.watch(userProfileProvider.select((p) => p.darkMode));

    // Activate WebSocket auto-connect (reacts to auth state)
    ref.watch(wsAutoConnectProvider);

    // Update system UI to match theme
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor:
            isDark ? AppColors.background : AppColors.lightBackground,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return MaterialApp.router(
      title: 'Chizze',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
    );
  }
}

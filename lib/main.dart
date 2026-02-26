import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/theme.dart';
import 'core/router/app_router.dart';
import 'core/services/websocket_service.dart';
import 'core/services/api_client.dart';
import 'features/profile/providers/user_profile_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';


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

  // Global error handler — catches uncaught Flutter exceptions and reports to Sentry
  // Note: SentryFlutter.init will override FlutterError.onError with its own handler
  // that respects beforeSend, so we set this BEFORE init as a pre-init safety net.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[ErrorBoundary] ${details.exceptionAsString()}');
    // Don't manually report — SentryFlutter's onError handler will take over
    // after init and apply beforeSend filters. Manual capture here would
    // bypass those filters and cause duplicate/noisy events.
  };

  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://18c1661519b0d5cdebbb190efc5e66bd@o4509849175326720.ingest.us.sentry.io/4510951045922816';
      // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
      // We recommend adjusting this value in production.
      options.tracesSampleRate = 1.0;
      // The sampling rate for profiling is relative to tracesSampleRate
      // Setting to 1.0 will profile 100% of sampled transactions:
      options.profilesSampleRate = 1.0;

      // Filter out transient/non-actionable errors before they reach Sentry
      // (Fixes FLUTTER-1, FLUTTER-8, FLUTTER-A, FLUTTER-9)
      options.beforeSend = (SentryEvent event, Hint hint) {
        final throwable = event.throwable;
        final message = throwable?.toString() ?? '';

        // Drop PermissionDeniedException — handled gracefully in location code
        if (message.contains('PermissionDeniedException') ||
            message.contains('User denied permissions')) {
          return null;
        }

        // Drop transient DNS/network errors — not bugs, user connectivity issues
        if (message.contains('Failed host lookup') ||
            message.contains('SocketException') ||
            message.contains('No address associated with hostname') ||
            message.contains('WebSocketChannelException')) {
          return null;
        }

        // Drop font loading failures — network-dependent, not actionable
        if (message.contains('Failed to load font')) {
          return null;
        }

        // Drop server 5xx errors (ApiException) — backend issues, not client bugs.
        // These are already logged server-side; no need to pollute Flutter Sentry.
        // (Fixes FLUTTER-6 regression: ApiException(500) from payment initiation)
        if (message.contains('ApiException(5') ||
            message.contains('ApiException(4')) {
          return null;
        }

        return event;
      };
    },
    appRunner: () => runApp(SentryWidget(child: const ProviderScope(child: ChizzeApp()))),
  );
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/restaurant/screens/restaurant_detail_screen.dart';
import '../../features/cart/screens/cart_screen.dart';
import '../../features/payment/screens/payment_screen.dart';
import '../../features/orders/screens/order_confirmation_screen.dart';
import '../../features/orders/screens/order_tracking_screen.dart';
import '../../features/orders/screens/orders_screen.dart';
import '../../features/orders/screens/review_screen.dart';
import '../../features/partner/screens/partner_dashboard_screen.dart';
import '../../features/partner/screens/partner_orders_screen.dart';
import '../../features/partner/screens/menu_management_screen.dart';
import '../../features/partner/screens/analytics_screen.dart';

/// GoRouter provider with auth + role-based redirects
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isAuth = authState.isAuthenticated;
      final isAuthRoute =
          state.uri.path == '/login' ||
          state.uri.path == '/otp' ||
          state.uri.path == '/';
      final isPartnerRoute = state.uri.path.startsWith('/partner');

      // Still loading initial auth check
      if (authState.status == AuthStatus.initial) return '/';

      // Not authenticated → redirect to login
      if (!isAuth && !isAuthRoute) return '/login';

      // Authenticated → redirect away from auth routes
      if (isAuth && isAuthRoute) {
        return authState.isPartner ? '/partner/dashboard' : '/home';
      }

      // Partner trying to access customer routes (and vice versa)
      if (isAuth && authState.isPartner && !isPartnerRoute && !isAuthRoute) {
        // Allow some shared routes
        if (state.uri.path == '/cart' ||
            state.uri.path == '/payment' ||
            state.uri.path.startsWith('/order') ||
            state.uri.path.startsWith('/review') ||
            state.uri.path.startsWith('/restaurant')) {
          return null;
        }
        return '/partner/dashboard';
      }

      return null; // No redirect needed
    },
    routes: [
      // ─── Splash ───
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),

      // ─── Auth ───
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return OtpScreen(
            phone: extra?['phone'] ?? '',
            userId: extra?['userId'] ?? '',
          );
        },
      ),

      // ─── Restaurant Detail (standalone) ───
      GoRoute(
        path: '/restaurant/:id',
        builder: (context, state) => RestaurantDetailScreen(
          restaurantId: state.pathParameters['id'] ?? '',
        ),
      ),

      // ─── Cart (standalone) ───
      GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),

      // ─── Payment (standalone) ───
      GoRoute(
        path: '/payment',
        builder: (context, state) => const PaymentScreen(),
      ),

      // ─── Order Confirmation ───
      GoRoute(
        path: '/order-confirmation/:id',
        builder: (context, state) =>
            OrderConfirmationScreen(orderId: state.pathParameters['id'] ?? ''),
      ),

      // ─── Order Tracking ───
      GoRoute(
        path: '/order-tracking/:id',
        builder: (context, state) =>
            OrderTrackingScreen(orderId: state.pathParameters['id'] ?? ''),
      ),

      // ─── Order Detail ───
      GoRoute(
        path: '/order-detail/:id',
        builder: (context, state) =>
            OrderTrackingScreen(orderId: state.pathParameters['id'] ?? ''),
      ),

      // ─── Review ───
      GoRoute(
        path: '/review/:id',
        builder: (context, state) =>
            ReviewScreen(orderId: state.pathParameters['id'] ?? ''),
      ),

      // ══════════════════════════════════════════
      // ─── Customer Shell (bottom nav) ───
      // ══════════════════════════════════════════
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SearchScreen()),
          ),
          GoRoute(
            path: '/orders',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: OrdersScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: Scaffold(
                body: Center(child: Text('Profile — Coming Soon')),
              ),
            ),
          ),
        ],
      ),

      // ══════════════════════════════════════════
      // ─── Partner Shell (bottom nav) ───
      // ══════════════════════════════════════════
      ShellRoute(
        builder: (context, state, child) => PartnerShell(child: child),
        routes: [
          GoRoute(
            path: '/partner/dashboard',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PartnerDashboardScreen()),
          ),
          GoRoute(
            path: '/partner/orders',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PartnerOrdersScreen()),
          ),
          GoRoute(
            path: '/partner/menu',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: MenuManagementScreen()),
          ),
          GoRoute(
            path: '/partner/analytics',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AnalyticsScreen()),
          ),
        ],
      ),
    ],
  );
});

// ══════════════════════════════════════════
// Customer Shell
// ══════════════════════════════════════════

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/orders')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF2A2A2A), width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex(context),
          onTap: (index) {
            switch (index) {
              case 0:
                context.go('/home');
              case 1:
                context.go('/search');
              case 2:
                context.go('/orders');
              case 3:
                context.go('/profile');
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search_rounded),
              label: 'Search',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long_rounded),
              label: 'Orders',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════
// Partner Shell
// ══════════════════════════════════════════

class PartnerShell extends ConsumerWidget {
  final Widget child;
  const PartnerShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/partner/dashboard')) return 0;
    if (location.startsWith('/partner/orders')) return 1;
    if (location.startsWith('/partner/menu')) return 2;
    if (location.startsWith('/partner/analytics')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF2A2A2A), width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex(context),
          onTap: (index) {
            switch (index) {
              case 0:
                context.go('/partner/dashboard');
              case 1:
                context.go('/partner/orders');
              case 2:
                context.go('/partner/menu');
              case 3:
                context.go('/partner/analytics');
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long_rounded),
              label: 'Orders',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.restaurant_menu_outlined),
              activeIcon: Icon(Icons.restaurant_menu_rounded),
              label: 'Menu',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.analytics_outlined),
              activeIcon: Icon(Icons.analytics_rounded),
              label: 'Analytics',
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/role_selection_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
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
import '../../features/delivery/screens/delivery_dashboard_screen.dart';
import '../../features/delivery/screens/active_delivery_screen.dart';
import '../../features/delivery/screens/earnings_screen.dart';
import '../../features/delivery/screens/delivery_profile_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/address_management_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/coupons/screens/coupons_screen.dart';

/// Notifier that bridges Riverpod auth state → GoRouter refreshListenable.
/// Only notifies when auth STATUS changes (not isLoading), so that in-progress
/// navigations (like push to OTP screen) aren't destroyed.
class _RouterNotifier extends ChangeNotifier {
  AuthState _authState = const AuthState();

  AuthState get authState => _authState;

  void update(AuthState newState) {
    // Notify GoRouter when auth status, role, or onboarding state changes.
    // NOT when isLoading toggles — that was destroying navigation state.
    final statusChanged = newState.status != _authState.status;
    final roleChanged = newState.userRole != _authState.userRole;
    final newUserChanged = newState.isNewUser != _authState.isNewUser;
    _authState = newState;
    if (statusChanged || roleChanged || newUserChanged) {
      debugPrint('[Router] Auth state changed → status=${newState.status}, role=${newState.userRole}, isNew=${newState.isNewUser}');
      notifyListeners();
    }
  }
}

/// Persistent router notifier — lives for the app lifetime.
final _routerNotifierProvider = Provider<_RouterNotifier>((ref) {
  final notifier = _RouterNotifier();
  ref.listen<AuthState>(authProvider, (_, next) {
    notifier.update(next);
  });
  // Seed with current value
  notifier.update(ref.read(authProvider));
  return notifier;
});

/// GoRouter provider — creates the router ONCE with refreshListenable.
/// Navigation state is preserved across auth loading changes.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = notifier.authState;
      final isAuth = authState.isAuthenticated;
      final isSplash = state.uri.path == '/';
      final isAuthRoute =
          state.uri.path == '/login' ||
          state.uri.path == '/otp' ||
          state.uri.path == '/role-select';
      final isOnboarding = state.uri.path == '/onboarding';
      final isPartnerRoute = state.uri.path.startsWith('/partner');

      debugPrint('[Router] redirect: path=${state.uri.path}, status=${authState.status}, isAuth=$isAuth, isNew=${authState.isNewUser}');

      // Still loading initial auth check — stay on splash
      if (authState.status == AuthStatus.initial) return isSplash ? null : '/';

      // Auth resolved — redirect away from splash
      if (isSplash) {
        if (isAuth) {
          // New user needs onboarding (name + location)
          if (authState.needsOnboarding) return '/onboarding';
          if (authState.isPartner) return '/partner/dashboard';
          if (authState.isDeliveryPartner) return '/delivery/dashboard';
          return '/home';
        }
        return '/role-select';
      }

      // Not authenticated → redirect to role selection (but allow auth routes)
      if (!isAuth && !isAuthRoute) return '/role-select';

      // Authenticated user on auth routes → redirect to proper home
      if (isAuth && isAuthRoute) {
        // New user needs onboarding first
        if (authState.needsOnboarding) return '/onboarding';
        if (authState.isPartner) return '/partner/dashboard';
        if (authState.isDeliveryPartner) return '/delivery/dashboard';
        return '/home';
      }

      // Authenticated user who needs onboarding → force onboarding (from any non-auth page)
      if (isAuth && authState.needsOnboarding && !isOnboarding && !isAuthRoute) {
        return '/onboarding';
      }

      // Authenticated user on onboarding — allow if still new, redirect if already onboarded
      if (isAuth && isOnboarding && !authState.needsOnboarding) {
        if (authState.isPartner) return '/partner/dashboard';
        if (authState.isDeliveryPartner) return '/delivery/dashboard';
        return '/home';
      }

      // Partner trying to access customer routes (and vice versa)
      if (isAuth && authState.isPartner && !isPartnerRoute && !isAuthRoute && !isOnboarding) {
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

      // ─── Role Selection ───
      GoRoute(path: '/role-select', builder: (context, state) => const RoleSelectionScreen()),

      // ─── Auth ───
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
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

      // ─── Onboarding (new user: name + location) ───
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),

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

      // ─── Addresses ───
      GoRoute(
        path: '/addresses',
        builder: (context, state) => const AddressManagementScreen(),
      ),

      // ─── Notifications ───
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),

      // ─── Coupons ───
      GoRoute(
        path: '/coupons',
        builder: (context, state) => const CouponsScreen(),
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
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProfileScreen()),
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

      // ══════════════════════════════════════════
      // ─── Delivery Shell (bottom nav) ───
      // ══════════════════════════════════════════
      ShellRoute(
        builder: (context, state, child) => DeliveryShell(child: child),
        routes: [
          GoRoute(
            path: '/delivery/dashboard',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DeliveryDashboardScreen()),
          ),
          GoRoute(
            path: '/delivery/active',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ActiveDeliveryScreen()),
          ),
          GoRoute(
            path: '/delivery/earnings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: EarningsScreen()),
          ),
          GoRoute(
            path: '/delivery/profile',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DeliveryProfileScreen()),
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

// ══════════════════════════════════════════
// Delivery Shell
// ══════════════════════════════════════════

class DeliveryShell extends ConsumerWidget {
  final Widget child;
  const DeliveryShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/delivery/dashboard')) return 0;
    if (location.startsWith('/delivery/active')) return 1;
    if (location.startsWith('/delivery/earnings')) return 2;
    if (location.startsWith('/delivery/profile')) return 3;
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
                context.go('/delivery/dashboard');
              case 1:
                context.go('/delivery/active');
              case 2:
                context.go('/delivery/earnings');
              case 3:
                context.go('/delivery/profile');
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.delivery_dining_outlined),
              activeIcon: Icon(Icons.delivery_dining_rounded),
              label: 'Active',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Earnings',
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

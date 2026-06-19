import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/dashboard/screens/monitor_detail_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      if (authState.isLoading) return null;
      if (authState.isAuthenticated && state.matchedLocation == '/login') {
        return '/dashboard';
      }
      if (!authState.isAuthenticated && state.matchedLocation != '/login') {
        return '/login';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, _) => const LoginScreen()),
      GoRoute(
        path: '/dashboard',
        builder: (context, _) => const DashboardScreen(),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (context, _) => const SettingsScreen(),
          ),
          GoRoute(
            path: 'monitor/:id',
            builder: (context, state) {
              final id =
                  int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return MonitorDetailScreen(monitorId: id);
            },
          ),
        ],
      ),
    ],
  );
});

import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/group_create_screen.dart';
import 'screens/group_join_screen.dart';
import 'screens/profile_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isAuth = session != null;
    final isAuthRoute = state.matchedLocation == '/login' ||
        state.matchedLocation == '/signup';

    if (!isAuth && !isAuthRoute) return '/login';
    if (isAuth && isAuthRoute) return '/calendar';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
    GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
    GoRoute(path: '/groups/create', builder: (_, __) => const GroupCreateScreen()),
    GoRoute(path: '/groups/join', builder: (_, __) => const GroupJoinScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
  ],
);

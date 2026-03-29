import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/group_create_screen.dart';
import 'screens/group_join_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/reset_password_screen.dart';

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      _authEvent = data.event;
      notifyListeners();
    });
  }

  AuthChangeEvent? _authEvent;
  AuthChangeEvent? get authEvent => _authEvent;
}

final _notifier = _RouterNotifier();

final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: _notifier,
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isAuth = session != null;
    final location = state.matchedLocation;
    final isPublicRoute = location == '/login' ||
        location == '/signup' ||
        location == '/forgot-password';

    if (_notifier.authEvent == AuthChangeEvent.passwordRecovery &&
        location != '/reset-password') {
      return '/reset-password';
    }
    if (!isAuth && !isPublicRoute && location != '/reset-password') {
      return '/login';
    }
    if (isAuth && isPublicRoute) return '/calendar';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
    GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
    GoRoute(path: '/reset-password', builder: (_, __) => const ResetPasswordScreen()),
    GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
    GoRoute(path: '/groups/create', builder: (_, __) => const GroupCreateScreen()),
    GoRoute(path: '/groups/join', builder: (_, __) => const GroupJoinScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
  ],
);

import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'go_router_refresh.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/update_password_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/group_create_screen.dart';
import 'screens/group_join_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/privacy_policy_screen.dart';

/// [setupAppRouter] 호출 전에 접근하지 마세요. `main()`에서 Supabase 초기화 직후 설정합니다.
late final GoRouter appRouter;

GoRouterRefreshNotifier? _authRefresh;

/// Supabase.initialize 이후에 한 번만 호출합니다.
void setupAppRouter() {
  _authRefresh?.dispose();
  _authRefresh = GoRouterRefreshNotifier();
  appRouter = GoRouter(
    refreshListenable: _authRefresh,
    initialLocation: '/login',
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isAuth = session != null;
      // matchedLocation이 비는 경우가 있어 uri.path를 함께 사용
      final path = state.uri.path.isNotEmpty
          ? state.uri.path
          : state.matchedLocation;
      final isLoginOrSignup = path == '/login' || path == '/signup';
      final isResetFlow = path == '/reset-password' || path == '/update-password';
      final isPrivacy = path == '/privacy';

      if (!isAuth && !isLoginOrSignup && !isResetFlow && !isPrivacy) {
        return '/login';
      }
      if (isAuth && isLoginOrSignup) return '/calendar';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(path: '/reset-password', builder: (_, _) => const ResetPasswordScreen()),
      GoRoute(path: '/update-password', builder: (_, _) => const UpdatePasswordScreen()),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyPolicyScreen()),
      GoRoute(path: '/calendar', builder: (_, _) => const CalendarScreen()),
      GoRoute(path: '/groups/create', builder: (_, _) => const GroupCreateScreen()),
      GoRoute(path: '/groups/join', builder: (_, _) => const GroupJoinScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    ],
  );
}

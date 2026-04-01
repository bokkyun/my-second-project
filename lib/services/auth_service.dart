import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// 아이디 → Supabase 이메일 변환 (웹과 동일한 방식)
String toEmail(String username) =>
    '${username.trim().toLowerCase()}@teamsync.local';

class AuthService {
  static final _client = Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

  /// 비밀번호 재설정 메일의 리다이렉트 URL (웹: 현재 오리진 /update-password)
  static String? get _passwordResetRedirectTo {
    if (kIsWeb) return '${Uri.base.origin}/update-password';
    // 네이티브에서 이메일 링크로 앱을 열려면 Supabase에 동일 URL 등록 후 딥링크 설정이 필요합니다.
    return null;
  }

  static Future<AuthResponse> signIn(String username, String password) {
    return _client.auth.signInWithPassword(
      email: toEmail(username),
      password: password,
    );
  }

  static Future<AuthResponse> signUp(
      String username, String password, String nickname) {
    return _client.auth.signUp(
      email: toEmail(username),
      password: password,
      data: {'nickname': nickname.isEmpty ? username : nickname},
    );
  }

  static Future<void> signOut() => _client.auth.signOut();

  /// 비밀번호 재설정 이메일 발송
  static Future<void> resetPasswordForEmail(String username) {
    return _client.auth.resetPasswordForEmail(
      toEmail(username),
      redirectTo: _passwordResetRedirectTo,
    );
  }

  /// 새 비밀번호로 변경 (재설정 링크 세션 또는 로그인 상태)
  static Future<UserResponse> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}

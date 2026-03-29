import 'package:supabase_flutter/supabase_flutter.dart';

/// 아이디 → Supabase 이메일 변환 (웹과 동일한 방식)
String toEmail(String username) =>
    '${username.trim().toLowerCase()}@teamsync.local';

class AuthService {
  static final _client = Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

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
}

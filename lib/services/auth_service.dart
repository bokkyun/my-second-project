import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final _client = Supabase.instance.client;

  static User? get currentUser => _client.auth.currentUser;

  static Future<AuthResponse> signIn(String email, String password) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<AuthResponse> signUp(
      String email, String password, String nickname) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: 'teamsync://login-callback/',
      data: {'nickname': nickname.isEmpty ? email.split('@').first : nickname},
    );
  }

  static Future<void> resetPassword(String email) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: 'teamsync://login-callback/',
    );
  }

  static Future<UserResponse> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<void> signOut() => _client.auth.signOut();
}

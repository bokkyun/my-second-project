import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool _isRetryableNetworkError(Object e) {
  if (e is TimeoutException) return true;
  final msg = e.toString().toLowerCase();
  if (msg.contains('failed host lookup') ||
      msg.contains('no address associated with hostname') ||
      msg.contains('socketexception') ||
      msg.contains('clientexception') ||
      msg.contains('connection reset') ||
      msg.contains('network is unreachable')) {
    return true;
  }
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    return m.contains('failed host lookup') ||
        m.contains('socketexception') ||
        m.contains('network');
  }
  return false;
}

class AuthService {
  static final _client = Supabase.instance.client;

  /// [Supabase 대시보드 → Authentication → Providers](https://supabase.com/dashboard/project/qrucuqdehrdqgsunfwfd/auth/providers)
  /// 에서 Email·Google을 활성화하고, Google의 Client ID/Secret을 넣습니다.
  ///
  /// **400 `redirect_uri_mismatch` 해결:** Google OAuth 요청의 `redirect_uri`는 항상 아래 **한 줄**입니다.
  /// [Google Cloud Console](https://console.cloud.google.com/apis/credentials) → **웹 애플리케이션** OAuth 클라이언트
  /// (Supabase에 넣은 Client ID와 **동일한** 항목) → **승인된 리디렉션 URI**에 아래를 **그대로** 추가합니다.
  ///
  /// `https://qrucuqdehrdqgsunfwfd.supabase.co/auth/v1/callback`
  ///
  /// **승인된 JavaScript 원본**에는 `http://localhost:포트`, `http://127.0.0.1:포트`(Flutter가 쓰는 포트),
  /// 배포 시 `https://배포도메인` 을 넣습니다. (끝 슬래시 없이 origin만)
  /// Supabase에 다른 프로젝트 URL을 쓰면 위 호스트도 그 프로젝트 ref에 맞게 바꿉니다.

  /// Google Cloud Console → **웹 애플리케이션** OAuth 클라이언트 ID (`web/index.html` meta와 동일).
  static const _googleWebClientId =
      '71423794065-a0csmmroi6e370f2hj0n3cghjt6t7qdh.apps.googleusercontent.com';

  static User? get currentUser => _client.auth.currentUser;

  static bool isValidEmail(String v) {
    final email = v.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  /// 웹(해시 라우터 `#/…`)에서 인증 메일 링크가 올바른 화면으로 오도록 `#/` 경로를 씁니다.
  static String? get _emailSignupRedirectTo {
    if (kIsWeb) return '${Uri.base.origin}/#/login';
    return null;
  }

  /// 비밀번호 재설정 메일의 리다이렉트 URL (웹: 해시 라우트)
  static String? get _passwordResetRedirectTo {
    if (kIsWeb) return '${Uri.base.origin}/#/update-password';
    // 네이티브에서 이메일 링크로 앱을 열려면 Supabase에 동일 URL 등록 후 딥링크 설정이 필요합니다.
    return null;
  }

  /// DNS 일시 실패 등에 대비해 짧게 재시도합니다.
  static Future<AuthResponse> signIn(String email, String password) async {
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await _client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
      } catch (e) {
        if (attempt < maxAttempts - 1 && _isRetryableNetworkError(e)) {
          await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }
    throw StateError('AuthService.signIn: unreachable');
  }

  static Future<AuthResponse> signUp(
      String email, String password, String nickname) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: _emailSignupRedirectTo,
      data: {'nickname': nickname},
    );
  }

  /// Google 소셜 로그인
  ///
  /// **웹:** [signInWithOAuth]로 진행합니다. Google에 넘기는 `redirect_uri`가 Supabase
  /// 콜백(`…/auth/v1/callback`)과 일치해 `redirect_uri_mismatch`를 피합니다.
  /// (GIS/`google_sign_in`만 쓰면 앱 출처 등 다른 redirect가 나와 콘솔과 안 맞을 수 있음.)
  /// Supabase 대시보드 → Redirect URLs에 `${Uri.base.origin}/**` 형태로 허용이 필요합니다.
  ///
  /// **Android·iOS:** [GoogleSignIn] + [signInWithIdToken].
  static Future<AuthResponse?> signInWithGoogle() async {
    if (kIsWeb) {
      final ok = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: '${Uri.base.origin}/',
        authScreenLaunchMode: LaunchMode.platformDefault,
      );
      if (!ok) {
        throw Exception('브라우저에서 Google 로그인을 시작할 수 없습니다.');
      }
      return null;
    }

    final googleSignIn = GoogleSignIn(
      serverClientId: _googleWebClientId,
    );
    final googleUser = await googleSignIn.signIn();

    if (googleUser == null) throw Exception('Google 로그인이 취소되었습니다.');

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;

    if (idToken == null) throw Exception('Google ID 토큰을 가져오지 못했습니다.');

    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  static Future<void> signOut() => _client.auth.signOut();

  /// 회원가입 인증 메일 재전송
  static Future<void> resendSignupEmail(String email) {
    return _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: _emailSignupRedirectTo,
    );
  }

  /// 비밀번호 재설정 이메일 발송
  static Future<void> resetPasswordForEmail(String email) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: _passwordResetRedirectTo,
    );
  }

  /// 새 비밀번호로 변경 (재설정 링크 세션 또는 로그인 상태)
  static Future<UserResponse> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// 현재 로그인 사용자 탈퇴 (DB 정리 + auth 계정 삭제)
  static Future<void> deleteMyAccount() async {
    await _client.rpc('delete_my_account');
  }
}

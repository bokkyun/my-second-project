import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../utils/network_messages.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;
  bool _googleLoading = false;
  bool _resendingVerification = false;
  String _error = '';
  String _pendingVerificationEmail = '';
  Timer? _loadingWatchdog;

  @override
  void dispose() {
    _loadingWatchdog?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _clearLoadingWatchdog() {
    _loadingWatchdog?.cancel();
    _loadingWatchdog = null;
  }

  Future<void> _submit() async {
    if (_loading) return;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력해주세요.');
      return;
    }
    if (!AuthService.isValidEmail(email)) {
      setState(() => _error = '올바른 이메일 형식을 입력해주세요.');
      return;
    }
    _clearLoadingWatchdog();
    _loadingWatchdog = Timer(const Duration(seconds: 28), () {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_error.isEmpty) {
          _error = '요청이 너무 오래 걸립니다. 네트워크를 확인하거나 앱을 다시 실행해주세요.';
        }
      });
    });
    setState(() {
      _error = '';
      _pendingVerificationEmail = '';
      _loading = true;
    });
    try {
      final res = await AuthService.signIn(email, password).timeout(
        const Duration(seconds: 22),
        onTimeout: () => throw TimeoutException('signIn'),
      );
      if (res.session == null) {
        setState(() => _error = '로그인에 실패했습니다. 이메일 인증이 필요하거나 세션이 없습니다.');
        return;
      }
      if (!mounted) return;
      context.go('/calendar');
    } on TimeoutException {
      setState(() => _error = '서버 응답이 없습니다. 인터넷 연결을 확인한 뒤 다시 시도해주세요.');
    } on AuthException catch (e) {
      final networkMsg = friendlyNetworkMessage(e.message);
      if (networkMsg != null) {
        setState(() => _error = networkMsg);
      } else {
        final msg = e.message.toLowerCase();
        setState(() => _error = msg.contains('email_not_confirmed') ||
                msg.contains('email not confirmed')
            ? '이메일 인증이 필요합니다. 메일함의 인증 링크를 눌러주세요.'
            : msg.contains('invalid login') || msg.contains('invalid credentials')
                ? '이메일 또는 비밀번호가 올바르지 않습니다.'
                : '로그인 오류: ${e.message}');
        if (msg.contains('email_not_confirmed') ||
            msg.contains('email not confirmed')) {
          _pendingVerificationEmail = email;
        }
      }
    } catch (e) {
      final networkMsg = friendlyNetworkMessage(e.toString());
      setState(() => _error = networkMsg ?? '연결 오류: $e');
    } finally {
      _clearLoadingWatchdog();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_googleLoading) return;
    setState(() {
      _error = '';
      _googleLoading = true;
    });
    try {
      await AuthService.signInWithGoogle();
      if (!mounted) return;
      context.go('/calendar');
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('취소')) return;
      setState(() => _error = 'Google 로그인 실패: $msg');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _resendVerification() async {
    final email = _pendingVerificationEmail.trim();
    if (email.isEmpty || _resendingVerification) return;
    setState(() => _resendingVerification = true);
    try {
      await AuthService.resendSignupEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('인증 메일을 다시 보냈습니다. 메일함을 확인해주세요.')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = '인증 메일 재전송 실패: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '인증 메일 재전송 오류: $e');
    } finally {
      if (mounted) setState(() => _resendingVerification = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primaryContainer.withOpacity(0.4), cs.secondaryContainer.withOpacity(0.4)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month, size: 52, color: cs.primary),
                      const SizedBox(height: 8),
                      Text('TeamSync', style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold, color: cs.primary)),
                      const SizedBox(height: 4),
                      Text('공유 스케줄 관리 서비스',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                      const SizedBox(height: 28),

                      if (_error.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(children: [
                            Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error, style: TextStyle(color: Colors.red.shade700))),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        if (_pendingVerificationEmail.isNotEmpty) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _resendingVerification
                                  ? null
                                  : _resendVerification,
                              child: Text(
                                _resendingVerification
                                    ? '재전송 중...'
                                    : '인증 메일 다시 보내기',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],

                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: '이메일'),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: '비밀번호',
                          counterText: '',
                          suffixIcon: IconButton(
                            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          // 로딩 중에도 비활성 회색 스타일이 되지 않도록 색 유지 (작은 흰 점처럼 보이는 현상 완화)
                          onPressed: _loading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            disabledBackgroundColor: cs.primary,
                            disabledForegroundColor: cs.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _loading
                              ? SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: cs.onPrimary,
                                  ),
                                )
                              : const Text('로그인', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context.go('/reset-password'),
                          child: const Text('비밀번호를 잊으셨나요?', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _googleLoading ? null : _signInWithGoogle,
                          icon: _googleLoading
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Image.network(
                                  'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                  width: 20, height: 20,
                                ),
                          label: const Text('Google로 로그인', style: TextStyle(fontSize: 15)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFDADCE0)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Text('계정이 없으신가요? '),
                        TextButton(
                          onPressed: () => context.go('/signup'),
                          child: const Text('회원가입', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => context.push('/privacy'),
                        child: Text(
                          '개인정보처리방침',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

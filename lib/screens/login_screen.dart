import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;
  String _error = '';

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '아이디와 비밀번호를 입력해주세요.');
      return;
    }
    setState(() {
      _error = '';
      _loading = true;
    });
    try {
      final res = await AuthService.signIn(username, password).timeout(
        const Duration(seconds: 25),
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
      final msg = e.message.toLowerCase();
      setState(() => _error = msg.contains('email_not_confirmed') ||
              msg.contains('email not confirmed')
          ? '이메일 인증이 필요합니다. 관리자에게 문의하세요.'
          : msg.contains('invalid login') || msg.contains('invalid credentials')
              ? '아이디 또는 비밀번호가 올바르지 않습니다.'
              : '로그인 오류: ${e.message}');
    } catch (e) {
      setState(() => _error = '연결 오류: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
                      ],

                      TextField(
                        controller: _usernameCtrl,
                        decoration: const InputDecoration(labelText: '아이디'),
                        maxLength: 20,
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
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
                          child: _loading
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _usernameCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;
  String _error = '';
  bool _success = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _nicknameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _isValidUsername(String v) => RegExp(r'^[a-zA-Z0-9_-]{3,20}$').hasMatch(v);

  Future<void> _submit() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    final nickname = _nicknameCtrl.text.trim();

    if (!_isValidUsername(username)) {
      setState(() => _error = '아이디는 3~20자의 영문, 숫자, _(밑줄), -(하이픈)만 사용 가능합니다.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = '비밀번호가 일치하지 않습니다.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '비밀번호는 6자 이상이어야 합니다.');
      return;
    }

    setState(() { _error = ''; _loading = true; });
    try {
      await AuthService.signUp(username, password, nickname);
      if (mounted) setState(() { _success = true; _loading = false; });
    } on AuthException catch (e) {
      String msg = '회원가입에 실패했습니다. 다시 시도해주세요.';
      if (e.message.contains('already registered')) msg = '이미 사용 중인 아이디입니다.';
      setState(() { _error = msg; _loading = false; });
    } catch (e) {
      setState(() { _error = '오류: $e'; _loading = false; });
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
                  child: _success ? _buildSuccess() : _buildForm(cs),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 52),
      const SizedBox(height: 12),
      const Text('회원가입이 완료되었습니다!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.go('/login'),
          child: const Text('로그인하러 가기'),
        ),
      ),
    ]);
  }

  Widget _buildForm(ColorScheme cs) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        IconButton(onPressed: () => context.go('/login'), icon: const Icon(Icons.arrow_back)),
        const Expanded(child: Center(child: Text('TeamSync 회원가입',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
        const SizedBox(width: 40),
      ]),
      const SizedBox(height: 20),

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
            Expanded(child: Text(_error, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
          ]),
        ),
        const SizedBox(height: 16),
      ],

      TextField(
        controller: _usernameCtrl,
        decoration: const InputDecoration(
          labelText: '아이디',
          helperText: '3~20자, 영문·숫자·_(밑줄)·-(하이픈) 사용 가능',
        ),
        maxLength: 20,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _nicknameCtrl,
        decoration: const InputDecoration(
          labelText: '닉네임 (선택)',
          helperText: '비워두면 아이디가 닉네임으로 사용됩니다',
          counterText: '',
        ),
        maxLength: 20,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passwordCtrl,
        obscureText: !_showPassword,
        decoration: InputDecoration(
          labelText: '비밀번호',
          helperText: '6자 이상',
          counterText: '',
          suffixIcon: IconButton(
            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _confirmCtrl,
        obscureText: !_showPassword,
        decoration: const InputDecoration(labelText: '비밀번호 확인', counterText: ''),
      ),
      const SizedBox(height: 24),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
          child: _loading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('회원가입', style: TextStyle(fontSize: 16)),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text('비밀번호를 잊으셨나요?', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700])),
          TextButton(
            onPressed: () => context.go('/reset-password'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('비밀번호 재설정', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => context.push('/privacy'),
        child: Text(
          '개인정보처리방침',
          style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
        ),
      ),
    ]);
  }
}

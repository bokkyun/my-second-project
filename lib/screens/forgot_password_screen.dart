import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String _error = '';
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '이메일을 입력해주세요.');
      return;
    }

    setState(() { _error = ''; _loading = true; });
    try {
      await AuthService.resetPassword(email);
      if (mounted) setState(() { _sent = true; _loading = false; });
    } catch (_) {
      setState(() { _error = '이메일 발송에 실패했습니다. 이메일 주소를 확인해주세요.'; _loading = false; });
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
                  child: _sent ? _buildSent(cs) : _buildForm(cs),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSent(ColorScheme cs) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.mark_email_read, color: cs.primary, size: 56),
      const SizedBox(height: 12),
      const Text('이메일을 확인해주세요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(
        '${_emailCtrl.text}로 비밀번호 재설정 링크를 발송했습니다.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.go('/login'),
          child: const Text('로그인으로 돌아가기'),
        ),
      ),
    ]);
  }

  Widget _buildForm(ColorScheme cs) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        IconButton(onPressed: () => context.go('/login'), icon: const Icon(Icons.arrow_back)),
        const Expanded(child: Center(child: Text('비밀번호 재설정',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
        const SizedBox(width: 40),
      ]),
      const SizedBox(height: 8),
      const Text(
        '가입한 이메일을 입력하면 비밀번호 재설정 링크를 보내드립니다.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.grey),
      ),
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
            Expanded(child: Text(_error, style: TextStyle(color: Colors.red.shade700))),
          ]),
        ),
        const SizedBox(height: 16),
      ],

      TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: '이메일'),
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
              : const Text('재설정 링크 발송', style: TextStyle(fontSize: 16)),
        ),
      ),
    ]);
  }
}

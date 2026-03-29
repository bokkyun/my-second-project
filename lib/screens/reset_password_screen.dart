import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;
  String _error = '';
  bool _success = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

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
      await AuthService.updatePassword(password);
      if (mounted) setState(() { _success = true; _loading = false; });
    } catch (_) {
      setState(() { _error = '비밀번호 변경에 실패했습니다. 다시 시도해주세요.'; _loading = false; });
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
                  child: _success ? _buildSuccess(cs) : _buildForm(cs),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess(ColorScheme cs) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 56),
      const SizedBox(height: 12),
      const Text('비밀번호가 변경되었습니다', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('새 비밀번호로 로그인해주세요.',
          style: TextStyle(fontSize: 14, color: Colors.grey)),
      const SizedBox(height: 24),
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
      Icon(Icons.lock_reset, size: 48, color: cs.primary),
      const SizedBox(height: 8),
      const Text('새 비밀번호 설정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
        controller: _passwordCtrl,
        obscureText: !_showPassword,
        decoration: InputDecoration(
          labelText: '새 비밀번호',
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
        decoration: const InputDecoration(labelText: '새 비밀번호 확인', counterText: ''),
      ),
      const SizedBox(height: 24),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary),
          child: _loading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('비밀번호 변경', style: TextStyle(fontSize: 16)),
        ),
      ),
    ]);
  }
}

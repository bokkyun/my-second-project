import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String _error = '';
  bool _success = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (!AuthService.isValidEmail(email)) {
      setState(() => _error = '올바른 이메일 형식을 입력해주세요.');
      return;
    }
    setState(() {
      _error = '';
      _success = false;
      _loading = true;
    });
    try {
      await AuthService.resetPasswordForEmail(email);
      if (mounted) setState(() => _success = true);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = '재설정 메일을 보내지 못했습니다: ${e.message}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '오류: $e');
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
            colors: [
              cs.primaryContainer.withOpacity(0.4),
              cs.secondaryContainer.withOpacity(0.4),
            ],
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => context.go('/login'),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          const Expanded(
                            child: Text(
                              '비밀번호 재설정',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '가입한 이메일을 입력하면 재설정 안내 메일을 보냅니다.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (_error.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(_error, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_success) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Text(
                            '메일함을 확인해 주세요. 링크를 누른 뒤 새 비밀번호를 설정할 수 있습니다.',
                            style: TextStyle(color: Colors.green.shade800, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: '이메일'),
                        enabled: !_success,
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: (_loading || _success) ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('재설정 메일 보내기', style: TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('로그인으로', style: TextStyle(fontWeight: FontWeight.w600)),
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

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/group_service.dart';

class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();
  Color _color = const Color(0xFF1976D2);
  bool _isSearchable = false;
  bool _loading = false;
  bool _showPw = false;
  String _error = '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  void _pickColor() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('그룹 색상 선택'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: _color,
            onColorChanged: (c) => setState(() => _color = c),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인')),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = '그룹 이름을 입력해주세요.');
      return;
    }
    if (_pwCtrl.text.trim().isEmpty) {
      setState(() => _error = '그룹 비밀번호를 입력해주세요.');
      return;
    }
    if (_pwCtrl.text.trim() != _pwConfirmCtrl.text.trim()) {
      setState(() => _error = '비밀번호가 일치하지 않습니다.');
      return;
    }
    setState(() { _error = ''; _loading = true; });
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await GroupService.createGroup(
        userId: userId,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        color: _colorToHex(_color),
        isSearchable: _isSearchable,
        password: _pwCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('그룹이 생성되었습니다!')));
        context.go('/calendar');
      }
    } catch (e) {
      setState(() => _error = '그룹 생성 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('그룹 생성'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/calendar')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_error.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(_error, style: TextStyle(color: Colors.red.shade700)),
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '그룹 이름 *'),
              maxLength: 30,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: '설명 (선택)', counterText: ''),
              maxLines: 3,
              maxLength: 100,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pwCtrl,
              obscureText: !_showPw,
              decoration: InputDecoration(
                labelText: '그룹 비밀번호 *',
                helperText: '가입 시 이 비밀번호를 입력해야 합니다.',
                counterText: '',
                suffixIcon: IconButton(
                  icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPw = !_showPw),
                ),
              ),
              maxLength: 30,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pwConfirmCtrl,
              obscureText: !_showPw,
              decoration: const InputDecoration(
                labelText: '비밀번호 확인 *',
                counterText: '',
              ),
              maxLength: 30,
            ),
            const SizedBox(height: 20),

            const Text('그룹 색상', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickColor,
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                ),
                const SizedBox(width: 12),
                Text(_colorToHex(_color), style: const TextStyle(fontFamily: 'monospace')),
                const SizedBox(width: 8),
                const Text('(탭하여 변경)', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 20),

            SwitchListTile(
              title: const Text('그룹 검색 허용'),
              subtitle: const Text('다른 사용자가 이 그룹을 검색할 수 있습니다'),
              value: _isSearchable,
              onChanged: (v) => setState(() => _isSearchable = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('그룹 생성', style: TextStyle(fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
: Colors.white))
                    : const Text('그룹 생성', style: TextStyle(fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

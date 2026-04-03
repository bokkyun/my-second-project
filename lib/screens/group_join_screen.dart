import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/group_service.dart';

class GroupJoinScreen extends StatefulWidget {
  const GroupJoinScreen({super.key});

  @override
  State<GroupJoinScreen> createState() => _GroupJoinScreenState();
}

class _GroupJoinScreenState extends State<GroupJoinScreen> {
  final _searchCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  String _joiningId = '';
  bool _showPw = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    final res = await GroupService.searchGroups(q);
    if (mounted) setState(() { _results = res; _searching = false; });
  }

  Future<void> _openPasswordDialog(String groupId) async {
    _pwCtrl.clear();
    setState(() => _showPw = false);
    var notifyOnJoin = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('그룹 비밀번호 입력'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _pwCtrl,
                  obscureText: !_showPw,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    suffixIcon: IconButton(
                      icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDlgState(() => _showPw = !_showPw),
                    ),
                  ),
                  onSubmitted: (_) => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: notifyOnJoin,
                  onChanged: (v) => setDlgState(() => notifyOnJoin = v ?? true),
                  title: const Text('그룹 일정 푸시 알림'),
                  subtitle: const Text(
                    '그룹원이 일정을 등록하면 알려받습니다(기기에 Firebase 설정 시).',
                    style: TextStyle(fontSize: 12),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('확인')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _join(groupId, _pwCtrl.text.trim(), notifyGroupEvents: notifyOnJoin);
    }
  }

  Future<void> _join(String groupId, String password, {bool notifyGroupEvents = true}) async {
    setState(() => _joiningId = groupId);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await GroupService.joinGroup(groupId, userId, password, notifyGroupEvents: notifyGroupEvents);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('그룹에 가입했습니다!')));
        context.go('/calendar');
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('비밀번호') ? '비밀번호가 틀렸습니다.' : '이미 가입한 그룹이거나 오류가 발생했습니다.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _joiningId = '');
    }
  }

  Color _parseColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('그룹 가입'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/calendar')),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: OutlinedButton.icon(
          onPressed: () => context.go('/groups/create'),
          icon: const Icon(Icons.add),
          label: const Text('새 그룹 만들기'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: '그룹 이름 검색',
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.text,
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _searching ? null : _search,
              child: const Text('검색'),
            ),
          ]),
          const SizedBox(height: 16),

          if (_searching)
            const Center(child: CircularProgressIndicator())
          else if (_results.isEmpty && _searchCtrl.text.isNotEmpty)
            const Center(child: Text('검색 결과가 없습니다.', style: TextStyle(color: Colors.grey)))
          else
            Expanded(
              child: ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final g = _results[i];
                  final color = _parseColor(g['color'] as String? ?? '#1976d2');
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: color,
                        child: Text((g['name'] as String)[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white))),
                    title: Text(g['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: g['description'] != null && (g['description'] as String).isNotEmpty
                        ? Text(g['description'] as String, maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: _joiningId == g['id']
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : ElevatedButton(
                            onPressed: () => _openPasswordDialog(g['id'] as String),
                            child: const Text('가입'),
                          ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }
}

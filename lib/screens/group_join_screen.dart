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
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  String _joiningId = '';

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    final res = await GroupService.searchGroups(q);
    if (mounted) setState(() { _results = res; _searching = false; });
  }

  Future<void> _join(String groupId) async {
    setState(() => _joiningId = groupId);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await GroupService.joinGroup(groupId, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('그룹에 가입했습니다!')));
        context.go('/calendar');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 가입한 그룹이거나 오류가 발생했습니다.')));
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
                            onPressed: () => _join(g['id'] as String),
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

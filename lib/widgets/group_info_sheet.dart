import 'package:flutter/material.dart';
import '../models/group.dart';
import '../services/group_service.dart';

class GroupInfoSheet extends StatefulWidget {
  final Group group;
  final Future<void> Function(String groupId) onLeave;
  final Future<void> Function(String groupId) onDelete;
  final Future<void> Function(String groupId, String newAdminUserId)? onChangeAdmin;

  const GroupInfoSheet({
    super.key,
    required this.group,
    required this.onLeave,
    required this.onDelete,
    this.onChangeAdmin,
  });

  @override
  State<GroupInfoSheet> createState() => _GroupInfoSheetState();
}

class _GroupInfoSheetState extends State<GroupInfoSheet> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  bool _changeAdminMode = false;
  String? _selectedNewAdminId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final members = await GroupService.fetchGroupMembers(widget.group.id);
    if (mounted) setState(() { _members = members; _loading = false; });
  }

  String _roleLabel(String role) {
    if (role == 'admin') return '관리자';
    if (role == 'readonly') return '읽기 전용';
    return '일반 멤버';
  }

  Future<void> _handleChangeAdmin() async {
    if (_selectedNewAdminId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('관리자 변경'),
        content: const Text('선택한 멤버에게 관리자 권한을 이전합니다.\n현재 관리자는 일반 멤버로 변경됩니다.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context);
      await widget.onChangeAdmin!(widget.group.id, _selectedNewAdminId!);
    }
  }

  Future<void> _confirmAction(String title, String content, Future<void> Function() action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context);
      await action();
    }
  }

  Widget _buildChangeAdminPanel() {
    final nonAdminMembers = _members.where((m) => m['role'] != 'admin').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('새 관리자를 선택하세요', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      const Text('현재 관리자 권한이 이전됩니다.',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _selectedNewAdminId,
        decoration: const InputDecoration(
          labelText: '새 관리자',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: nonAdminMembers.map((m) {
          final label = m['nickname'] as String? ?? m['email'] as String? ?? '알 수 없음';
          return DropdownMenuItem<String>(value: m['id'] as String, child: Text(label));
        }).toList(),
        onChanged: (v) => setState(() => _selectedNewAdminId = v),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => setState(() { _changeAdminMode = false; _selectedNewAdminId = null; }),
            child: const Text('취소'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _selectedNewAdminId != null ? _handleChangeAdmin : null,
            child: const Text('변경'),
          ),
        ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 4, width: 40, margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),

        // 제목
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Container(
              width: 14, height: 14,
              decoration: BoxDecoration(color: group.flutterColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(group.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
        ),

        if (group.description != null && group.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(group.description!, style: const TextStyle(color: Colors.grey)),
          ),

        const Divider(),

        // 멤버 목록
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Text('멤버${_loading ? '' : ' (${_members.length}명)'}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),

        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _members.length,
              itemBuilder: (_, i) {
                final m = _members[i];
                final nickname = m['nickname'] as String? ?? m['email'] as String? ?? '알 수 없음';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: group.flutterColor,
                    radius: 16,
                    child: Text(nickname[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                  title: Text(nickname, style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: Chip(
                    label: Text(_roleLabel(m['role'] as String),
                        style: const TextStyle(fontSize: 12)),
                    backgroundColor: m['role'] == 'admin'
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.grey.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              },
            ),
          ),

        const Divider(),

        // 하단 버튼
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
          child: _changeAdminMode
              ? _buildChangeAdminPanel()
              : Row(children: [
                  if (group.myRole == 'admin') ...[
                    if (widget.onChangeAdmin != null && _members.any((m) => m['role'] != 'admin'))
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() { _changeAdminMode = true; _selectedNewAdminId = null; }),
                          icon: const Icon(Icons.admin_panel_settings, size: 18),
                          label: const Text('관리자 변경'),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmAction(
                          '그룹 삭제',
                          '${group.name} 그룹을 삭제하면 복구할 수 없습니다.',
                          () => widget.onDelete(group.id),
                        ),
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text('그룹 삭제', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmAction(
                          '그룹 탈퇴',
                          '${group.name} 그룹에서 탈퇴하시겠습니까?',
                          () => widget.onLeave(group.id),
                        ),
                        icon: const Icon(Icons.exit_to_app, color: Colors.red),
                        label: const Text('그룹 탈퇴', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
                    ),
                  ),
                ]),
        ),
      ]),
    );
  }
}

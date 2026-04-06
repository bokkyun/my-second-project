import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/group.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../widgets/daily_reminder_settings_panel.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nicknameCtrl = TextEditingController();
  String? _currentNickname;
  List<Group> _groups = [];
  bool _loading = true;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = AuthService.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    final groups = await GroupService.fetchMyGroups(userId);
    if (mounted) {
      setState(() {
        _currentNickname = profile['nickname'] as String?;
        _nicknameCtrl.text = _currentNickname ?? '';
        _groups = groups;
        _loading = false;
      });
    }
  }

  Future<void> _saveNickname() async {
    if (_nicknameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'nickname': _nicknameCtrl.text.trim()})
          .eq('id', AuthService.currentUser!.id);
      setState(() => _currentNickname = _nicknameCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필이 저장되었습니다!')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장 중 오류가 발생했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leaveGroup(Group group) async {
    final confirmed = await _showConfirmDialog(
      '그룹 탈퇴',
      '${group.name} 그룹에서 탈퇴하시겠습니까?',
    );
    if (!confirmed) return;
    await GroupService.leaveGroup(group.id, AuthService.currentUser!.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('그룹에서 탈퇴했습니다.')));
    }
  }

  Future<void> _deleteGroup(Group group) async {
    final confirmed = await _showConfirmDialog(
      '그룹 삭제',
      '${group.name} 그룹을 삭제하면 복구할 수 없습니다.',
      confirmLabel: '삭제',
      isDanger: true,
    );
    if (!confirmed) return;
    await GroupService.deleteGroup(group.id, AuthService.currentUser!.id);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('그룹이 삭제되었습니다.')));
    }
  }

  Future<bool> _showConfirmDialog(String title, String content,
      {String confirmLabel = '확인', bool isDanger = false}) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Text(content),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: isDanger
                    ? ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white)
                    : null,
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('프로필 설정'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/calendar'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // 아바타
                  Center(
                    child: Column(children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          (_currentNickname ?? '?')[0].toUpperCase(),
                          style: const TextStyle(fontSize: 28, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AuthService.currentUser?.email
                                ?.replaceAll('@teamsync.local', '') ??
                            '',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // 닉네임 수정
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('닉네임', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nicknameCtrl,
                          decoration: const InputDecoration(labelText: '닉네임', counterText: ''),
                          maxLength: 20,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _saveNickname,
                            child: _saving
                                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('저장'),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 매일 일정 요약 (요일별 시각)
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: const DailyReminderSettingsPanel(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 내 그룹 목록
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('내 그룹', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 8),
                        if (_groups.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: Text('속한 그룹이 없습니다.', style: TextStyle(color: Colors.grey))),
                          )
                        else
                          ..._groups.map((g) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  width: 12, height: 12,
                                  decoration: BoxDecoration(
                                    color: g.flutterColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                title: Text(g.name),
                                subtitle: Text(g.myRole == 'admin' ? '관리자' : g.myRole == 'readonly' ? '읽기 전용' : '일반 멤버'),
                                trailing: g.myRole == 'admin'
                                    ? OutlinedButton(
                                        onPressed: () => _deleteGroup(g),
                                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                                        child: const Text('삭제'),
                                      )
                                    : OutlinedButton(
                                        onPressed: () => _leaveGroup(g),
                                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                                        child: const Text('탈퇴'),
                                      ),
                              )),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 약관 · 개인정보
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: const Text('개인정보처리방침'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/privacy'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 로그아웃
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('계정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _signOut,
                            icon: const Icon(Icons.logout, color: Colors.red),
                            label: const Text('로그아웃', style: TextStyle(color: Colors.red)),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

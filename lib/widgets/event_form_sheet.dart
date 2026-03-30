import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/group.dart';

class EventFormSheet extends StatefulWidget {
  final DateTime? defaultDate;
  final CalendarEvent? editEvent;
  final List<Group> groups;
  final Set<String> adminGroupIds;
  final Future<List<Map<String, dynamic>>> Function(String groupId)? onFetchMembers;
  final Future<void> Function({
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool isAllDay,
    required String color,
    required List<String> groupIds,
    String? targetUserId,
  }) onSave;

  const EventFormSheet({
    super.key,
    this.defaultDate,
    this.editEvent,
    required this.groups,
    required this.onSave,
    this.adminGroupIds = const {},
    this.onFetchMembers,
  });

  @override
  State<EventFormSheet> createState() => _EventFormSheetState();
}

class _EventFormSheetState extends State<EventFormSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  late DateTime _startsAt;
  late DateTime _endsAt;
  bool _isAllDay = false;
  Color _color = const Color(0xFF1976D2);
  final Set<String> _selectedGroupIds = {};
  bool _saving = false;
  String? _targetUserId;
  List<Map<String, dynamic>> _groupMembers = [];
  bool _membersLoading = false;

  @override
  void initState() {
    super.initState();
    final ev = widget.editEvent;
    if (ev != null) {
      _titleCtrl.text = ev.title;
      _descCtrl.text = ev.description ?? '';
      _startsAt = ev.startsAt;
      _endsAt = ev.endsAt;
      _isAllDay = ev.isAllDay;
      _color = ev.flutterColor;
      _selectedGroupIds.addAll(ev.groupIds);
    } else {
      final base = widget.defaultDate ?? DateTime.now();
      _startsAt = DateTime(base.year, base.month, base.day, 9);
      _endsAt = DateTime(base.year, base.month, base.day, 10);
    }
  }

  /** 체크된 관리자 그룹의 멤버만 로드 */
  Future<void> _updateMembersForSelectedGroups() async {
    if (widget.onFetchMembers == null) return;

    final selectedAdminGroupIds = _selectedGroupIds
        .where((gid) => widget.adminGroupIds.contains(gid))
        .toList();

    if (selectedAdminGroupIds.isEmpty) {
      if (mounted) setState(() { _groupMembers = []; _targetUserId = null; });
      return;
    }

    setState(() => _membersLoading = true);
    try {
      final results = await Future.wait(
        selectedAdminGroupIds.map((gid) => widget.onFetchMembers!(gid)),
      );
      final all = results.expand((r) => r).toList();
      final unique = <String, Map<String, dynamic>>{};
      for (final m in all) {
        unique[m['id'] as String] = m;
      }
      if (mounted) {
        final newMembers = unique.values.toList();
        setState(() {
          _groupMembers = newMembers;
          /** 선택된 멤버가 새 목록에 없으면 초기화 */
          if (_targetUserId != null && !newMembers.any((m) => m['id'] == _targetUserId)) {
            _targetUserId = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _membersLoading = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Future<void> _pickDateTime(bool isStart) async {
    final init = isStart ? _startsAt : _endsAt;
    final date = await showDatePicker(
      context: context, initialDate: init,
      firstDate: DateTime(2020), lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return;
    if (_isAllDay) {
      setState(() {
        if (isStart) _startsAt = date;
        else _endsAt = date;
      });
      return;
    }
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(init));
    if (time == null || !mounted) return;
    final result = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startsAt = result;
        if (_endsAt.isBefore(_startsAt)) _endsAt = _startsAt.add(const Duration(hours: 1));
      } else {
        _endsAt = result;
      }
    });
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목을 입력해주세요.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        startsAt: _startsAt,
        endsAt: _isAllDay ? DateTime(_endsAt.year, _endsAt.month, _endsAt.day, 23, 59) : _endsAt,
        isAllDay: _isAllDay,
        color: _colorToHex(_color),
        groupIds: _selectedGroupIds.toList(),
        targetUserId: _targetUserId,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장 중 오류가 발생했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmtDate(DateTime dt) => DateFormat('yyyy.MM.dd (E) HH:mm', 'ko').format(dt);
  String _fmtDateOnly(DateTime dt) => DateFormat('yyyy.MM.dd (E)', 'ko').format(dt);

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editEvent != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(height: 4, width: 40, margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text(isEdit ? '일정 수정' : '새 일정',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: _saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('저장'),
              ),
            ]),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: '제목 *'),
                  maxLength: 50,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(labelText: '메모 (선택)', counterText: ''),
                  maxLines: 2,
                  maxLength: 200,
                ),
                const SizedBox(height: 16),

                SwitchListTile(
                  title: const Text('하루 종일'),
                  value: _isAllDay,
                  onChanged: (v) => setState(() => _isAllDay = v),
                  contentPadding: EdgeInsets.zero,
                ),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('시작'),
                  subtitle: Text(_isAllDay ? _fmtDateOnly(_startsAt) : _fmtDate(_startsAt)),
                  onTap: () => _pickDateTime(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('종료'),
                  subtitle: Text(_isAllDay ? _fmtDateOnly(_endsAt) : _fmtDate(_endsAt)),
                  onTap: () => _pickDateTime(false),
                ),
                const SizedBox(height: 8),

                // 색상
                Row(children: [
                  const Text('색상', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('색상 선택'),
                        content: BlockPicker(
                          pickerColor: _color,
                          onColorChanged: (c) => setState(() => _color = c),
                        ),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
                      ),
                    ),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: _color,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),

                /** 등록 대상 선택 - 체크된 그룹 중 관리자 그룹이 있을 때만 표시 */
                if (widget.editEvent == null && (_membersLoading || _groupMembers.isNotEmpty)) ...[
                  const Text('등록 대상', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _membersLoading
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : DropdownButtonFormField<String?>(
                          value: _targetUserId,
                          decoration: const InputDecoration(
                            labelText: '등록 대상',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('본인 (나)')),
                            ..._groupMembers.map((m) => DropdownMenuItem(
                              value: m['id'] as String,
                              child: Text(
                                m['nickname'] as String? ??
                                m['email'] as String? ??
                                m['id'] as String,
                              ),
                            )),
                          ],
                          onChanged: (v) => setState(() => _targetUserId = v),
                        ),
                  const SizedBox(height: 16),
                ],

                if (widget.groups.isNotEmpty) ...[
                  const Text('공유할 그룹', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 4,
                    children: widget.groups.map((g) {
                      final selected = _selectedGroupIds.contains(g.id);
                      return FilterChip(
                        label: Text(g.name),
                        selected: selected,
                        selectedColor: g.flutterColor.withOpacity(0.25),
                        checkmarkColor: g.flutterColor,
                        onSelected: (v) {
                          setState(() {
                            if (v) _selectedGroupIds.add(g.id);
                            else _selectedGroupIds.remove(g.id);
                          });
                          if (widget.adminGroupIds.contains(g.id)) {
                            _updateMembersForSelectedGroups();
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

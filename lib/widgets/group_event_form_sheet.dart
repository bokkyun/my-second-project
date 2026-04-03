import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intl/intl.dart';

import '../models/group.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';

/// 한 그룹을 선택해 **전 구성원**에게 보이는 이벤트 등록 (`event_kind = group_event`)
class GroupEventFormSheet extends StatefulWidget {
  final List<Group> groups;
  final DateTime? defaultDate;

  const GroupEventFormSheet({
    super.key,
    required this.groups,
    this.defaultDate,
  });

  @override
  State<GroupEventFormSheet> createState() => _GroupEventFormSheetState();
}

class _GroupEventFormSheetState extends State<GroupEventFormSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  late DateTime _startsAt;
  late DateTime _endsAt;
  bool _isAllDay = false;
  Color _color = const Color(0xFF1976D2);
  String? _groupId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final base = widget.defaultDate ?? DateTime.now();
    _startsAt = DateTime(base.year, base.month, base.day, 9);
    _endsAt = DateTime(base.year, base.month, base.day, 10);
    if (widget.groups.isNotEmpty) {
      _groupId = widget.groups.first.id;
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

  String _fmtDate(DateTime dt) => DateFormat('yyyy.MM.dd (E) HH:mm', 'ko').format(dt);
  String _fmtDateOnly(DateTime dt) => DateFormat('yyyy.MM.dd (E)', 'ko').format(dt);

  Future<void> _pickDateTime(bool isStart) async {
    final init = isStart ? _startsAt : _endsAt;
    final date = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return;
    if (_isAllDay) {
      setState(() {
        if (isStart) {
          _startsAt = date;
        } else {
          _endsAt = date;
        }
      });
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(init),
    );
    if (time == null || !mounted) return;
    final result = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startsAt = result;
        if (_endsAt.isBefore(_startsAt)) {
          _endsAt = _startsAt.add(const Duration(hours: 1));
        }
      } else {
        _endsAt = result;
      }
    });
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목을 입력해주세요.')),
      );
      return;
    }
    if (_groupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('그룹을 선택해주세요.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await EventService.createEvent(
        userId: AuthService.currentUser!.id,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        startsAt: _startsAt,
        endsAt: _isAllDay
            ? DateTime(_endsAt.year, _endsAt.month, _endsAt.day, 23, 59)
            : _endsAt,
        isAllDay: _isAllDay,
        color: _colorToHex(_color),
        groupIds: [_groupId!],
        eventKind: 'group_event',
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장 중 오류가 발생했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.groups, color: cs.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '그룹 이벤트 만들기',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('등록'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '선택한 그룹의 모든 구성원 캘린더에 표시됩니다. 알림을 켠 멤버에게는 푸시가 전송될 수 있습니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.groups.isEmpty)
                      const Text('속한 그룹이 없습니다. 그룹을 만든 뒤 이용해 주세요.')
                    else ...[
                      DropdownButtonFormField<String>(
                        value: _groupId,
                        decoration: const InputDecoration(
                          labelText: '그룹 선택 *',
                          border: OutlineInputBorder(),
                        ),
                        items: widget.groups
                            .map(
                              (g) => DropdownMenuItem(
                                value: g.id,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: g.flutterColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(g.name)),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _groupId = v),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                          labelText: '이벤트 제목 *',
                        ),
                        maxLength: 50,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descCtrl,
                        decoration: const InputDecoration(
                          labelText: '설명 (선택)',
                          counterText: '',
                        ),
                        maxLines: 2,
                        maxLength: 200,
                      ),
                      const SizedBox(height: 12),
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
                        subtitle: Text(
                          _isAllDay ? _fmtDateOnly(_startsAt) : _fmtDate(_startsAt),
                        ),
                        onTap: () => _pickDateTime(true),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_outlined),
                        title: const Text('종료'),
                        subtitle: Text(
                          _isAllDay ? _fmtDateOnly(_endsAt) : _fmtDate(_endsAt),
                        ),
                        onTap: () => _pickDateTime(false),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('색상', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('색상 선택'),
                                content: BlockPicker(
                                  pickerColor: _color,
                                  onColorChanged: (c) => setState(() => _color = c),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('확인'),
                                  ),
                                ],
                              ),
                            ),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: _color,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

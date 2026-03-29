import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/event.dart';
import '../models/group.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/group_service.dart';
import '../widgets/event_form_sheet.dart';
import '../widgets/event_detail_sheet.dart';
import '../widgets/group_info_sheet.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<Group> _groups = [];
  Set<String> _visibleGroupIds = {};
  List<CalendarEvent> _events = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _nickname;
  bool _loadingGroups = true;
  bool _loadingEvents = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _loadAll();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userId = AuthService.currentUser!.id;
    final p = await Supabase.instance.client
        .from('profiles')
        .select('nickname')
        .eq('id', userId)
        .single();
    if (mounted) setState(() => _nickname = p['nickname'] as String?);
  }

  Future<void> _loadAll() async {
    await _loadGroups();
    await _loadEvents();
  }

  Future<void> _loadGroups() async {
    final groups = await GroupService.fetchMyGroups(AuthService.currentUser!.id);
    if (mounted) {
      setState(() {
        _groups = groups;
        _visibleGroupIds = groups.map((g) => g.id).toSet();
        _loadingGroups = false;
      });
    }
  }

  Future<void> _loadEvents() async {
    setState(() => _loadingEvents = true);
    final events = await EventService.fetchEvents(
        AuthService.currentUser!.id, _visibleGroupIds.toList());
    if (mounted) setState(() { _events = events; _loadingEvents = false; });
  }

  List<CalendarEvent> _eventsForDay(DateTime day) {
    return _events.where((e) {
      final start = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
      final end = DateTime(e.endsAt.year, e.endsAt.month, e.endsAt.day);
      final d = DateTime(day.year, day.month, day.day);
      return !d.isBefore(start) && !d.isAfter(end);
    }).toList();
  }

  void _openEventForm({DateTime? date, CalendarEvent? editEvent}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventFormSheet(
        defaultDate: date,
        editEvent: editEvent,
        groups: _groups,
        onSave: ({required title, description, required startsAt, required endsAt, required isAllDay, required color, required groupIds}) async {
          final userId = AuthService.currentUser!.id;
          if (editEvent != null) {
            await EventService.updateEvent(
              eventId: editEvent.id, userId: userId,
              title: title, description: description,
              startsAt: startsAt, endsAt: endsAt,
              isAllDay: isAllDay, color: color, groupIds: groupIds,
            );
          } else {
            await EventService.createEvent(
              userId: userId, title: title, description: description,
              startsAt: startsAt, endsAt: endsAt,
              isAllDay: isAllDay, color: color, groupIds: groupIds,
            );
          }
          await _loadEvents();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(editEvent != null ? '일정이 수정되었습니다.' : '일정이 저장되었습니다!')));
          }
        },
      ),
    );
  }

  void _openEventDetail(CalendarEvent event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventDetailSheet(
        event: event,
        groups: _groups,
        currentUserId: AuthService.currentUser!.id,
        onEdit: () {
          Navigator.pop(context);
          _openEventForm(editEvent: event);
        },
        onDelete: () async {
          Navigator.pop(context);
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('일정 삭제'),
              content: Text('\'${event.title}\' 일정을 삭제하시겠습니까?'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('삭제'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await EventService.deleteEvent(event.id, AuthService.currentUser!.id);
            await _loadEvents();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('일정이 삭제되었습니다.')));
          }
        },
      ),
    );
  }

  void _openGroupInfo(Group group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupInfoSheet(
        group: group,
        onLeave: (gid) async {
          await GroupService.leaveGroup(gid, AuthService.currentUser!.id);
          await _loadAll();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('그룹에서 탈퇴했습니다.')));
        },
        onDelete: (gid) async {
          await GroupService.deleteGroup(gid, AuthService.currentUser!.id);
          await _loadAll();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('그룹이 삭제되었습니다.')));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedEvents = _selectedDay != null ? _eventsForDay(_selectedDay!) : <CalendarEvent>[];
    final avatarLetter = (_nickname ?? '?')[0].toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('TeamSync', style: TextStyle(fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            tooltip: '로그아웃',
            onPressed: () async {
              await AuthService.signOut();
              if (mounted) context.go('/login');
            },
          ),
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(avatarLetter, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Column(children: [
        // 캘린더
        TableCalendar<CalendarEvent>(
          locale: 'ko_KR',
          firstDay: DateTime(2020),
          lastDay: DateTime(2030),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          eventLoader: _eventsForDay,
          calendarStyle: CalendarStyle(
            markerDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            todayDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
          ),
          headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              if (events.isEmpty) return null;
              return Positioned(
                bottom: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: events.take(3).map((e) => Container(
                    width: 6, height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: e.flutterColor,
                      shape: BoxShape.circle,
                    ),
                  )).toList(),
                ),
              );
            },
          ),
          onDaySelected: (selected, focused) {
            setState(() { _selectedDay = selected; _focusedDay = focused; });
          },
          onPageChanged: (focused) => setState(() => _focusedDay = focused),
        ),

        const Divider(height: 1),

        // 선택된 날짜 이벤트 목록
        Expanded(
          child: _loadingEvents
              ? const Center(child: CircularProgressIndicator())
              : selectedEvents.isEmpty
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.event_note, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          _selectedDay != null
                              ? '${DateFormat('M월 d일').format(_selectedDay!)} 일정이 없습니다.'
                              : '날짜를 선택하세요.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ]),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: selectedEvents.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final ev = selectedEvents[i];
                        return Card(
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            leading: Container(
                              width: 4, height: 40,
                              decoration: BoxDecoration(
                                color: ev.flutterColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            title: Text(ev.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (ev.creatorNickname != null)
                                Text(ev.creatorNickname!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              Text(
                                ev.isAllDay ? '하루 종일' : DateFormat('HH:mm').format(ev.startsAt),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ]),
                            onTap: () => _openEventDetail(ev),
                          ),
                        );
                      },
                    ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEventForm(date: _selectedDay),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('내 그룹', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16,
                  color: Theme.of(context).colorScheme.primary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '그룹 생성',
                onPressed: () { Navigator.pop(context); context.push('/groups/create'); },
              ),
            ]),
          ),
          const Divider(height: 1),

          if (_loadingGroups)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text('속한 그룹이 없습니다.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () { Navigator.pop(context); context.push('/groups/join'); },
                  icon: const Icon(Icons.group_add),
                  label: const Text('그룹 가입하기'),
                ),
              ]),
            )
          else ...[
            // 전체 체크박스
            CheckboxListTile(
              title: const Text('전체', style: TextStyle(fontWeight: FontWeight.w600)),
              value: _visibleGroupIds.length == _groups.length
                  ? true
                  : _visibleGroupIds.isEmpty
                      ? false
                      : null,
              tristate: true,
              onChanged: (_) {
                setState(() {
                  if (_visibleGroupIds.length == _groups.length) {
                    _visibleGroupIds.clear();
                  } else {
                    _visibleGroupIds = _groups.map((g) => g.id).toSet();
                  }
                });
                _loadEvents();
              },
            ),
            const Divider(height: 1),
            ..._groups.map((g) => ListTile(
                  leading: Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(color: g.flutterColor, shape: BoxShape.circle),
                  ),
                  title: Text(g.name, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(
                      value: _visibleGroupIds.contains(g.id),
                      activeColor: g.flutterColor,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) _visibleGroupIds.add(g.id);
                          else _visibleGroupIds.remove(g.id);
                        });
                        _loadEvents();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline, size: 18),
                      onPressed: () { Navigator.pop(context); _openGroupInfo(g); },
                    ),
                  ]),
                )),
          ],

          const Spacer(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.group_add),
            title: const Text('그룹 가입'),
            onTap: () { Navigator.pop(context); context.push('/groups/join'); },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('프로필 설정'),
            onTap: () { Navigator.pop(context); context.push('/profile'); },
          ),
        ]),
      ),
    );
  }
}

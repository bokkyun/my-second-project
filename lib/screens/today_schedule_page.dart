import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../models/group.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../widgets/event_detail_sheet.dart';
import '../widgets/event_form_sheet.dart';

/// 매일 요약 알림 탭 시 · 그룹 목록형 + 시간순 타임라인(참고 UI)으로 오늘(또는 선택일) 일정 표시
class TodaySchedulePage extends StatefulWidget {
  const TodaySchedulePage({super.key});

  @override
  State<TodaySchedulePage> createState() => _TodaySchedulePageState();
}

class _TodaySchedulePageState extends State<TodaySchedulePage> {
  List<Group> _groups = [];
  List<CalendarEvent> _events = [];
  bool _loading = true;
  late DateTime _viewDay;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _viewDay = DateTime(n.year, n.month, n.day);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = AuthService.currentUser!.id;
      final groups = await GroupService.fetchMyGroups(uid);
      final visible = groups.map((g) => g.id).toList();
      final events = await EventService.fetchEvents(uid, visible);
      if (mounted) {
        setState(() {
          _groups = groups;
          _events = events;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CalendarEvent> _eventsForDay(DateTime day) {
    return NotificationService.eventsForCalendarDay(_events, day);
  }

  String _groupLabel(CalendarEvent ev) {
    for (final gid in ev.groupIds) {
      final g = _groups.where((x) => x.id == gid).firstOrNull;
      if (g != null) return g.name;
    }
    return '내 일정';
  }

  bool _isAdminOfEvent(CalendarEvent event) {
    if (event.creatorId == AuthService.currentUser!.id) return false;
    return event.groupIds.any(
      (gid) => _groups.any((g) => g.id == gid && g.myRole == 'admin'),
    );
  }

  Color _groupColor(CalendarEvent ev) {
    for (final gid in ev.groupIds) {
      final g = _groups.where((x) => x.id == gid).firstOrNull;
      if (g != null) return g.flutterColor;
    }
    return ev.flutterColor;
  }

  void _shiftDay(int delta) {
    setState(() {
      _viewDay = _viewDay.add(Duration(days: delta));
    });
  }

  void _openDetail(CalendarEvent ev) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EventDetailSheet(
        event: ev,
        groups: _groups,
        currentUserId: AuthService.currentUser!.id,
        onEdit: () {
          Navigator.pop(ctx);
          _openEditForm(ev);
        },
        onDelete: () async {
          Navigator.pop(ctx);
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('일정 삭제'),
              content: Text('\'${ev.title}\' 일정을 삭제하시겠습니까?'),
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
          if (ok == true && mounted) {
            await EventService.deleteEvent(
              ev.id,
              AuthService.currentUser!.id,
              isAdminOverride: _isAdminOfEvent(ev),
            );
            await _load();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('일정이 삭제되었습니다.')),
              );
            }
          }
        },
      ),
    );
  }

  void _openEditForm(CalendarEvent editEvent) {
    final adminGroupIds = _groups
        .where((g) => g.myRole == 'admin')
        .map((g) => g.id)
        .toSet();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventFormSheet(
        editEvent: editEvent,
        groups: _groups,
        adminGroupIds: adminGroupIds,
        onFetchMembers: null,
        onSave: ({
          required title,
          description,
          required startsAt,
          required endsAt,
          required isAllDay,
          required color,
          required groupIds,
          String? targetUserId,
          required eventKind,
        }) async {
          await EventService.updateEvent(
            eventId: editEvent.id,
            userId: AuthService.currentUser!.id,
            title: title,
            description: description,
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: isAllDay,
            color: color,
            groupIds: groupIds,
            isAdminOverride: _isAdminOfEvent(editEvent),
            eventKind: eventKind,
          );
          await _load();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('일정이 수정되었습니다.')),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = _eventsForDay(_viewDay);
    final sorted = List<CalendarEvent>.from(dayEvents)
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final dateFmt = DateFormat('M월 d일 (E)', 'ko_KR');
    final prevD = _viewDay.subtract(const Duration(days: 1));
    final nextD = _viewDay.add(const Duration(days: 1));

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('하루 일정'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/calendar');
            }
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // 날짜 네비 (참고 UI 2번 — 가로 날짜 선택)
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => _shiftDay(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Center(
                          child: FilledButton.tonal(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _viewDay,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (d != null) {
                                setState(() {
                                  _viewDay = DateTime(d.year, d.month, d.day);
                                });
                              }
                            },
                            child: Text(
                              dateFmt.format(_viewDay),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _shiftDay(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          final n = DateTime.now();
                          _viewDay = DateTime(n.year, n.month, n.day);
                        }),
                        child: const Text('오늘'),
                      ),
                      Text(
                        '${DateFormat('M월 d일', 'ko_KR').format(prevD)} · ${DateFormat('M월 d일', 'ko_KR').format(nextD)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 참고 UI 3번 — 그룹 목록형 리스트
                  Row(
                    children: [
                      Icon(Icons.groups, color: Theme.of(context).colorScheme.primary, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        '오늘의 일정',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (sorted.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '이 날짜에 등록된 일정이 없습니다.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: sorted.asMap().entries.map((e) {
                          final ev = e.value;
                          final isLast = e.key == sorted.length - 1;
                          final timeStr = ev.isAllDay
                              ? '종일'
                              : DateFormat('HH:mm').format(ev.startsAt);
                          final gColor = _groupColor(ev);
                          return InkWell(
                            onTap: () => _openDetail(ev),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Checkbox(
                                        value: true,
                                        onChanged: null,
                                        activeColor: gColor,
                                      ),
                                      Container(
                                        width: 10,
                                        height: 10,
                                        margin: const EdgeInsets.only(top: 10),
                                        decoration: BoxDecoration(
                                          color: gColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              ev.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${_groupLabel(ev)} · $timeStr'
                                              '${ev.isGroupEvent ? ' · 그룹 이벤트' : ''}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        timeStr,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade800,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right,
                                        color: Colors.grey.shade400,
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isLast) Divider(height: 1, color: Colors.grey.shade200),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // 참고 UI 2번 — 시간축 카드
                  Row(
                    children: [
                      Icon(Icons.schedule, color: Theme.of(context).colorScheme.secondary, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        '시간순',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (sorted.isEmpty)
                    const SizedBox.shrink()
                  else
                    ...sorted.map((ev) {
                      final start = ev.isAllDay
                          ? '종일'
                          : DateFormat('HH:mm').format(ev.startsAt);
                      final end = ev.isAllDay
                          ? ''
                          : ' – ${DateFormat('HH:mm').format(ev.endsAt)}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 56,
                              child: Text(
                                '$start$end',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border(
                                    left: BorderSide(
                                      color: _groupColor(ev),
                                      width: 4,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          ev.isGroupEvent ? Icons.groups : Icons.event,
                                          size: 18,
                                          color: _groupColor(ev),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            ev.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (ev.description != null &&
                                        ev.description!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        ev.description!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final i = iterator;
    return i.moveNext() ? i.current : null;
  }
}

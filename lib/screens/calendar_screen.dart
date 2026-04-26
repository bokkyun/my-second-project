import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/event.dart';
import '../utils/reb_apt_sply_api.dart';
import '../models/subway_display_row.dart';
import '../models/group.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../services/push_messaging_service.dart';
import '../services/subway_arrival_service.dart';
import '../services/subway_prefs.dart';
import '../services/widget_sync_service.dart';
import '../widgets/event_form_sheet.dart';
import '../widgets/event_detail_sheet.dart';
import '../widgets/group_event_form_sheet.dart';
import '../widgets/group_info_sheet.dart';
import '../widgets/daily_reminder_settings_panel.dart';
import '../widgets/subway_commute_settings_panel.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    this.initialOpenEventId,
  });

  /// ?? ??? ?????? ???????? ????? ??? ????
  final String? initialOpenEventId;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  List<Group> _groups = [];
  Set<String> _visibleGroupIds = {};
  bool _onlyMySchedules = false;
  List<CalendarEvent> _events = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _nickname;
  bool _loadingGroups = true;
  bool _loadingEvents = true;
  String? _pendingEventId;

  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounce;
  Timer? _pollTimer;
  List<SubwayDisplayRow> _subwayRows = [];
  String _subwayHint = '지하철 설정에서 역을 저장해 주세요.';
  bool _loadingSubwaySummary = false;

  /// 한국부동산원 청약홈(공공데이터) — 드로어에서 끄면 요청 없음
  bool _showRebAptSply = true;
  List<CalendarEvent> _rebAptEvents = [];
  bool _rebAptLoading = false;
  String? _rebAptError;
  String? _appVersionLabel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedDay = DateTime.now();
    _pendingEventId = widget.initialOpenEventId;
    _loadAll();
    unawaited(_loadRebAptPref());
    unawaited(_loadAppVersion());
    _loadProfile();
    _refreshSubwaySummary();
    _subscribeCalendarRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (mounted) unawaited(_refreshEventsQuietly());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeDebounce?.cancel();
    _pollTimer?.cancel();
    _unsubscribeCalendarRealtime();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshEventsQuietly());
      unawaited(_refreshSubwaySummary());
    }
  }

  void _subscribeCalendarRealtime() {
    final uid = AuthService.currentUser?.id;
    if (uid == null) return;
    try {
      _unsubscribeCalendarRealtime();
      final client = Supabase.instance.client;
      _realtimeChannel = client
          .channel('calendar-sync-$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'events',
            callback: (_) => _debouncedEventsRefresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'event_visibility',
            callback: (_) => _debouncedEventsRefresh(),
          );
      _realtimeChannel!.subscribe();
    } catch (e) {
      debugPrint('[CalendarScreen] Realtime subscription failed: $e');
    }
  }

  void _unsubscribeCalendarRealtime() {
    final ch = _realtimeChannel;
    _realtimeChannel = null;
    if (ch != null) {
      try {
        unawaited(Supabase.instance.client.removeChannel(ch));
      } catch (_) {}
    }
  }

  void _debouncedEventsRefresh() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_refreshEventsQuietly());
    });
  }

  /// ????? ?????? ???? ???? ???? (Realtime??????? ???)
  Future<void> _refreshEventsQuietly() async {
    if (!mounted) return;
    try {
      final events = await EventService.fetchEvents(
        AuthService.currentUser!.id, _visibleGroupIds.toList());
      if (!mounted) return;
      setState(() => _events = events);
      try {
        await NotificationService.scheduleTodayEvents(events);
      } catch (e) {
        debugPrint('[CalendarScreen] notification schedule error: $e');
      }
      try {
        await WidgetSyncService.syncTodayEvents(events);
      } catch (e) {
        debugPrint('[CalendarScreen] widget sync error: $e');
      }
      unawaited(_refreshSubwaySummary());
    } catch (e) {
      debugPrint('[CalendarScreen] _refreshEventsQuietly error: $e');
    }
  }

  Future<void> _loadProfile() async {
    final user = AuthService.currentUser;
    if (user == null) return;
    try {
      final p = await Supabase.instance.client
          .from('profiles')
          .select('nickname')
          .eq('id', user.id)
          .maybeSingle();
      if (mounted) setState(() => _nickname = p?['nickname'] as String?);
    } catch (_) {
      if (mounted) setState(() => _nickname = null);
    }
  }

  Future<void> _loadAll() async {
    await _loadGroups();
    await _loadEvents();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await GroupService.fetchMyGroups(AuthService.currentUser!.id);
      if (mounted) {
        setState(() {
          _groups = groups;
          _visibleGroupIds = groups.map((g) => g.id).toSet();
          _loadingGroups = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _groups = [];
          _loadingGroups = false;
        });
      }
    }
  }

  Future<void> _loadEvents() async {
    setState(() => _loadingEvents = true);
    try {
      final events = await EventService.fetchEvents(
          AuthService.currentUser!.id, _visibleGroupIds.toList());
      if (mounted) {
        setState(() {
          _events = events;
          _loadingEvents = false;
        });
        try {
          await NotificationService.scheduleTodayEvents(events);
        } catch (e) {
          debugPrint('[CalendarScreen] notification schedule error: $e');
        }
        try {
          await WidgetSyncService.syncTodayEvents(events);
        } catch (e) {
          debugPrint('[CalendarScreen] widget sync error: $e');
        }
        unawaited(_refreshSubwaySummary());
        await _runPendingNotificationActions();
      }
    } catch (e) {
      debugPrint('[CalendarScreen] _loadEvents error: $e');
      if (mounted) {
        setState(() {
          _events = [];
          _loadingEvents = false;
        });
        try { await WidgetSyncService.syncTodayEvents([]); } catch (_) {}
        try { await NotificationService.scheduleDailySummaryFromPrefs([]); } catch (_) {}
        await _runPendingNotificationActions();
      }
    }
  }

  /// ???? ?????: ????? ????? ??? ?????? ??????
  Future<void> _runPendingNotificationActions() async {
    if (!mounted) return;

    final eventId = _pendingEventId;
    if (eventId != null) {
      _pendingEventId = null;
      CalendarEvent? ev;
      for (final e in _allVisibleEvents) {
        if (e.id == eventId) {
          ev = e;
          break;
        }
      }
      if (ev == null &&
          !eventId.startsWith('reb-apt-') &&
          !eventId.startsWith('reb-od-')) {
        ev = await EventService.fetchEventById(eventId);
      }
      if (!mounted) return;
      context.go('/calendar');
      final toShow = ev;
      if (toShow != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openEventDetail(toShow);
          }
        });
      }
    }
  }

  List<CalendarEvent> _eventsForDay(DateTime day) {
    final uid = AuthService.currentUser?.id;
    Iterable<CalendarEvent> list = _allVisibleEvents;
    if (_onlyMySchedules && uid != null) {
      list = list.where((e) => e.creatorId == uid && !e.isExternal);
    }
    return list.where((e) {
      final start = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
      final end = DateTime(e.endsAt.year, e.endsAt.month, e.endsAt.day);
      final d = DateTime(day.year, day.month, day.day);
      return !d.isBefore(start) && !d.isAfter(end);
    }).toList();
  }

  /// ???????? ?????? ?????? ??????? ?? ????????? ????
  bool _isAdminOfEvent(CalendarEvent event) {
    if (event.creatorId == AuthService.currentUser!.id) return false;
    return event.groupIds.any(
      (gid) => _groups.any((g) => g.id == gid && g.myRole == 'admin'),
    );
  }

  void _openReminderSettings() {
    showDailyReminderSettingsSheet(context);
  }

  void _openSubwaySettings() {
    showSubwayCommuteSettingsSheet(context).then((_) {
      if (mounted) {
        unawaited(_refreshSubwaySummary());
      }
    });
  }

  Future<void> _loadRebAptPref() async {
    try {
      final p = await SharedPreferences.getInstance();
      final on = p.getBool('calendar_show_reb_apt') ?? true;
      if (mounted) setState(() => _showRebAptSply = on);
      if (on) await _fetchRebAptEvents();
    } catch (e) {
      debugPrint('[CalendarScreen] _loadRebAptPref: $e');
    }
  }

  /// pubspec `version`이 앱 설정(Android versionName / versionCode 등)에 반영된 값
  Future<void> _loadAppVersion() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersionLabel = 'v${p.version} (빌드 ${p.buildNumber})';
        });
      }
    } catch (e) {
      debugPrint('[CalendarScreen] _loadAppVersion: $e');
    }
  }

  Future<void> _fetchRebAptEvents() async {
    if (!_showRebAptSply) {
      if (mounted) {
        setState(() {
          _rebAptEvents = [];
          _rebAptError = null;
          _rebAptLoading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _rebAptLoading = true;
        _rebAptError = null;
      });
    }
    final r = await fetchRebAptSplyList();
    if (!mounted) return;
    setState(() {
      _rebAptLoading = false;
      _rebAptEvents = r.events;
      _rebAptError = r.error;
    });
  }

  Future<void> _setShowRebAptSply(bool value) async {
    setState(() => _showRebAptSply = value);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('calendar_show_reb_apt', value);
    } catch (_) {}
    await _fetchRebAptEvents();
  }

  /// Supabase + (옵션) 청약홈 외부 일정
  List<CalendarEvent> get _allVisibleEvents {
    if (!_showRebAptSply) return _events;
    return [..._events, ..._rebAptEvents];
  }

  Future<void> _refreshSubwaySummary() async {
    if (_loadingSubwaySummary) return;
    setState(() => _loadingSubwaySummary = true);
    try {
      await WidgetSyncService.syncSubwayOnly();
      final config = await SubwayPrefs.load();
      if (!mounted) return;
      if (!config.hasAny) {
        setState(() {
          _subwayRows = [];
          _subwayHint = '지하철 설정에서 역을 저장해 주세요.';
        });
        return;
      }
      final rows = await SubwayArrivalService.buildDisplayRows(config);
      if (mounted) {
        setState(() {
          _subwayRows = rows;
          _subwayHint = '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _subwayRows = [];
          _subwayHint = '도착 정보를 불러오지 못했습니다.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loadingSubwaySummary = false);
      }
    }
  }

  Widget _buildSubwayPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loadingSubwaySummary) {
      return Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '도착 정보 불러오는 중…',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      );
    }
    if (_subwayRows.isEmpty) {
      return Text(
        _subwayHint,
        style: TextStyle(fontSize: 12, height: 1.2, color: scheme.onSurfaceVariant),
      );
    }
    final maxH = math.min(220.0, MediaQuery.sizeOf(context).height * 0.24);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _subwayRows.map((r) => _buildSubwayRowTile(context, r)).toList(),
        ),
      ),
    );
  }

  Widget _buildSubwayRowTile(BuildContext context, SubwayDisplayRow r) {
    final scheme = Theme.of(context).colorScheme;
    if (r.isSection) {
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Text(
          r.sectionLabel ?? '',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            height: 1.15,
            color: scheme.primary,
          ),
        ),
      );
    }
    final accent = r.accentColor(scheme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 2,
            height: 14,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: scheme.onSurface,
                ),
                children: [
                  TextSpan(
                    text: '${r.station} ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '${r.terminal} ',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: r.eta,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.event, color: Theme.of(context).colorScheme.primary),
              title: const Text('일정 추가'),
              subtitle: const Text('나만 또는 선택한 그룹에 공유'),
              onTap: () {
                Navigator.pop(ctx);
                _openEventForm(date: _selectedDay);
              },
            ),
            ListTile(
              leading: Icon(Icons.groups, color: Theme.of(context).colorScheme.secondary),
              title: const Text('그룹 이벤트 만들기'),
              subtitle: const Text('선택한 그룹의 모든 구성원 캘린더에 등록 · 푸시 알림'),
              onTap: () {
                Navigator.pop(ctx);
                _openGroupEventForm();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openGroupEventForm() {
    if (_groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 그룹에 참여해 주세요.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupEventFormSheet(
        groups: _groups,
        defaultDate: _selectedDay,
      ),
    ).then((_) {
      if (mounted) {
        _loadEvents();
      }
    });
  }

  void _openEventForm({DateTime? date, CalendarEvent? editEvent}) {
    final adminGroupIds = _groups
        .where((g) => g.myRole == 'admin')
        .map((g) => g.id)
        .toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventFormSheet(
        defaultDate: date,
        editEvent: editEvent,
        groups: _groups,
        adminGroupIds: editEvent == null ? adminGroupIds : const {},
        onFetchMembers: editEvent == null ? GroupService.fetchGroupMembers : null,
        onSave: ({required title, description, required startsAt, required endsAt, required isAllDay, required color, required groupIds, String? targetUserId, required eventKind}) async {
          final currentUserId = AuthService.currentUser!.id;
          if (editEvent != null) {
            await EventService.updateEvent(
              eventId: editEvent.id, userId: currentUserId,
              title: title, description: description,
              startsAt: startsAt, endsAt: endsAt,
              isAllDay: isAllDay, color: color, groupIds: groupIds,
              isAdminOverride: _isAdminOfEvent(editEvent),
              eventKind: eventKind,
            );
          } else {
            final creatorId = targetUserId ?? currentUserId;
            await EventService.createEvent(
              userId: creatorId, title: title, description: description,
              startsAt: startsAt, endsAt: endsAt,
              isAllDay: isAllDay, color: color, groupIds: groupIds,
              eventKind: eventKind,
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
            await EventService.deleteEvent(
              event.id, AuthService.currentUser!.id,
              isAdminOverride: _isAdminOfEvent(event),
            );
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
        onChangeAdmin: (gid, newAdminUserId) async {
          await GroupService.changeGroupAdmin(gid, newAdminUserId, AuthService.currentUser!.id);
          await _loadAll();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('관리자가 변경되었습니다.')));
        },
        onChangePassword: (gid, newPassword) async {
          await GroupService.changeGroupPassword(gid, AuthService.currentUser!.id, newPassword);
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
              await PushMessagingService.clearTokenForLogout();
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
        // ?????
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

        // ???????? ????? ????? ??
        Expanded(
          child: _loadingEvents
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadEvents();
                    if (_showRebAptSply) await _fetchRebAptEvents();
                  },
                  child: selectedEvents.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.25,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.event_note, size: 48, color: Colors.grey),
                                    const SizedBox(height: 8),
                                    Text(
                                      _selectedDay != null
                                          ? '${DateFormat('M월 d일').format(_selectedDay!)} 일정이 없습니다.'
                                          : '날짜를 선택해주세요.',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '아래로 당겨서 새로고침',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          itemCount: selectedEvents.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
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
        ),
        const Divider(height: 1),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 6, 72, 6),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.directions_subway,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildSubwayPanel(context)),
            ],
          ),
        ),
      ]),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'calendar_subway_settings',
            tooltip: '출퇴근 지하철 설정',
            onPressed: _openSubwaySettings,
            child: const Icon(Icons.directions_subway),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.small(
            heroTag: 'calendar_reminder_settings',
            tooltip: '오늘 일정 요약 알림 설정',
            onPressed: _openReminderSettings,
            child: const Icon(Icons.settings),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'calendar_add_menu',
            tooltip: '일정 · 그룹 이벤트',
            onPressed: _showAddMenu,
            child: const Icon(Icons.add),
          ),
        ],
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                const Text('속한 그룹이 없습니다.', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/groups/create');
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('새 그룹 만들기'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () { Navigator.pop(context); context.push('/groups/join'); },
                  icon: const Icon(Icons.group_add),
                  label: const Text('그룹 가입하기'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('내 일정만', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('내가 등록한 일정만 캘린더에 표시', style: TextStyle(fontSize: 12)),
                  value: _onlyMySchedules,
                  onChanged: (v) {
                    setState(() => _onlyMySchedules = v ?? false);
                  },
                ),
              ]),
            )
          else ...[
            // ??? ???????
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
            CheckboxListTile(
              title: const Text('내 일정만', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('내가 등록한 일정만 캘린더에 표시', style: TextStyle(fontSize: 12)),
              value: _onlyMySchedules,
              onChanged: (v) {
                setState(() => _onlyMySchedules = v ?? false);
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

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              '정보',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          CheckboxListTile(
            title: const Text('아파트 청약·분양', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              _rebAptLoading
                  ? '불러오는 중…'
                  : (_rebAptError ?? '한국부동산원 청약홈(공공데이터) — 키는 --dart-define=DATA_GO_KR_SERVICE_KEY'),
              style: TextStyle(
                fontSize: 12,
                color: _rebAptError != null && _showRebAptSply ? Theme.of(context).colorScheme.error : null,
              ),
            ),
            value: _showRebAptSply,
            onChanged: (v) {
              unawaited(_setShowRebAptSply(v ?? false));
            },
            secondary: _rebAptLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.apartment_outlined),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          CheckboxListTile(
            title: const Text('공모주 (준비 중)', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('추가 예정', style: TextStyle(fontSize: 12)),
            value: false,
            onChanged: null,
            secondary: const Icon(Icons.show_chart, color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.primary),
            title: const Text('새 그룹 만들기'),
            onTap: () { Navigator.pop(context); context.push('/groups/create'); },
          ),
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
          if (_appVersionLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _appVersionLabel!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}


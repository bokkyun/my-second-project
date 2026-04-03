import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../models/event.dart';
import 'reminder_prefs.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'teamsync_schedule';
  static const _channelName = '스케줄 알림';
  static const _channelDesc = '오늘의 스케줄을 알려드립니다.';

  static const _promptChannelId = 'teamsync_daily_summary';
  static const _promptChannelName = '오늘 일정 요약';
  static const _promptChannelDesc = '설정한 시간에 오늘 일정 요약을 알려줍니다.';

  static const _groupChannelId = 'teamsync_group_push';
  static const _groupChannelName = '그룹 일정 알림';

  /// 일정별 알림 (시작 시각 등)
  static const _eventIdBase = 10000;
  static const _maxEventNotificationSlots = 500;

  /// 매일 요약 (고정 ID)
  static const _dailySummaryNotificationId = 999998;

  /// 그룹 푸시 포그라운드 표시 (고정 ID)
  static const _groupForegroundNotificationId = 999997;

  /// [zonedSchedule] payload — 탭 시 오늘 일정 상세
  static const payloadDailySummary = 'daily_summary';

  static const payloadGroupEventPrefix = 'group_event:';

  static GoRouter? _router;

  static void attachRouter(GoRouter router) {
    _router = router;
  }

  static Future<void> initialize() async {
    tz_data.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final p = response.payload;
    if (p == null || p.isEmpty) return;
    if (p == payloadDailySummary) {
      _router?.go('/today-schedule');
      return;
    }
    if (p.startsWith(payloadGroupEventPrefix)) {
      final id = p.substring(payloadGroupEventPrefix.length);
      if (id.isNotEmpty) {
        _router?.go('/calendar?eventId=$id');
      }
    }
  }

  static Future<void> handleNotificationAppLaunch() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return;
    final p = details!.notificationResponse?.payload;
    if (p == null || p.isEmpty) return;
    if (p == payloadDailySummary) {
      _router?.go('/today-schedule');
      return;
    }
    if (p.startsWith(payloadGroupEventPrefix)) {
      final id = p.substring(payloadGroupEventPrefix.length);
      if (id.isNotEmpty) {
        _router?.go('/calendar?eventId=$id');
      }
    }
  }

  /// 오늘 하루에 걸쳐 있는 일정만 필터 (자정 기준)
  static List<CalendarEvent> eventsForCalendarDay(
      List<CalendarEvent> events, DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return events.where((e) {
      final start = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
      final end = DateTime(e.endsAt.year, e.endsAt.month, e.endsAt.day);
      return !d.isBefore(start) && !d.isAfter(end);
    }).toList();
  }

  static String _buildDailySummaryTitle(int count) {
    return 'TeamSync · 오늘 일정 $count건';
  }

  static String _buildDailySummaryBody(List<CalendarEvent> todayEvents) {
    if (todayEvents.isEmpty) {
      return '등록된 일정이 없습니다. 탭하면 캘린더에서 확인할 수 있어요.';
    }
    final sorted = List<CalendarEvent>.from(todayEvents)
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final parts = <String>[];
    final fmt = DateFormat('HH:mm');
    for (final e in sorted.take(6)) {
      final t = e.isAllDay ? '종일' : fmt.format(e.startsAt);
      parts.add('$t ${e.title}');
    }
    var s = parts.join(' · ');
    if (sorted.length > 6) {
      s += ' 외 ${sorted.length - 6}건';
    }
    if (s.length > 220) {
      s = '${s.substring(0, 217)}…';
    }
    return s;
  }

  /// [todayEvents]는 오늘 포함 일정 목록(캘린더와 동일 필터). 비어 있으면 «일정 없음» 요약.
  static Future<void> scheduleDailySummaryFromPrefs(
      List<CalendarEvent> todayEvents) async {
    await _plugin.cancel(_dailySummaryNotificationId);

    final enabled = await ReminderPrefs.isDailyReminderEnabled();
    if (!enabled) return;

    final time = await ReminderPrefs.dailyReminderTime();
    final localTz = tz.local;
    final scheduled = _nextInstanceOfTime(time.hour, time.minute, localTz);

    final title = _buildDailySummaryTitle(todayEvents.length);
    final body = _buildDailySummaryBody(todayEvents);

    await _plugin.zonedSchedule(
      _dailySummaryNotificationId,
      title,
      body,
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _promptChannelId,
          _promptChannelName,
          channelDescription: _promptChannelDesc,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          styleInformation: BigTextStyleInformation(body),
          category: AndroidNotificationCategory.event,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          subtitle: '오늘 일정 요약',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payloadDailySummary,
    );
  }

  static tz.TZDateTime _nextInstanceOfTime(
      int hour, int minute, tz.Location location) {
    final now = tz.TZDateTime.now(location);
    var scheduled = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// 포그라운드에서 FCM과 유사하게 표시 (탭 시 일정 상세)
  static Future<void> showGroupEventLocalNotification({
    required String title,
    required String body,
    required String eventId,
  }) async {
    await _plugin.show(
      _groupForegroundNotificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _groupChannelId,
          _groupChannelName,
          channelDescription: '그룹원이 등록한 일정',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: '$payloadGroupEventPrefix$eventId',
    );
  }

  /// 오늘 일정에 대한 시각 알림 + 매일 요약 예약
  static Future<void> scheduleTodayEvents(List<CalendarEvent> events) async {
    for (var i = 0; i < _maxEventNotificationSlots; i++) {
      await _plugin.cancel(_eventIdBase + i);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final localTz = tz.local;

    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      if (i >= _maxEventNotificationSlots) break;

      final eventDay = DateTime(
        event.startsAt.year,
        event.startsAt.month,
        event.startsAt.day,
      );

      if (eventDay != today) continue;

      DateTime notifyAt;
      String body;

      if (event.isAllDay) {
        notifyAt = DateTime(today.year, today.month, today.day, 8, 0);
        body = '오늘 하루 종일 일정이 있습니다.';
      } else {
        notifyAt = event.startsAt;
        final h = event.startsAt.hour.toString().padLeft(2, '0');
        final m = event.startsAt.minute.toString().padLeft(2, '0');
        body = '$h:$m 일정이 시작됩니다.';
      }

      if (notifyAt.isBefore(now)) continue;

      await _plugin.zonedSchedule(
        _eventIdBase + i,
        event.title,
        body,
        tz.TZDateTime.from(notifyAt, localTz),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            color: event.flutterColor,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    final todaySlice = eventsForCalendarDay(events, now);
    await scheduleDailySummaryFromPrefs(todaySlice);
  }
}

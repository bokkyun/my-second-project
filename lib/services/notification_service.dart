import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
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

  /// 매일 요약 — 구버전 단일 예약 ID (마이그레이션 시 취소)
  static const _dailySummaryNotificationIdLegacy = 999998;

  /// 요일별 주간 반복 예약 ID (weekday `DateTime.weekday` 1=월 … 7=일).
  /// 999981~999987 사용 (999997 그룹 포그라운드 ID와 겹치지 않음)
  static int _dailySummaryIdForWeekday(int weekday) => 999980 + weekday;

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
    await _configureLocalTimeZone();

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

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    // Android 12+ 정확한 알람 — 거부 시 예약이 실패하거나 지연될 수 있음
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await androidImpl?.requestExactAlarmsPermission();
    }
  }

  /// 기기 로컬 시간대를 `tz.local`에 맞춤. 미설정 시 UTC 기준으로 예약되어 알림 시각이 어긋남.
  /// Android 12+ 에서 정확한 알람 권한이 없으면 네이티브가 예약 시 예외를 던져 알림이 전혀 잡히지 않음.
  /// 이 경우 [AndroidScheduleMode.inexactAllowWhileIdle] 로 대체한다.
  static Future<AndroidScheduleMode> _androidScheduleModeForAlarms() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canExact = await android?.canScheduleExactNotifications();
    if (canExact == false) {
      debugPrint(
        'NotificationService: 정확한 알람 권한 없음 → inexactAllowWhileIdle 로 예약',
      );
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
    return AndroidScheduleMode.exactAllowWhileIdle;
  }

  /// 설정에서 권한을 허용한 뒤 돌아왔을 때 다시 예약
  static Future<void> rescheduleDailySummaryAfterAppResume() async {
    try {
      await scheduleDailySummaryFromPrefs([]);
    } catch (e) {
      debugPrint('NotificationService: resume 후 재예약 실패 $e');
    }
  }

  static Future<void> _configureLocalTimeZone() async {
    if (kIsWeb) {
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
      } catch (_) {}
      return;
    }
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      final id = info.identifier;
      if (id.isEmpty) {
        throw ArgumentError('빈 시간대 식별자');
      }
      tz.setLocalLocation(tz.getLocation(id));
      debugPrint('NotificationService: 로컬 시간대 $id');
    } catch (e) {
      debugPrint('NotificationService: 시간대 자동 설정 실패 ($e), Asia/Seoul 사용');
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
      } catch (e2) {
        debugPrint('NotificationService: Asia/Seoul 설정도 실패: $e2');
      }
    }
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

  static Future<void> _scheduleDailySummaryOnce({
    required int weekday,
    required String title,
    required String body,
    required tz.TZDateTime scheduled,
    required AndroidScheduleMode androidMode,
  }) async {
    await _plugin.zonedSchedule(
      _dailySummaryIdForWeekday(weekday),
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
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          subtitle: '오늘 일정 요약',
        ),
      ),
      androidScheduleMode: androidMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: payloadDailySummary,
    );
  }

  /// [todayEvents]는 오늘 포함 일정 목록(캘린더와 동일 필터). 비어 있으면 «일정 없음» 요약.
  static Future<void> scheduleDailySummaryFromPrefs(
      List<CalendarEvent> todayEvents) async {
    await ReminderPrefs.ensureMigrated();
    await _plugin.cancel(_dailySummaryNotificationIdLegacy);
    // 구 ID(999991~995) 및 신규(999981~987) 정리
    for (final id in <int>{
      999991,
      999992,
      999993,
      999994,
      999995,
      ...List.generate(7, (i) => 999981 + i),
    }) {
      await _plugin.cancel(id);
    }

    final title = _buildDailySummaryTitle(todayEvents.length);
    final body = _buildDailySummaryBody(todayEvents);
    final localTz = tz.local;
    final androidMode = await _androidScheduleModeForAlarms();

    for (var weekday = 1; weekday <= 7; weekday++) {
      final on = await ReminderPrefs.isWeekdayEnabled(weekday);
      if (!on) continue;

      final time = await ReminderPrefs.weekdayTime(weekday);
      final scheduled = _nextInstanceOfWeekdayAndTime(
        weekday,
        time.hour,
        time.minute,
        localTz,
      );

      try {
        await _scheduleDailySummaryOnce(
          weekday: weekday,
          title: title,
          body: body,
          scheduled: scheduled,
          androidMode: androidMode,
        );
      } catch (e) {
        if (androidMode == AndroidScheduleMode.exactAllowWhileIdle) {
          try {
            await _scheduleDailySummaryOnce(
              weekday: weekday,
              title: title,
              body: body,
              scheduled: scheduled,
              androidMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
            debugPrint(
              'NotificationService: 요약 알림 inexact 로 재예약됨 (weekday=$weekday)',
            );
          } catch (e2) {
            debugPrint(
              'NotificationService: 요약 알림 예약 실패 (weekday=$weekday) $e2',
            );
          }
        } else {
          debugPrint(
            'NotificationService: 요약 알림 예약 실패 (weekday=$weekday) $e',
          );
        }
      }
    }
  }

  /// [weekday]는 `DateTime.weekday`와 동일 (월=1 … 일=7).
  static tz.TZDateTime _nextInstanceOfWeekdayAndTime(
    int weekday,
    int hour,
    int minute,
    tz.Location location,
  ) {
    final now = tz.TZDateTime.now(location);
    var candidate = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    for (var i = 0; i < 8; i++) {
      if (candidate.weekday == weekday && !candidate.isBefore(now)) {
        return candidate;
      }
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
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
    final androidMode = await _androidScheduleModeForAlarms();

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

      try {
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
          androidScheduleMode: androidMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        if (androidMode == AndroidScheduleMode.exactAllowWhileIdle) {
          try {
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
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          } catch (e2) {
            debugPrint('NotificationService: 일정 알림 예약 실패 ${event.title} $e2');
          }
        } else {
          debugPrint('NotificationService: 일정 알림 예약 실패 ${event.title} $e');
        }
      }
    }

    final todaySlice = eventsForCalendarDay(events, now);
    await scheduleDailySummaryFromPrefs(todaySlice);
  }
}

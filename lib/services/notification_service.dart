import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/event.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'teamsync_schedule';
  static const _channelName = '스케줄 알림';
  static const _channelDesc = '오늘의 스케줄을 알려드립니다.';

  /** 앱 시작 시 1회 초기화 */
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
    );

    /** Android 13+ 알림 권한 요청 */
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /**
   * 오늘 일정에 대한 알림 예약
   * 기존 예약된 알림을 모두 취소하고 새로 등록
   */
  static Future<void> scheduleTodayEvents(List<CalendarEvent> events) async {
    await _plugin.cancelAll();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final localTz = tz.local;

    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      final eventDay = DateTime(
        event.startsAt.year, event.startsAt.month, event.startsAt.day,
      );

      /** 오늘 일정만 처리 */
      if (eventDay != today) continue;

      DateTime notifyAt;
      String body;

      if (event.isAllDay) {
        /** 하루 종일 일정 → 오전 8시 알림 */
        notifyAt = DateTime(today.year, today.month, today.day, 8, 0);
        body = '오늘 하루 종일 일정이 있습니다.';
      } else {
        /** 시간 지정 일정 → 시작 시간에 알림 */
        notifyAt = event.startsAt;
        final h = event.startsAt.hour.toString().padLeft(2, '0');
        final m = event.startsAt.minute.toString().padLeft(2, '0');
        body = '$h:$m 일정이 시작됩니다.';
      }

      /** 이미 지난 시간은 건너뜀 */
      if (notifyAt.isBefore(now)) continue;

      await _plugin.zonedSchedule(
        i,
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
      );
    }
  }
}

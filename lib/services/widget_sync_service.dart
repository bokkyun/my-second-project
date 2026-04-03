import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';

/// Android 홈 화면 위젯 데이터 동기화 (home_widget)
class WidgetSyncService {
  WidgetSyncService._();

  static const _qualifiedProvider = 'com.bokkyun.teamsync.TeamSyncWidgetProvider';

  /// 오늘 일정 요약을 위젯에 반영합니다.
  static Future<void> syncTodayEvents(List<CalendarEvent> allEvents) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final todayEvents = allEvents.where((e) {
      final start = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
      final end = DateTime(e.endsAt.year, e.endsAt.month, e.endsAt.day);
      return !today.isBefore(start) && !today.isAfter(end);
    }).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    final dateStr = DateFormat('M월 d일').format(today);
    final count = todayEvents.length;
    await HomeWidget.saveWidgetData<String>('ts_subtitle', '$dateStr · 일정 $count건');

    String detail;
    if (todayEvents.isEmpty) {
      detail = '오늘 일정이 없습니다';
    } else {
      detail = todayEvents
          .take(4)
          .map((e) {
            final time = e.isAllDay
                ? '종일'
                : DateFormat('HH:mm').format(e.startsAt);
            return '$time ${e.title}';
          })
          .join('\n');
    }
    await HomeWidget.saveWidgetData<String>('ts_detail', detail);

    await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedProvider);
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import 'subway_arrival_service.dart';
import 'subway_prefs.dart';

/// Android 홈 화면 위젯 데이터 동기화 (home_widget)
///
/// 네이티브 위젯은 [ts_events_json], [ts_anchor_ms]를 사용하고,
/// 일/주/월 모드(ts_view_mode)는 위젯 버튼으로만 바꾸므로 Flutter에서 덮어쓰지 않습니다.
class WidgetSyncService {
  WidgetSyncService._();

  static const _qualifiedProvider = 'com.bokkyun.teamsync.TeamSyncWidgetProvider';

  /// 오늘 일정 요약 + 전체 이벤트 JSON(일·주·월 달력용)을 위젯에 반영합니다.
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

    var forWidget = allEvents.toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    if (forWidget.length > 600) {
      forWidget = forWidget.take(600).toList();
    }
    final payload = jsonEncode(
      forWidget
          .map(
            (e) => <String, Object?>{
              's': e.startsAt.millisecondsSinceEpoch,
              'e': e.endsAt.millisecondsSinceEpoch,
              't': e.title,
              'a': e.isAllDay ? 1 : 0,
            },
          )
          .toList(),
    );
    await HomeWidget.saveWidgetData<String>('ts_events_json', payload);

    final anchorMs = today.millisecondsSinceEpoch;
    await HomeWidget.saveWidgetData<int>('ts_anchor_ms', anchorMs);

    await _syncSubwaySummaryData();
    await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedProvider);
  }

  static Future<void> syncSubwayOnly() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    await _syncSubwaySummaryData();
    await HomeWidget.updateWidget(qualifiedAndroidName: _qualifiedProvider);
  }

  static Future<void> _syncSubwaySummaryData() async {
    final config = await SubwayPrefs.load();
    final summary = await SubwayArrivalService.buildSummary(config);
    await HomeWidget.saveWidgetData<String>('ts_subway_summary', summary);
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 매일 같은 시각 "오늘 일정을 알려드릴까요?" 알림 설정
class ReminderPrefs {
  ReminderPrefs._();

  static const _keyEnabled = 'daily_reminder_enabled';
  static const _keyHour = 'daily_reminder_hour';
  static const _keyMinute = 'daily_reminder_minute';

  static Future<bool> isDailyReminderEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyEnabled) ?? false;
  }

  static Future<TimeOfDay> dailyReminderTime() async {
    final p = await SharedPreferences.getInstance();
    final h = p.getInt(_keyHour) ?? 8;
    final m = p.getInt(_keyMinute) ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  static Future<void> setDailyReminder({
    required bool enabled,
    TimeOfDay? time,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyEnabled, enabled);
    if (time != null) {
      await p.setInt(_keyHour, time.hour);
      await p.setInt(_keyMinute, time.minute);
    }
  }
}

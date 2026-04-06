import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 요일별(월~일) "오늘 일정 요약" 로컬 알림 설정 (요일마다 시각·on/off 분리)
class ReminderPrefs {
  ReminderPrefs._();

  static const _migratedKey = 'daily_reminder_v2_migrated';
  static const _weekendMigratedKey = 'daily_reminder_v3_weekend_migrated';

  /// 구버전: 단일 시각
  static const _keyEnabled = 'daily_reminder_enabled';
  static const _keyHour = 'daily_reminder_hour';
  static const _keyMinute = 'daily_reminder_minute';

  static String _wdEnabledKey(int weekday) =>
      'daily_reminder_wd_${weekday}_enabled';
  static String _wdHourKey(int weekday) => 'daily_reminder_wd_${weekday}_hour';
  static String _wdMinuteKey(int weekday) =>
      'daily_reminder_wd_${weekday}_minute';

  /// 기존 단일 알림 설정을 월~금 동일 값으로 복사 (최초 1회)
  static Future<void> ensureMigrated() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_migratedKey) != true) {
      final oldEn = p.getBool(_keyEnabled) ?? false;
      final oldH = p.getInt(_keyHour) ?? 8;
      final oldM = p.getInt(_keyMinute) ?? 0;

      for (var wd = 1; wd <= 5; wd++) {
        await p.setBool(_wdEnabledKey(wd), oldEn);
        await p.setInt(_wdHourKey(wd), oldH.clamp(0, 23));
        await p.setInt(_wdMinuteKey(wd), oldM.clamp(0, 59));
      }
      await p.setBool(_migratedKey, true);
    }

    // 토·일 키가 없을 때만 기본값 (꺼짐, 08:00)
    if (p.getBool(_weekendMigratedKey) != true) {
      for (final wd in [6, 7]) {
        if (!p.containsKey(_wdHourKey(wd))) {
          await p.setBool(_wdEnabledKey(wd), false);
          await p.setInt(_wdHourKey(wd), 8);
          await p.setInt(_wdMinuteKey(wd), 0);
        }
      }
      await p.setBool(_weekendMigratedKey, true);
    }
  }

  /// [weekday]: `DateTime.weekday`와 동일 (월=1 … 일=7)
  static Future<bool> isWeekdayEnabled(int weekday) async {
    await ensureMigrated();
    final p = await SharedPreferences.getInstance();
    return p.getBool(_wdEnabledKey(weekday)) ?? false;
  }

  static Future<TimeOfDay> weekdayTime(int weekday) async {
    await ensureMigrated();
    final p = await SharedPreferences.getInstance();
    final h = p.getInt(_wdHourKey(weekday)) ?? 8;
    final m = p.getInt(_wdMinuteKey(weekday)) ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  static Future<void> setWeekday({
    required int weekday,
    required bool enabled,
    required TimeOfDay time,
  }) async {
    await ensureMigrated();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_wdEnabledKey(weekday), enabled);
    await p.setInt(_wdHourKey(weekday), time.hour);
    await p.setInt(_wdMinuteKey(weekday), time.minute);
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/reminder_prefs.dart';

/// 월~일 각각 알림 on/off 및 시각 (알람 앱 스타일)
class DailyReminderSettingsPanel extends StatefulWidget {
  const DailyReminderSettingsPanel({super.key});

  @override
  State<DailyReminderSettingsPanel> createState() =>
      _DailyReminderSettingsPanelState();
}

class _DailyReminderSettingsPanelState
    extends State<DailyReminderSettingsPanel> {
  bool _loading = true;
  final List<bool> _enabled = List.filled(7, false);
  final List<TimeOfDay> _times = List.filled(
    7,
    const TimeOfDay(hour: 8, minute: 0),
  );

  static const _labels = [
    '월요일',
    '화요일',
    '수요일',
    '목요일',
    '금요일',
    '토요일',
    '일요일',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ReminderPrefs.ensureMigrated();
    for (var i = 0; i < 7; i++) {
      final wd = i + 1;
      _enabled[i] = await ReminderPrefs.isWeekdayEnabled(wd);
      _times[i] = await ReminderPrefs.weekdayTime(wd);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _applyAndReschedule() async {
    await NotificationService.scheduleDailySummaryFromPrefs([]);
  }

  Future<void> _onToggleDay(int index, bool value) async {
    setState(() => _enabled[index] = value);
    await ReminderPrefs.setWeekday(
      weekday: index + 1,
      enabled: value,
      time: _times[index],
    );
    await _applyAndReschedule();
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(value ? '$_labels[index] 알림이 켜졌습니다.' : '$_labels[index] 알림을 껐습니다.')),
      );
    }
  }

  Future<void> _pickTime(int index) async {
    final t = await showTimePicker(
      context: context,
      initialTime: _times[index],
    );
    if (t == null || !mounted) return;
    setState(() => _times[index] = t);
    await ReminderPrefs.setWeekday(
      weekday: index + 1,
      enabled: _enabled[index],
      time: t,
    );
    await _applyAndReschedule();
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('알림 시간이 저장되었습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '요일별 알림',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        if (kIsWeb) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '웹 브라우저에서는 OS 예약 알림(로컬 알림)이 지원되지 않습니다. 설정은 저장되며, 실제 알림은 Android 앱에서 받을 수 있습니다.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
        Text(
          '요일마다 다른 시각에 오늘 일정 요약을 받을 수 있어요. 끈 요일에는 알림이 가지 않습니다.',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '알림이 오지 않으면 기기 설정에서 앱 알림을 허용하고, 「알람 및 리마인더」(정확한 알람) 권한을 켜 주세요.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(7, (i) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(_labels[i]),
                  subtitle: Text(
                    _enabled[i] ? _times[i].format(context) : '알림 없음',
                    style: TextStyle(
                      color: _enabled[i]
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                  ),
                  value: _enabled[i],
                  onChanged: (v) => _onToggleDay(i, v),
                ),
                if (_enabled[i])
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.alarm, size: 22),
                    title: const Text('알림 시각'),
                    trailing: Text(
                      _times[i].format(context),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => _pickTime(i),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// 캘린더 등에서 모달로 열 때 사용
Future<void> showDailyReminderSettingsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.paddingOf(ctx).bottom + 16,
          ),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (_, scrollCtrl) => SingleChildScrollView(
              controller: scrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '오늘 일정 요약 알림',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  const DailyReminderSettingsPanel(),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

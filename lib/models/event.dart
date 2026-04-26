import 'package:flutter/material.dart';

class CalendarEvent {
  /// Supabase에 저장되지 않는 읽기 전용(공공 API 등) 일정
  static const kExternalCreatorId = '__external__';

  final String id;
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAllDay;
  final String color;
  final String creatorId;
  final String? creatorNickname;
  final List<String> groupIds;

  /// `schedule` 일반 일정 | `group_event` 그룹 전체에 공유되는 이벤트 | `default`·`coffee` 는 DB/웹과 맞춤
  final String eventKind;

  /// null이면 Supabase. `reb-apt` 등은 캘린더에만 합쳐 표시(수정·삭제 불가).
  final String? externalSource;

  /// 공공 API 원본(청약 `reb-odcloud` 상세·한글 라벨 표시용, 선택)
  final Map<String, dynamic>? externalRaw;

  const CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startsAt,
    required this.endsAt,
    required this.isAllDay,
    required this.color,
    required this.creatorId,
    this.creatorNickname,
    required this.groupIds,
    this.eventKind = 'schedule',
    this.externalSource,
    this.externalRaw,
  });

  bool get isExternal => externalSource != null;
  bool get isGroupEvent => eventKind == 'group_event' && !isExternal;

  factory CalendarEvent.fromMap(Map<String, dynamic> map,
      {String? creatorNickname}) {
    final visibility = map['event_visibility'] as List<dynamic>? ?? [];
    return CalendarEvent(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      startsAt: DateTime.parse(map['starts_at'] as String).toLocal(),
      endsAt: DateTime.parse(map['ends_at'] as String).toLocal(),
      isAllDay: map['is_all_day'] as bool? ?? false,
      color: map['color'] as String? ?? '#1976d2',
      creatorId: map['creator_id'] as String,
      creatorNickname: creatorNickname,
      groupIds: visibility.map((v) => v['group_id'] as String).toList(),
      eventKind: map['event_kind'] as String? ?? 'schedule',
      externalSource: null,
      externalRaw: null,
    );
  }

  Color get flutterColor {
    final hex = color.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  DateTime get startDay =>
      DateTime(startsAt.year, startsAt.month, startsAt.day);
}

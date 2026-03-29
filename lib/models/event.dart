import 'package:flutter/material.dart';

class CalendarEvent {
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
  });

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
    );
  }

  Color get flutterColor {
    final hex = color.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  DateTime get startDay =>
      DateTime(startsAt.year, startsAt.month, startsAt.day);
}

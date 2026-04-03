import 'package:flutter/material.dart';

class Group {
  final String id;
  final String name;
  final String? description;
  final String color;
  final bool isSearchable;
  final String createdBy;
  final String myRole; // admin / member / readonly

  /// 그룹원이 등록한 일정에 대한 푸시 알림 수신 동의
  final bool notifyGroupEvents;

  const Group({
    required this.id,
    required this.name,
    this.description,
    required this.color,
    required this.isSearchable,
    required this.createdBy,
    required this.myRole,
    this.notifyGroupEvents = true,
  });

  factory Group.fromMap(Map<String, dynamic> map, String role) {
    return Group(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      color: map['color'] as String? ?? '#1976d2',
      isSearchable: map['is_searchable'] as bool? ?? false,
      createdBy: map['created_by'] as String,
      myRole: role,
      notifyGroupEvents: true,
    );
  }

  /// `group_members` 조인 결과 행: `{ role, notify_group_events, groups: {...} }`
  factory Group.fromMemberRow(Map<String, dynamic> row) {
    final map = row['groups'] as Map<String, dynamic>;
    return Group(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      color: map['color'] as String? ?? '#1976d2',
      isSearchable: map['is_searchable'] as bool? ?? false,
      createdBy: map['created_by'] as String,
      myRole: row['role'] as String,
      notifyGroupEvents: row['notify_group_events'] as bool? ?? true,
    );
  }

  Color get flutterColor {
    final hex = color.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}

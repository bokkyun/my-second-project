import 'package:flutter/material.dart';

class Group {
  final String id;
  final String name;
  final String? description;
  final String color;
  final bool isSearchable;
  final String createdBy;
  final String myRole; // admin / member / readonly

  const Group({
    required this.id,
    required this.name,
    this.description,
    required this.color,
    required this.isSearchable,
    required this.createdBy,
    required this.myRole,
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
    );
  }

  Color get flutterColor {
    final hex = color.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}

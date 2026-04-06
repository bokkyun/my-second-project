import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/group.dart';

class EventDetailSheet extends StatelessWidget {
  final CalendarEvent event;
  final List<Group> groups;
  final String currentUserId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const EventDetailSheet({
    super.key,
    required this.event,
    required this.groups,
    required this.currentUserId,
    required this.onEdit,
    required this.onDelete,
  });

  String _fmt(DateTime dt, bool isAllDay) => isAllDay
      ? DateFormat('yyyy.MM.dd (E)', 'ko').format(dt)
      : DateFormat('yyyy.MM.dd (E) HH:mm', 'ko').format(dt);

  @override
  Widget build(BuildContext context) {
    final isOwner = event.creatorId == currentUserId;
    final isGroupAdmin = event.groupIds.any(
      (gid) => groups.any((g) => g.id == gid && g.myRole == 'admin'),
    );
    final canEdit = isOwner || isGroupAdmin;
    final sharedGroups = groups.where((g) => event.groupIds.contains(g.id)).toList();

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 4, width: 40, margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),

        // 헤더
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: event.flutterColor.withOpacity(0.12),
            border: Border(left: BorderSide(color: event.flutterColor, width: 4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (event.isGroupEvent) ...[
              const SizedBox(height: 6),
              Chip(
                label: const Text('그룹 이벤트', style: TextStyle(fontSize: 12)),
                backgroundColor: event.flutterColor.withOpacity(0.2),
                side: BorderSide(color: event.flutterColor.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
            if (event.creatorNickname != null)
              Text('등록: ${event.creatorNickname}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 시간
            Row(children: [
              const Icon(Icons.schedule, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(child: Text(
                event.isAllDay
                    ? '${_fmt(event.startsAt, true)} (하루 종일)'
                    : '${_fmt(event.startsAt, false)} ~ ${_fmt(event.endsAt, false)}',
                style: const TextStyle(fontSize: 14),
              )),
            ]),

            // 메모
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.notes, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text(event.description!, style: const TextStyle(fontSize: 14))),
              ]),
            ],

            // 공유 그룹
            if (sharedGroups.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.group, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Wrap(
                  spacing: 6, runSpacing: 4,
                  children: sharedGroups.map((g) => Chip(
                    label: Text(g.name, style: const TextStyle(fontSize: 12)),
                    backgroundColor: g.flutterColor.withOpacity(0.15),
                    side: BorderSide(color: g.flutterColor.withOpacity(0.3)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  )).toList(),
                )),
              ]),
            ],

            if (canEdit) ...[
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('수정'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    label: const Text('삭제', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ]),
      ),
    );
  }
}

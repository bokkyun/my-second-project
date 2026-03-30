import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event.dart';

class EventService {
  static final _db = Supabase.instance.client;

  static Future<List<CalendarEvent>> fetchEvents(
      String userId, List<String> visibleGroupIds) async {
    // 내 일정
    final myRes = await _db
        .from('events')
        .select('*, event_visibility(group_id)')
        .eq('creator_id', userId);

    // 공유된 그룹 일정
    List<Map<String, dynamic>> sharedRaw = [];
    if (visibleGroupIds.isNotEmpty) {
      final sharedRes = await _db
          .from('event_visibility')
          .select('event_id, group_id, events(*, event_visibility(group_id))')
          .inFilter('group_id', visibleGroupIds);
      sharedRaw = (sharedRes as List)
          .where((r) =>
              r['events'] != null &&
              r['events']['creator_id'] != userId)
          .map((r) => r['events'] as Map<String, dynamic>)
          .toList();
    }

    final allRaw = [
      ...(myRes as List).cast<Map<String, dynamic>>(),
      ...sharedRaw,
    ];

    // 중복 제거
    final unique = <String, Map<String, dynamic>>{};
    for (final e in allRaw) {
      unique[e['id'] as String] = e;
    }

    // 등록자 닉네임 fetch
    final creatorIds =
        unique.values.map((e) => e['creator_id'] as String).toSet().toList();
    final Map<String, String?> nicknameMap = {};
    if (creatorIds.isNotEmpty) {
      final profiles = await _db
          .from('profiles')
          .select('id, nickname')
          .inFilter('id', creatorIds);
      for (final p in profiles as List) {
        nicknameMap[p['id'] as String] = p['nickname'] as String?;
      }
    }

    return unique.values
        .map((e) => CalendarEvent.fromMap(e,
            creatorNickname: nicknameMap[e['creator_id'] as String]))
        .toList();
  }

  static Future<void> createEvent({
    required String userId,
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool isAllDay,
    required String color,
    required List<String> groupIds,
  }) async {
    final ev = await _db
        .from('events')
        .insert({
          'title': title,
          'description': description,
          'starts_at': startsAt.toUtc().toIso8601String(),
          'ends_at': endsAt.toUtc().toIso8601String(),
          'is_all_day': isAllDay,
          'color': color,
          'creator_id': userId,
        })
        .select()
        .single();

    if (groupIds.isNotEmpty) {
      await _db.from('event_visibility').insert(
            groupIds.map((gid) => {'event_id': ev['id'], 'group_id': gid}).toList(),
          );
    }
  }

  static Future<void> updateEvent({
    required String eventId,
    required String userId,
    required String title,
    String? description,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool isAllDay,
    required String color,
    required List<String> groupIds,
    bool isAdminOverride = false,
  }) async {
    final query = _db.from('events').update({
      'title': title,
      'description': description,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'is_all_day': isAllDay,
      'color': color,
    }).eq('id', eventId);
    if (isAdminOverride) {
      await query;
    } else {
      await query.eq('creator_id', userId);
    }

    await _db.from('event_visibility').delete().eq('event_id', eventId);
    if (groupIds.isNotEmpty) {
      await _db.from('event_visibility').insert(
            groupIds.map((gid) => {'event_id': eventId, 'group_id': gid}).toList(),
          );
    }
  }

  static Future<void> deleteEvent(String eventId, String userId,
      {bool isAdminOverride = false}) async {
    final query = _db.from('events').delete().eq('id', eventId);
    if (isAdminOverride) {
      await query;
    } else {
      await query.eq('creator_id', userId);
    }
  }
}

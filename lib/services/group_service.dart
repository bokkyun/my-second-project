import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/group.dart';

class GroupService {
  static final _db = Supabase.instance.client;

  static Future<List<Group>> fetchMyGroups(String userId) async {
    final res = await _db
        .from('group_members')
        .select('role, groups(*)')
        .eq('user_id', userId);
    return (res as List)
        .map((m) => Group.fromMap(m['groups'] as Map<String, dynamic>, m['role'] as String))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> fetchGroupMembers(
      String groupId) async {
    final res = await _db
        .from('group_members')
        .select('role, profiles(id, nickname, email)')
        .eq('group_id', groupId);
    return (res as List).map((m) {
      final profile = m['profiles'] as Map<String, dynamic>;
      return {
        'id': profile['id'],
        'nickname': profile['nickname'],
        'email': profile['email'],
        'role': m['role'],
      };
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> searchGroups(String query) async {
    final res = await _db
        .from('groups')
        .select()
        .eq('is_searchable', true)
        .ilike('name', '%$query%');
    return (res as List).cast<Map<String, dynamic>>();
  }

  static Future<void> createGroup({
    required String userId,
    required String name,
    required String description,
    required String color,
    required bool isSearchable,
  }) async {
    final group = await _db
        .from('groups')
        .insert({
          'name': name,
          'description': description,
          'color': color,
          'is_searchable': isSearchable,
          'created_by': userId,
        })
        .select()
        .single();
    await _db.from('group_members').insert({
      'group_id': group['id'],
      'user_id': userId,
      'role': 'admin',
    });
  }

  static Future<void> joinGroup(String groupId, String userId) async {
    await _db.from('group_members').insert({
      'group_id': groupId,
      'user_id': userId,
      'role': 'member',
    });
  }

  static Future<void> leaveGroup(String groupId, String userId) async {
    await _db
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  static Future<void> deleteGroup(String groupId, String userId) async {
    await _db
        .from('groups')
        .delete()
        .eq('id', groupId)
        .eq('created_by', userId);
  }
}

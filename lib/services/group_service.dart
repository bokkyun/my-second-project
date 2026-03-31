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
        .select('id, name, description, color, is_searchable, created_by')
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
    required String password,
  }) async {
    final group = await _db
        .from('groups')
        .insert({
          'name': name,
          'description': description,
          'color': color,
          'is_searchable': isSearchable,
          'created_by': userId,
          'password': password,
        })
        .select()
        .single();
    await _db.from('group_members').insert({
      'group_id': group['id'],
      'user_id': userId,
      'role': 'admin',
    });
  }

  static Future<void> joinGroup(String groupId, String userId, String password) async {
    final verify = await _db
        .from('groups')
        .select('id')
        .eq('id', groupId)
        .eq('password', password)
        .maybeSingle();
    if (verify == null) {
      throw Exception('비밀번호가 틀렸습니다.');
    }
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

  /** 그룹 비밀번호 변경 (관리자만 가능) */
  static Future<void> changeGroupPassword(String groupId, String userId, String newPassword) async {
    await _db
        .from('groups')
        .update({'password': newPassword})
        .eq('id', groupId)
        .eq('created_by', userId);
  }

  /** 그룹 관리자를 다른 멤버로 변경 (현재 관리자는 일반 멤버로 강등) */
  static Future<void> changeGroupAdmin(
      String groupId, String newAdminUserId, String currentUserId) async {
    await _db
        .from('group_members')
        .update({'role': 'admin'})
        .eq('group_id', groupId)
        .eq('user_id', newAdminUserId);
    await _db
        .from('group_members')
        .update({'role': 'member'})
        .eq('group_id', groupId)
        .eq('user_id', currentUserId);
  }
}

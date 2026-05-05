import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models.dart';
import 'notification_repository.dart';

/// Backed by [supabase/migrations/016_in_app_notifications.sql].
class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<AppNotification>> listForUser(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null || me != userId) return [];

    final rows = await _client
        .from('in_app_notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final list = rows as List<dynamic>;
    return list
        .map((e) => _fromRow(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> add({
    required String userId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;

    if (userId == me) {
      final row = <String, dynamic>{
        'user_id': userId,
        'title': title,
        'body': body,
      };
      if (data != null) row['data'] = data;
      await _client.from('in_app_notifications').insert(row);
      return;
    }

    await _client.rpc<void>(
      'notify_user',
      params: <String, dynamic>{
        'p_user_id': userId,
        'p_title': title,
        'p_body': body,
        'p_data': data,
      },
    );
  }

  @override
  Future<void> markRead({required String notificationId}) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;

    await _client
        .from('in_app_notifications')
        .update(<String, dynamic>{
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', notificationId)
        .eq('user_id', me);
  }

  static AppNotification _fromRow(Map<String, dynamic> row) {
    return AppNotification(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      title: row['title'] as String,
      body: row['body'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      readAt: row['read_at'] == null
          ? null
          : DateTime.parse(row['read_at'] as String),
      data: _stringMap(row['data']),
    );
  }

  static Map<String, String>? _stringMap(dynamic v) {
    if (v == null) return null;
    if (v is Map) {
      return v.map(
        (k, val) => MapEntry(k.toString(), val?.toString() ?? ''),
      );
    }
    return null;
  }
}

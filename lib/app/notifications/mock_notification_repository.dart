import 'dart:convert';

import '../../domain/models.dart';
import '../storage/kv_store.dart';

class MockNotificationRepository {
  MockNotificationRepository(this._store);

  final KvStore _store;

  static const _kNotifications = 'agapshift.notifications.items';

  Future<List<AppNotification>> listForUser(String userId) async {
    final all = await _loadAll();
    return all.where((n) => n.userId == userId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> add({
    required String userId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    final all = await _loadAll();
    final id = 'n_${DateTime.now().microsecondsSinceEpoch}';
    final n = AppNotification(
      id: id,
      userId: userId,
      title: title,
      body: body,
      createdAt: DateTime.now().toUtc(),
      readAt: null,
      data: data,
    );
    await _saveAll([n, ...all]);
  }

  Future<void> markRead({required String notificationId}) async {
    final all = await _loadAll();
    final updated = all.map((n) {
      if (n.id != notificationId) return n;
      return AppNotification(
        id: n.id,
        userId: n.userId,
        title: n.title,
        body: n.body,
        createdAt: n.createdAt,
        readAt: DateTime.now().toUtc(),
        data: n.data,
      );
    }).toList();
    await _saveAll(updated);
  }

  Future<List<AppNotification>> _loadAll() async {
    final raw = await _store.getString(_kNotifications);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _saveAll(List<AppNotification> items) async {
    final encoded = items.map(_toJson).toList();
    await _store.setString(_kNotifications, jsonEncode(encoded));
  }

  Map<String, dynamic> _toJson(AppNotification n) => {
        'id': n.id,
        'userId': n.userId,
        'title': n.title,
        'body': n.body,
        'createdAt': n.createdAt.toIso8601String(),
        'readAt': n.readAt?.toIso8601String(),
        'data': n.data,
      };

  AppNotification _fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        userId: j['userId'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        readAt: j['readAt'] == null ? null : DateTime.parse(j['readAt'] as String),
        data: j['data'] == null ? null : Map<String, String>.from(j['data'] as Map),
      );
}


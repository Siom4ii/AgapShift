import 'package:supabase_flutter/supabase_flutter.dart';

import '../profile/worker_display_names.dart';
import 'messaging_models.dart';
import 'messaging_repository.dart';

/// Postgres-backed DMs ([supabase/migrations/013_direct_messaging.sql]).
class SupabaseMessagingRepository implements MessagingRepository {
  SupabaseMessagingRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  Future<int> _unreadFromPeer({
    required String conversationId,
    required String me,
    DateTime? lastReadAt,
  }) async {
    dynamic res;
    if (lastReadAt == null) {
      res = await _client
          .from('dm_messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', me);
    } else {
      res = await _client
          .from('dm_messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', me)
          .gt('created_at', lastReadAt.toUtc().toIso8601String());
    }
    return (res as List<dynamic>).length;
  }

  @override
  Future<List<DmConversationSummary>> listConversations() async {
    final me = _me;
    if (me == null) return [];
    final mem = await _client
        .from('dm_conversation_members')
        .select('conversation_id, last_read_at')
        .eq('user_id', me);
    final list = mem as List<dynamic>;
    final lastReadByConv = <String, DateTime?>{};
    final convIds = <String>[];
    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      final cid = m['conversation_id'] as String?;
      if (cid == null || cid.isEmpty) continue;
      convIds.add(cid);
      final lr = m['last_read_at'];
      lastReadByConv[cid] =
          lr == null ? null : DateTime.tryParse(lr.toString());
    }
    final uniqueIds = convIds.toSet().toList();
    if (uniqueIds.isEmpty) return [];

    final convRows = await _client
        .from('dm_conversations')
        .select('id, updated_at')
        .inFilter('id', uniqueIds)
        .order('updated_at', ascending: false);

    final rows = convRows as List<dynamic>;
    final otherIds = <String>{};
    final summaries = <DmConversationSummary>[];

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final cid = row['id'] as String;
      final updatedAt = DateTime.parse(row['updated_at'] as String);
      final others = await _client
          .from('dm_conversation_members')
          .select('user_id')
          .eq('conversation_id', cid)
          .neq('user_id', me);
      final olist = others as List<dynamic>;
      if (olist.isEmpty) continue;
      final otherId =
          Map<String, dynamic>.from(olist.first as Map)['user_id'] as String;
      otherIds.add(otherId);
      final last = await _client
          .from('dm_messages')
          .select('body, sender_id')
          .eq('conversation_id', cid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final preview = last == null ? '' : ((last['body'] as String?) ?? '');
      final lastSender =
          last == null ? null : (last['sender_id'] as String?);
      final unread = await _unreadFromPeer(
        conversationId: cid,
        me: me,
        lastReadAt: lastReadByConv[cid],
      );
      summaries.add(
        DmConversationSummary(
          conversationId: cid,
          otherUserId: otherId,
          otherDisplayName: _peerFallback(otherId),
          lastPreview: preview,
          updatedAt: updatedAt,
          lastMessageSenderId: lastSender,
          unreadCount: unread,
        ),
      );
    }

    final names = await fetchWorkerDisplayNamesById(otherIds);
    final merged = summaries.map((s) {
      final n = names[s.otherUserId]?.trim();
      if (n != null && n.isNotEmpty) {
        return DmConversationSummary(
          conversationId: s.conversationId,
          otherUserId: s.otherUserId,
          otherDisplayName: n,
          lastPreview: s.lastPreview,
          updatedAt: s.updatedAt,
          lastMessageSenderId: s.lastMessageSenderId,
          unreadCount: s.unreadCount,
        );
      }
      return s;
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return merged;
  }

  @override
  Future<int> unreadCount() async {
    final me = _me;
    if (me == null) return 0;
    final memRows = await _client
        .from('dm_conversation_members')
        .select('conversation_id,last_read_at')
        .eq('user_id', me);
    final memList = memRows as List<dynamic>;
    if (memList.isEmpty) return 0;

    var total = 0;
    for (final raw in memList) {
      final m = Map<String, dynamic>.from(raw as Map);
      final cid = m['conversation_id'] as String?;
      if (cid == null || cid.isEmpty) continue;
      final lastReadRaw = m['last_read_at'];
      final lastRead = lastReadRaw == null
          ? null
          : DateTime.tryParse(lastReadRaw.toString());

      // Count messages from OTHER user after last_read_at.
      // Note: per-conversation read timestamps prevent a clean single query, so we loop.
      dynamic res;
      if (lastRead == null) {
        res = await _client
            .from('dm_messages')
            .select('id')
            .eq('conversation_id', cid)
            .neq('sender_id', me);
      } else {
        res = await _client
            .from('dm_messages')
            .select('id')
            .eq('conversation_id', cid)
            .neq('sender_id', me)
            .gt('created_at', lastRead.toUtc().toIso8601String());
      }
      final list = res as List<dynamic>;
      total += list.length;
    }
    return total;
  }

  String _peerFallback(String id) {
    final t = id.trim();
    if (t.length <= 12) return t;
    return '…${t.substring(t.length - 6)}';
  }

  @override
  Future<String> getOrCreateConversation({required String otherUserId}) async {
    final res = await _client.rpc<dynamic>(
      'dm_get_or_create_conversation',
      params: {'p_other': otherUserId},
    );
    return res.toString();
  }

  @override
  Future<List<DmMessage>> listMessages(String conversationId, {int limit = 200}) async {
    final rows = await _client
        .from('dm_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(limit);
    final list = rows as List<dynamic>;
    return list.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      return DmMessage(
        id: m['id'] as String,
        conversationId: m['conversation_id'] as String,
        senderId: m['sender_id'] as String,
        body: m['body'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
    }).toList();
  }

  @override
  Future<DmMessage> sendMessage({
    required String conversationId,
    required String body,
  }) async {
    final me = _me;
    if (me == null) throw StateError('Not signed in');
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('Empty message');
    final row = await _client
        .from('dm_messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': me,
          'body': text,
        })
        .select()
        .single();
    final m = Map<String, dynamic>.from(row);
    return DmMessage(
      id: m['id'] as String,
      conversationId: m['conversation_id'] as String,
      senderId: m['sender_id'] as String,
      body: m['body'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }

  @override
  Stream<List<DmMessage>> watchMessages(String conversationId) async* {
    yield await listMessages(conversationId);
    await for (final _
        in _client.from('dm_messages').stream(primaryKey: ['id']).eq(
              'conversation_id',
              conversationId,
            )) {
      yield await listMessages(conversationId);
    }
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    final me = _me;
    if (me == null) return;
    await _client.from('dm_conversation_members').update({
      'last_read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('conversation_id', conversationId).eq('user_id', me);
  }
}

import 'dart:async';
import 'dart:convert';

import '../session/app_actor_id.dart';
import '../session/session_controller.dart';
import '../storage/kv_store.dart';
import 'messaging_models.dart';
import 'messaging_repository.dart';

class _MockConvo {
  _MockConvo({
    required this.id,
    required this.participants,
    required this.messages,
    required this.updatedAt,
  });

  final String id;
  final List<String> participants;
  final List<_MockMsg> messages;
  DateTime updatedAt;
}

class _MockMsg {
  _MockMsg({
    required this.id,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String body;
  final DateTime createdAt;
}

class MockMessagingRepository implements MessagingRepository {
  MockMessagingRepository(this._store, this._session);

  final KvStore _store;
  final SessionController _session;

  static const _k = 'agapshift.dm.mock_v1';

  String get _me => appActorId(_session, mockFallback: 'me');

  Future<List<_MockConvo>> _load() async {
    final raw = await _store.getString(_k);
    if (raw == null || raw.isEmpty) return [];
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final list = map['conversations'] as List<dynamic>? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      final msgs = (m['messages'] as List<dynamic>? ?? [])
          .map(
            (x) => _MockMsg(
              id: x['id'] as String,
              senderId: x['senderId'] as String,
              body: x['body'] as String,
              createdAt: DateTime.parse(x['createdAt'] as String),
            ),
          )
          .toList();
      return _MockConvo(
        id: m['id'] as String,
        participants: (m['participants'] as List<dynamic>)
            .map((p) => p as String)
            .toList(),
        messages: msgs,
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );
    }).toList();
  }

  Future<void> _save(List<_MockConvo> all) async {
    final encoded = all
        .map(
          (c) => {
            'id': c.id,
            'participants': c.participants,
            'updatedAt': c.updatedAt.toUtc().toIso8601String(),
            'messages': c.messages
                .map(
                  (m) => {
                    'id': m.id,
                    'senderId': m.senderId,
                    'body': m.body,
                    'createdAt': m.createdAt.toUtc().toIso8601String(),
                  },
                )
                .toList(),
          },
        )
        .toList();
    await _store.setString(_k, jsonEncode({'conversations': encoded}));
  }

  @override
  Future<List<DmConversationSummary>> listConversations() async {
    final me = _me;
    final all = await _load();
    final out = <DmConversationSummary>[];
    for (final c in all) {
      if (!c.participants.contains(me)) continue;
      final other = c.participants.firstWhere((p) => p != me, orElse: () => '');
      final last = c.messages.isEmpty
          ? null
          : c.messages.reduce(
              (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
            );
      out.add(
        DmConversationSummary(
          conversationId: c.id,
          otherUserId: other,
          otherDisplayName: other.isEmpty ? 'Unknown' : _shortPeer(other),
          lastPreview: last?.body ?? '',
          updatedAt: c.updatedAt,
        ),
      );
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  String _shortPeer(String id) {
    final t = id.trim();
    if (t.contains('@')) return t.split('@').first;
    if (t.length <= 14) return t;
    return '${t.substring(0, 6)}…${t.substring(t.length - 4)}';
  }

  @override
  Future<String> getOrCreateConversation({required String otherUserId}) async {
    final me = _me;
    if (otherUserId == me) {
      throw ArgumentError('Cannot message yourself');
    }
    final all = await _load();
    for (final c in all) {
      if (c.participants.contains(me) && c.participants.contains(otherUserId)) {
        return c.id;
      }
    }
    final id = 'dm_${DateTime.now().microsecondsSinceEpoch}';
    all.add(
      _MockConvo(
        id: id,
        participants: [me, otherUserId],
        messages: [],
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await _save(all);
    return id;
  }

  @override
  Future<List<DmMessage>> listMessages(String conversationId, {int limit = 200}) async {
    final all = await _load();
    _MockConvo? c;
    for (final x in all) {
      if (x.id == conversationId) {
        c = x;
        break;
      }
    }
    if (c == null) return [];
    final slice = c.messages.length > limit ? c.messages.sublist(c.messages.length - limit) : c.messages;
    return slice
        .map(
          (m) => DmMessage(
            id: m.id,
            conversationId: conversationId,
            senderId: m.senderId,
            body: m.body,
            createdAt: m.createdAt,
          ),
        )
        .toList();
  }

  @override
  Future<DmMessage> sendMessage({
    required String conversationId,
    required String body,
  }) async {
    final me = _me;
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('Empty message');
    final all = await _load();
    final idx = all.indexWhere((c) => c.id == conversationId);
    if (idx < 0) throw StateError('Conversation not found');
    final c = all[idx];
    if (!c.participants.contains(me)) throw StateError('Not a participant');
    final msg = _MockMsg(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}',
      senderId: me,
      body: text,
      createdAt: DateTime.now().toUtc(),
    );
    c.messages.add(msg);
    c.updatedAt = msg.createdAt;
    await _save(all);
    return DmMessage(
      id: msg.id,
      conversationId: conversationId,
      senderId: me,
      body: msg.body,
      createdAt: msg.createdAt,
    );
  }

  @override
  Stream<List<DmMessage>> watchMessages(String conversationId) {
    late StreamController<List<DmMessage>> c;
    Timer? timer;
    c = StreamController<List<DmMessage>>(
      onListen: () async {
        Future<void> pump() async {
          if (c.isClosed) return;
          try {
            c.add(await listMessages(conversationId));
          } catch (e, st) {
            c.addError(e, st);
          }
        }

        await pump();
        timer = Timer.periodic(const Duration(seconds: 2), (_) => pump());
      },
      onCancel: () {
        timer?.cancel();
      },
    );
    return c.stream;
  }

  @override
  Future<void> markConversationRead(String conversationId) async {}
}

import 'package:flutter/material.dart';

import '../../../notifications/mock_notification_repository.dart';
import '../../../session/session_controller.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.repo,
    required this.session,
  });

  final MockNotificationRepository repo;
  final SessionController session;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = false;
  String? _error;
  List<_Row> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = widget.session.state.email ?? '';
      final items = await widget.repo.listForUser(userId);
      if (!mounted) return;
      setState(() => _items = items.map((n) => _Row(n.id, n.title, n.body, n.readAt != null)).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _markRead(String id) async {
    await widget.repo.markRead(notificationId: id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Error: $_error'))
                : _items.isEmpty
                    ? const Center(child: Text('No notifications yet.'))
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final n = _items[i];
                          return ListTile(
                            title: Text(n.title),
                            subtitle: Text(n.body),
                            leading: Icon(n.read ? Icons.mark_email_read : Icons.notifications),
                            onTap: n.read ? null : () => _markRead(n.id),
                          );
                        },
                      ),
      ),
    );
  }
}

class _Row {
  _Row(this.id, this.title, this.body, this.read);
  final String id;
  final String title;
  final String body;
  final bool read;
}


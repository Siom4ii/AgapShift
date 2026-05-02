import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/models.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../theme/agap_colors.dart';

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

enum _Filter { all, jobs, payments }

enum _NotifKind { gig, payment, rating, verification, generic }

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = false;
  String? _error;
  List<_NotifItem> _items = const [];
  _Filter _filter = _Filter.all;

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
      final userId = appActorId(widget.session, mockFallback: '');
      final raw = await widget.repo.listForUser(userId);
      if (!mounted) return;
      final mapped = raw.map((n) => _NotifItem.fromModel(n)).toList();
      setState(() => _items = _mergeWithDemos(mapped, userId));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<_NotifItem> _filtered(List<_NotifItem> all) {
    return all.where((n) {
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.jobs:
          return n.kind == _NotifKind.gig || n.kind == _NotifKind.rating || n.kind == _NotifKind.verification;
        case _Filter.payments:
          return n.kind == _NotifKind.payment;
      }
    }).toList();
  }

  Future<void> _markRead(String id) async {
    await widget.repo.markRead(notificationId: id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filtered(_items);
    return Scaffold(
      backgroundColor: AgapColors.pageBackground,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AgapColors.pageBackground,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'AgapShift',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AgapColors.primaryBright,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AgapColors.mintSurface,
              child: Icon(Icons.person_rounded, color: AgapColors.primary, size: 20),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Error: $_error'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Text(
                          'Notifications',
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            _FilterChip(
                              label: 'All',
                              selected: _filter == _Filter.all,
                              onTap: () => setState(() => _filter = _Filter.all),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Jobs',
                              selected: _filter == _Filter.jobs,
                              onTap: () => setState(() => _filter = _Filter.jobs),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Payments',
                              selected: _filter == _Filter.payments,
                              onTap: () => setState(() => _filter = _Filter.payments),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: visible.isEmpty
                            ? Center(
                                child: Text(
                                  'No notifications in this category.',
                                  style: GoogleFonts.inter(color: AgapColors.textMuted),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                                  itemCount: visible.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (context, i) {
                                    final n = visible[i];
                                    return _NotificationCard(
                                      item: n,
                                      onTap: n.isPersisted && !n.read ? () => _markRead(n.id) : null,
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AgapColors.primary : const Color(0xFFE5E7EB),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: selected ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotifItem {
  _NotifItem({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    required this.read,
    required this.kind,
    required this.isPersisted,
    this.highlightPeso,
  });

  final String id;
  final String title;
  final String body;
  final DateTime at;
  final bool read;
  final _NotifKind kind;
  final bool isPersisted;
  final String? highlightPeso;

  factory _NotifItem.fromModel(AppNotification n) {
    final kind = _kindFromStrings(n.title, n.body, n.data);
    final highlight = _extractPeso(n.title, n.body);
    return _NotifItem(
      id: n.id,
      title: n.title,
      body: n.body,
      at: n.createdAt.toLocal(),
      read: n.readAt != null,
      kind: kind,
      isPersisted: true,
      highlightPeso: highlight,
    );
  }

  static _NotifKind _kindFromStrings(String title, String body, Map<String, String>? data) {
    final k = data?['kind']?.toLowerCase();
    if (k == 'payment' || k == 'payments') return _NotifKind.payment;
    if (k == 'gig' || k == 'job') return _NotifKind.gig;
    if (k == 'rating') return _NotifKind.rating;
    if (k == 'verification') return _NotifKind.verification;
    final t = '${title.toLowerCase()} ${body.toLowerCase()}';
    if (t.contains('payment') || t.contains('paid') || t.contains('₱') || t.contains('peso') || t.contains('withdraw')) {
      return _NotifKind.payment;
    }
    if (t.contains('rating') || t.contains('star')) return _NotifKind.rating;
    if (t.contains('verif')) return _NotifKind.verification;
    if (t.contains('gig') || t.contains('shift') || t.contains('job')) return _NotifKind.gig;
    return _NotifKind.generic;
  }

  static String? _extractPeso(String title, String body) {
    final regex = RegExp(r'₱\s*[\d,]+(?:\.\d{2})?');
    final m = regex.firstMatch('$title $body');
    return m?.group(0);
  }
}

List<_NotifItem> _mergeWithDemos(List<_NotifItem> mapped, String userId) {
  if (mapped.length >= 4) return mapped;
  final demos = _demoItems(userId);
  final ids = mapped.map((e) => e.id).toSet();
  final out = [...mapped];
  for (final d in demos) {
    if (out.length >= 6) break;
    if (!ids.contains(d.id)) out.add(d);
  }
  return out;
}

List<_NotifItem> _demoItems(String userId) {
  final now = DateTime.now();
  return [
    _NotifItem(
      id: 'demo_gig_$userId',
      title: 'New Gig Nearby: Warehouse Assistant',
      body: 'A new role matching your skills was posted 2 km away.',
      at: now.subtract(const Duration(minutes: 10)),
      read: false,
      kind: _NotifKind.gig,
      isPersisted: false,
    ),
    _NotifItem(
      id: 'demo_pay_$userId',
      title: 'Payment Received: ₱5,250.00',
      body: 'Your shift payment has been released to your wallet.',
      at: now.subtract(const Duration(hours: 2)),
      read: true,
      kind: _NotifKind.payment,
      isPersisted: false,
      highlightPeso: '₱5,250.00',
    ),
    _NotifItem(
      id: 'demo_rate_$userId',
      title: 'Rating Received: 5 stars from Logistics Hub',
      body: '"Great communication and on time every day."',
      at: now.subtract(const Duration(days: 1)),
      read: true,
      kind: _NotifKind.rating,
      isPersisted: false,
    ),
    _NotifItem(
      id: 'demo_ver_$userId',
      title: 'Verification Successful',
      body: 'Your profile is verified. You can now apply to all gigs.',
      at: now.subtract(const Duration(days: 2)),
      read: true,
      kind: _NotifKind.verification,
      isPersisted: false,
    ),
  ];
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, this.onTap});

  final _NotifItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, icon, iconColor) = switch (item.kind) {
      _NotifKind.gig => (const Color(0xFFDBEAFE), Icons.work_outline_rounded, const Color(0xFF1D4ED8)),
      _NotifKind.payment => (AgapColors.mintSurface, Icons.payments_rounded, AgapColors.primary),
      _NotifKind.rating => (const Color(0xFFFFFBEB), Icons.star_rounded, const Color(0xFFD97706)),
      _NotifKind.verification => (const Color(0xFFE0F2FE), Icons.verified_user_outlined, const Color(0xFF0369A1)),
      _NotifKind.generic => (const Color(0xFFF3F4F6), Icons.notifications_none_rounded, AgapColors.textMuted),
    };

    final baseTitleStyle = GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: const Color(0xFF0F172A));
    final peso = item.highlightPeso;
    Widget titleWidget;
    if (peso != null && item.title.contains(peso)) {
      final i = item.title.indexOf(peso);
      titleWidget = Text.rich(
        TextSpan(
          style: baseTitleStyle,
          children: [
            TextSpan(text: item.title.substring(0, i)),
            TextSpan(
              text: peso,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AgapColors.primaryBright,
              ),
            ),
            TextSpan(text: item.title.substring(i + peso.length)),
          ],
        ),
      );
    } else {
      titleWidget = Text(item.title, style: baseTitleStyle);
    }

    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AgapColors.borderSubtle),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (!item.read)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleWidget,
                        const SizedBox(height: 6),
                        Text(
                          item.body,
                          style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: AgapColors.textMuted),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _timeAgo(item.at),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AgapColors.textMuted.withValues(alpha: 0.85),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'JUST NOW';
  if (d.inMinutes < 60) return '${d.inMinutes} MINS AGO';
  if (d.inHours < 24) return '${d.inHours} HRS AGO';
  if (d.inDays < 7) return '${d.inDays} DAYS AGO';
  return '${t.day}/${t.month}/${t.year}';
}

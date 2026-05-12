import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../notifications/notification_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../theme/agap_colors.dart';
import '../marketplace/worker_gig_details_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.repo,
    required this.session,
  });

  final NotificationRepository repo;
  final SessionController session;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

enum _Filter { all, jobs, payments }

enum _NotifKind { gig, payment, rating, verification, generic }

enum _NotifTone { hire, apply, payment, rating, verification, gig, generic }

sealed class _NotifRow {}

final class _NotifSectionHeader extends _NotifRow {
  _NotifSectionHeader(this.label);
  final String label;
}

final class _NotifEntry extends _NotifRow {
  _NotifEntry(this.item);
  final _NotifItem item;
}

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
      setState(() => _items = mapped);
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
          return n.kind == _NotifKind.gig ||
              n.kind == _NotifKind.rating ||
              n.kind == _NotifKind.verification;
        case _Filter.payments:
          return n.kind == _NotifKind.payment;
      }
    }).toList();
  }

  int _unreadCount(List<_NotifItem> items) => items.where((e) => !e.read).length;

  List<_NotifRow> _rowsFor(List<_NotifItem> visible) {
    if (visible.isEmpty) return const [];
    final sorted = [...visible]..sort((a, b) => b.at.compareTo(a.at));
    final out = <_NotifRow>[];
    String? lastBucket;
    for (final n in sorted) {
      final bucket = _calendarBucketLabel(n.at);
      if (bucket != lastBucket) {
        out.add(_NotifSectionHeader(bucket));
        lastBucket = bucket;
      }
      out.add(_NotifEntry(n));
    }
    return out;
  }

  String _calendarBucketLabel(DateTime local) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(local.year, local.month, local.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    final diffDays = today.difference(d).inDays;
    if (diffDays >= 2 && diffDays < 7) return 'Earlier this week';
    if (local.year == now.year && local.month == now.month) return 'This month';
    if (local.year == now.year) return 'Earlier this year';
    return 'Older';
  }

  Future<void> _markRead(String id) async {
    await widget.repo.markRead(notificationId: id);
    await _load();
  }

  Future<void> _openGigIfPossible(BuildContext context, String gigId) async {
    final scope = MarketplaceScope.tryOf(context);
    if (scope == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open this job from the Jobs tab in the app.'),
        ),
      );
      return;
    }
    if (scope.session.state.role == UserRole.worker) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkerGigDetailsScreen(
            repo: scope.repo,
            notifications: scope.notifications,
            session: scope.session,
            gigId: gigId,
          ),
        ),
      );
      if (mounted) await _load();
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Open this post from My job posts in your dashboard.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filtered(_items);
    final unread = _unreadCount(visible);
    final rows = _rowsFor(visible);

    return Scaffold(
      backgroundColor: const Color(0xFFEEF1F5),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFEEF1F5),
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error: $_error',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _NotificationsHero(
                        unread: unread,
                        total: visible.length,
                      ),
                      SizedBox(
                        height: 44,
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
                              onTap: () =>
                                  setState(() => _filter = _Filter.payments),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: visible.isEmpty
                            ? _EmptyNotificationsState(
                                onClearFilter: _filter != _Filter.all
                                    ? () => setState(() => _filter = _Filter.all)
                                    : null,
                              )
                            : RefreshIndicator(
                                color: AgapColors.primaryBright,
                                onRefresh: _load,
                                child: CustomScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  slivers: [
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        4,
                                        16,
                                        28,
                                      ),
                                      sliver: SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (context, i) {
                                            final row = rows[i];
                                            if (row is _NotifSectionHeader) {
                                              return _SectionHeading(
                                                label: row.label,
                                              );
                                            }
                                            if (row is _NotifEntry) {
                                              final n = row.item;
                                              final card = _NotificationCard(
                                                item: n,
                                                onMarkRead: n.isPersisted &&
                                                        !n.read
                                                    ? () => _markRead(n.id)
                                                    : null,
                                                onViewGig:
                                                    n.gigId != null &&
                                                            n.gigId!.isNotEmpty
                                                        ? () =>
                                                            _openGigIfPossible(
                                                              context,
                                                              n.gigId!,
                                                            )
                                                        : null,
                                              );
                                              final wrapped = n.isPersisted &&
                                                      !n.read
                                                  ? Dismissible(
                                                      key: ValueKey<String>(
                                                        'notif_${n.id}',
                                                      ),
                                                      direction: DismissDirection
                                                          .endToStart,
                                                      confirmDismiss: (_) async {
                                                        await widget.repo
                                                            .markRead(
                                                          notificationId: n.id,
                                                        );
                                                        if (mounted) {
                                                          await _load();
                                                        }
                                                        return false;
                                                      },
                                                      background: Container(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        padding:
                                                            const EdgeInsets.only(
                                                          right: 22,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            20,
                                                          ),
                                                          color: AgapColors
                                                              .primaryBright
                                                              .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .end,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .mark_email_read_outlined,
                                                              color: AgapColors
                                                                  .primaryBright,
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Text(
                                                              'Mark read',
                                                              style: GoogleFonts
                                                                  .inter(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                color: AgapColors
                                                                    .primaryBright,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      child: card,
                                                    )
                                                  : card;
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 10,
                                                ),
                                                child: wrapped,
                                              )
                                                  .animate()
                                                  .fadeIn(
                                                    duration: 220.ms,
                                                    delay: (12 * i).ms,
                                                  )
                                                  .slideY(
                                                    begin: 0.04,
                                                    curve: Curves.easeOutCubic,
                                                  );
                                            }
                                            return const SizedBox.shrink();
                                          },
                                          childCount: rows.length,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _NotificationsHero extends StatelessWidget {
  const _NotificationsHero({
    required this.unread,
    required this.total,
  });

  final int unread;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              AgapColors.mintSurface.withValues(alpha: 0.65),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          boxShadow: [
            BoxShadow(
              color: AgapColors.primary.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications',
              style: GoogleFonts.inter(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                height: 1.05,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            if (total == 0)
              Text(
                'You are all caught up.',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AgapColors.textMuted,
                ),
              )
            else
              Row(
                children: [
                  if (unread > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AgapColors.primaryBright,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: AgapColors.primaryBright.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        '$unread new',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      unread > 0
                          ? 'Swipe a new notification left to mark it read — or tap it once.'
                          : 'Everything in this list has been read.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AgapColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          color: AgapColors.textMuted.withValues(alpha: 0.85),
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
    return AnimatedScale(
      scale: selected ? 1.02 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected ? AgapColors.primary : Colors.white,
              border: Border.all(
                color: selected
                    ? AgapColors.primary
                    : const Color(0xFFD1D5DB),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AgapColors.primaryBright.withValues(
                          alpha: 0.35,
                        ),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: selected ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyNotificationsState extends StatelessWidget {
  const _EmptyNotificationsState({this.onClearFilter});

  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: AgapColors.primary.withValues(alpha: 0.1),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                Icons.notifications_off_outlined,
                size: 42,
                color: AgapColors.primaryBright,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Nothing here yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              onClearFilter != null
                  ? 'Try switching back to All, or check again after new activity on your account.'
                  : 'When you apply, get hired, or receive payments, updates will land here with clear actions.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AgapColors.textMuted,
              ),
            ),
            if (onClearFilter != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onClearFilter,
                style: FilledButton.styleFrom(
                  backgroundColor: AgapColors.primaryBright,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
                child: Text(
                  'Show all notifications',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
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
    required this.tone,
    this.highlightPeso,
    this.data,
  });

  final String id;
  final String title;
  final String body;
  final DateTime at;
  final bool read;
  final _NotifKind kind;
  final _NotifTone tone;
  final bool isPersisted;
  final String? highlightPeso;
  final Map<String, String>? data;

  String? get gigId => data?['gigId'] ?? data?['gig_id'];

  factory _NotifItem.fromModel(AppNotification n) {
    final kind = _kindFromStrings(n.title, n.body, n.data);
    final tone = _toneFromStrings(n.title, n.body, kind);
    final highlight = _extractPeso(n.title, n.body);
    return _NotifItem(
      id: n.id,
      title: n.title,
      body: n.body,
      at: n.createdAt.toLocal(),
      read: n.readAt != null,
      kind: kind,
      tone: tone,
      isPersisted: true,
      highlightPeso: highlight,
      data: n.data,
    );
  }

  static _NotifKind _kindFromStrings(
    String title,
    String body,
    Map<String, String>? data,
  ) {
    final k = data?['kind']?.toLowerCase();
    if (k == 'payment' || k == 'payments') return _NotifKind.payment;
    if (k == 'gig' || k == 'job') return _NotifKind.gig;
    if (k == 'rating') return _NotifKind.rating;
    if (k == 'verification') return _NotifKind.verification;
    final t = '${title.toLowerCase()} ${body.toLowerCase()}';
    if (t.contains('payment') ||
        t.contains('paid') ||
        t.contains('₱') ||
        t.contains('peso') ||
        t.contains('withdraw')) {
      return _NotifKind.payment;
    }
    if (t.contains('rating') || t.contains('star')) return _NotifKind.rating;
    if (t.contains('verif')) return _NotifKind.verification;
    if (t.contains('gig') ||
        t.contains('shift') ||
        t.contains('job') ||
        t.contains('hired') ||
        t.contains('applicant')) {
      return _NotifKind.gig;
    }
    return _NotifKind.generic;
  }

  static _NotifTone _toneFromStrings(
    String title,
    String body,
    _NotifKind kind,
  ) {
    final t = title.toLowerCase();
    if (t.contains('hired') || t.contains('selected')) return _NotifTone.hire;
    if (t.contains('application sent') ||
        t.contains('applied') ||
        t.contains('new applicant')) {
      return _NotifTone.apply;
    }
    if (kind == _NotifKind.payment) return _NotifTone.payment;
    if (kind == _NotifKind.rating) return _NotifTone.rating;
    if (kind == _NotifKind.verification) return _NotifTone.verification;
    if (kind == _NotifKind.gig) return _NotifTone.gig;
    return _NotifTone.generic;
  }

  static String? _extractPeso(String title, String body) {
    final regex = RegExp(r'₱\s*[\d,]+(?:\.\d{2})?');
    final m = regex.firstMatch('$title $body');
    return m?.group(0);
  }
}

class _NotifDisplay {
  const _NotifDisplay({
    required this.headline,
    required this.subline,
    this.emoji,
  });

  final String headline;
  final String subline;
  final String? emoji;
}

_NotifDisplay _displayFor(_NotifItem item) {
  final t = item.title.toLowerCase();
  final b = item.body.trim();
  if (t.contains('you were hired') || t.contains('you got hired')) {
    return _NotifDisplay(
      headline: 'You got hired!',
      subline: b.isNotEmpty ? b : 'Open the job to see next steps.',
      emoji: '🎉',
    );
  }
  if (t.contains('application sent')) {
    return _NotifDisplay(
      headline: 'Application sent',
      subline: b.isNotEmpty ? b : 'We will let you know when the employer responds.',
      emoji: '👍',
    );
  }
  if (t.contains('new applicant')) {
    return _NotifDisplay(
      headline: 'New applicant',
      subline: b.isNotEmpty ? b : 'Someone applied to your job post.',
      emoji: '✨',
    );
  }
  if (t.contains('application update') || t.contains('not selected')) {
    return _NotifDisplay(
      headline: 'Application update',
      subline: b.isNotEmpty ? b : 'Thanks for applying — another role may be a better fit.',
      emoji: '💬',
    );
  }
  if (t.contains('rating') || t.contains('rated')) {
    return _NotifDisplay(
      headline: 'New feedback',
      subline: b.isNotEmpty ? b : 'Someone left a rating on your work.',
      emoji: '⭐',
    );
  }
  if (t.contains('payment') || t.contains('paid') || t.contains('released')) {
    return _NotifDisplay(
      headline: 'Payment activity',
      subline: b.isNotEmpty ? b : 'There is an update on your wallet activity.',
      emoji: '💸',
    );
  }
  if (t.contains('verif')) {
    return _NotifDisplay(
      headline: 'Verification',
      subline: b.isNotEmpty ? b : 'Your verification status changed.',
      emoji: '✅',
    );
  }
  return _NotifDisplay(headline: item.title, subline: item.body, emoji: null);
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    this.onMarkRead,
    this.onViewGig,
  });

  final _NotifItem item;
  final VoidCallback? onMarkRead;
  final VoidCallback? onViewGig;

  @override
  Widget build(BuildContext context) {
    final display = _displayFor(item);
    final scheme = _toneScheme(item.tone);
    final peso = item.highlightPeso;
    final baseTitleStyle = GoogleFonts.inter(
      fontWeight: FontWeight.w900,
      fontSize: 16,
      height: 1.2,
      color: const Color(0xFF0F172A),
    );

    Widget headline = Text(
      display.headline,
      style: baseTitleStyle,
    );
    if (peso != null && display.headline.contains(peso)) {
      final i = display.headline.indexOf(peso);
      headline = Text.rich(
        TextSpan(
          style: baseTitleStyle,
          children: [
            TextSpan(text: display.headline.substring(0, i)),
            TextSpan(
              text: peso,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AgapColors.primaryBright,
              ),
            ),
            TextSpan(text: display.headline.substring(i + peso.length)),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onMarkRead,
        splashColor: scheme.accent.withValues(alpha: 0.12),
        highlightColor: scheme.accent.withValues(alpha: 0.06),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: scheme.cardGradient,
            ),
            border: Border.all(color: scheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: scheme.accent.withValues(alpha: 0.06),
                blurRadius: 0,
                spreadRadius: 0,
                offset: Offset.zero,
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: scheme.iconGradient,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.accent.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(scheme.icon, color: scheme.iconFg, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (display.emoji != null) ...[
                              Text(
                                display.emoji!,
                                style: const TextStyle(fontSize: 17),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(child: headline),
                          ],
                        ),
                        if (display.subline.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            display.subline,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF475569),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          _timeAgo(item.at),
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.15,
                            color: AgapColors.textMuted.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!item.read)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        'New',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                ],
              ),
              if (onViewGig != null || onMarkRead != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onViewGig != null)
                      OutlinedButton.icon(
                        onPressed: onViewGig,
                        icon: const Icon(Icons.work_outline_rounded, size: 18),
                        label: Text(
                          'View job',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AgapColors.primaryBright,
                          side: BorderSide(
                            color: AgapColors.primaryBright.withValues(
                              alpha: 0.45,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    if (onMarkRead != null)
                      TextButton.icon(
                        onPressed: onMarkRead,
                        icon: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                          color: AgapColors.textMuted.withValues(alpha: 0.9),
                        ),
                        label: Text(
                          'Mark read',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            color: AgapColors.textMuted.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToneScheme {
  const _ToneScheme({
    required this.cardGradient,
    required this.border,
    required this.iconGradient,
    required this.icon,
    required this.iconFg,
    required this.accent,
  });

  final List<Color> cardGradient;
  final Color border;
  final List<Color> iconGradient;
  final IconData icon;
  final Color iconFg;
  final Color accent;
}

_ToneScheme _toneScheme(_NotifTone tone) {
  switch (tone) {
    case _NotifTone.hire:
      return _ToneScheme(
        cardGradient: [
          Colors.white,
          const Color(0xFFE8F8F0),
        ],
        border: const Color(0xFFC8EAD9),
        iconGradient: [
          AgapColors.primaryBright,
          AgapColors.primary,
        ],
        icon: Icons.celebration_rounded,
        iconFg: Colors.white,
        accent: AgapColors.primaryBright,
      );
    case _NotifTone.apply:
      return _ToneScheme(
        cardGradient: [
          Colors.white,
          const Color(0xFFEFF6FF),
        ],
        border: const Color(0xFFBFDBFE),
        iconGradient: [
          const Color(0xFF60A5FA),
          const Color(0xFF2563EB),
        ],
        icon: Icons.send_rounded,
        iconFg: Colors.white,
        accent: const Color(0xFF2563EB),
      );
    case _NotifTone.payment:
      return _ToneScheme(
        cardGradient: [
          Colors.white,
          const Color(0xFFFFFBEB),
        ],
        border: const Color(0xFFFDE68A),
        iconGradient: [
          const Color(0xFFFBBF24),
          const Color(0xFFD97706),
        ],
        icon: Icons.payments_rounded,
        iconFg: Colors.white,
        accent: const Color(0xFFD97706),
      );
    case _NotifTone.rating:
      return _ToneScheme(
        cardGradient: [
          Colors.white,
          const Color(0xFFFFF7ED),
        ],
        border: const Color(0xFFFED7AA),
        iconGradient: [
          const Color(0xFFF97316),
          const Color(0xFFEA580C),
        ],
        icon: Icons.star_rounded,
        iconFg: Colors.white,
        accent: const Color(0xFFEA580C),
      );
    case _NotifTone.verification:
      return _ToneScheme(
        cardGradient: [
          Colors.white,
          const Color(0xFFE0F2FE),
        ],
        border: const Color(0xFFBAE6FD),
        iconGradient: [
          const Color(0xFF38BDF8),
          const Color(0xFF0284C7),
        ],
        icon: Icons.verified_user_outlined,
        iconFg: Colors.white,
        accent: const Color(0xFF0284C7),
      );
    case _NotifTone.gig:
      return _ToneScheme(
        cardGradient: [
          Colors.white,
          const Color(0xFFEEF2FF),
        ],
        border: const Color(0xFFC7D2FE),
        iconGradient: [
          const Color(0xFF818CF8),
          const Color(0xFF4338CA),
        ],
        icon: Icons.work_outline_rounded,
        iconFg: Colors.white,
        accent: const Color(0xFF4338CA),
      );
    case _NotifTone.generic:
      return _ToneScheme(
        cardGradient: [
          Colors.white,
          const Color(0xFFF8FAFC),
        ],
        border: const Color(0xFFE2E8F0),
        iconGradient: [
          const Color(0xFF94A3B8),
          const Color(0xFF64748B),
        ],
        icon: Icons.notifications_none_rounded,
        iconFg: Colors.white,
        accent: const Color(0xFF64748B),
      );
  }
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} minutes ago';
  if (d.inHours < 24) return '${d.inHours} hours ago';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return '${t.month}/${t.day}/${t.year}';
}

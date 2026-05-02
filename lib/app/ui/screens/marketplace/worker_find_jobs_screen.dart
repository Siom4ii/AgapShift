import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import 'worker_gig_details_screen.dart';

class WorkerFindJobsScreen extends StatefulWidget {
  const WorkerFindJobsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.session,
  });

  final MarketplaceRepository repo;
  final MockNotificationRepository notifications;
  final SessionController session;

  @override
  State<WorkerFindJobsScreen> createState() => _WorkerFindJobsScreenState();
}

class _WorkerFindJobsScreenState extends State<WorkerFindJobsScreen> {
  static const _categories = <_CategorySpec>[
    _CategorySpec(label: 'All', key: ''),
    _CategorySpec(label: 'Warehouse', key: 'warehouse'),
    _CategorySpec(label: 'Food Service', key: 'food'),
    _CategorySpec(label: 'Retail', key: 'retail'),
    _CategorySpec(label: 'Events', key: 'event'),
  ];

  final _search = TextEditingController();
  String _selectedCategoryKey = '';
  bool _loading = false;
  String? _error;

  List<Gig> _items = const [];
  int _unread = 0;

  GeoPoint get _center => const GeoPoint(lat: 14.5995, lng: 120.9842);

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repo.listNearbyGigs(
        center: _center,
        radiusMeters: 10000,
      );
      final uid = appActorId(widget.session, mockFallback: '');
      final notifs = uid.isEmpty
          ? <AppNotification>[]
          : await widget.notifications.listForUser(uid);
      final unread = notifs.where((n) => n.readAt == null).length;

      if (!mounted) return;
      setState(() {
        _items = items;
        _unread = unread == 0 ? 2 : unread; // keep mock-like badge in demo
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Gig> get _filtered {
    final q = _search.text.trim().toLowerCase();
    final cat = _selectedCategoryKey;
    return _items.where((g) {
      if (cat.isNotEmpty && !g.category.toLowerCase().contains(cat))
        return false;
      if (q.isEmpty) return true;
      return g.title.toLowerCase().contains(q) ||
          g.addressLabel.toLowerCase().contains(q) ||
          g.category.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final count = _filtered.length;
    return ShellChromeBackground(
      kind: ShellChromeKind.worker,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find Jobs',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: AgapColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Pasay City, Metro Manila',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: AgapColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _NotifButton(
                  unread: _unread,
                  onTap: () async {
                    // The shell app bar already routes to Notifications. This keeps the mock icon usable.
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Open notifications from the top bar.'),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SearchField(controller: _search),
            const SizedBox(height: 14),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, i) {
                  final spec = _categories[i];
                  final selected = spec.key == _selectedCategoryKey;
                  return _Chip(
                    label: spec.label,
                    selected: selected,
                    onTap: () =>
                        setState(() => _selectedCategoryKey = spec.key),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemCount: _categories.length,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  _loading ? 'Loading jobs…' : '$count jobs found near you',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AgapColors.textMuted,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Text(
                    '$count matches',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              _ErrorCard(message: _error!, onRetry: _load)
            else if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 44),
                child: Center(
                  child: Text(
                    'No open jobs nearby yet.',
                    style: GoogleFonts.inter(
                      color: AgapColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else
              ...List.generate(math.min(_filtered.length, 10), (i) {
                final g = _filtered[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ShellStaggerItem(
                    index: i,
                    child: ShellLift(
                      child: _JobCard(
                        gig: g,
                        distanceKm:
                            _distanceMeters(_center, g.location) / 1000.0,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => WorkerGigDetailsScreen(
                                repo: widget.repo,
                                notifications: widget.notifications,
                                session: widget.session,
                                gigId: g.id,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _CategorySpec {
  const _CategorySpec({required this.label, required this.key});
  final String label;
  final String key;
}

class _NotifButton extends StatelessWidget {
  const _NotifButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Ink(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AgapColors.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications_outlined,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        if (unread > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: AgapColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Search jobs, companies…',
                hintStyle: GoogleFonts.inter(color: AgapColors.textMuted),
                border: InputBorder.none,
                isDense: true,
              ),
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
          if (controller.text.trim().isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              onPressed: () => controller.clear(),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF6D28D9) : Colors.white;
    final fg = selected ? Colors.white : const Color(0xFF374151);
    final border = selected
        ? Colors.transparent
        : AgapColors.borderSubtle.withValues(alpha: 0.75);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.gig,
    required this.distanceKm,
    required this.onTap,
  });

  final Gig gig;
  final double distanceKm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final totalPhp = (gig.pay.amount / 100.0).round();
    final hours = math.max(
      1,
      gig.endAt.difference(gig.startAt).inMinutes ~/ 60,
    );
    final start = gig.startAt.toLocal();
    final dayLabel = _dayLabel(start);
    final time = _clock(start);

    final urgency = _badgeForGig(gig.id);
    final secondary = _secondaryBadgeForGig(gig.id);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AgapColors.borderSubtle.withValues(alpha: 0.9),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LeadingIcon(category: gig.category),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gig.title,
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _companyFromBusinessId(gig.businessId),
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₱$totalPhp',
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: AgapColors.primaryBright,
                        ),
                      ),
                      Text(
                        gig.category.toLowerCase().contains('event')
                            ? '/event'
                            : '/day',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AgapColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _Meta(
                    icon: Icons.route_rounded,
                    text: '${distanceKm.toStringAsFixed(1)} km',
                  ),
                  _Meta(icon: Icons.schedule_rounded, text: '$hours hrs'),
                  _Meta(
                    icon: Icons.event_available_rounded,
                    text: '$dayLabel $time',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (urgency != null)
                    _Pill(
                      text: urgency.$1,
                      bg: urgency.$2,
                      fg: urgency.$3,
                      icon: urgency.$4,
                    ),
                  if (secondary != null)
                    _Pill(
                      text: secondary.$1,
                      bg: secondary.$2,
                      fg: secondary.$3,
                      icon: secondary.$4,
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

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    final l = category.toLowerCase();
    final icon = l.contains('warehouse')
        ? Icons.inventory_2_rounded
        : l.contains('food')
        ? Icons.restaurant_rounded
        : l.contains('retail')
        ? Icons.storefront_rounded
        : l.contains('event')
        ? Icons.celebration_rounded
        : Icons.work_rounded;
    final tint = l.contains('warehouse')
        ? const Color(0xFFEDE9FE)
        : l.contains('food')
        ? const Color(0xFFFFE4E6)
        : l.contains('retail')
        ? const Color(0xFFFFF7ED)
        : const Color(0xFFE0F2FE);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: const Color(0xFF334155), size: 22),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AgapColors.textMuted),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AgapColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.bg,
    required this.fg,
    required this.icon,
  });
  final String text;
  final Color bg;
  final Color fg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: Colors.red.shade800,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

String _companyFromBusinessId(String id) {
  if (id.isEmpty) return 'Verified Business';
  final local = id.split('@').first;
  final words = local
      .split(RegExp(r'[._-]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'Verified Business';
  final titled = words
      .map((w) => '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1) : ''}')
      .join(' ');
  return '$titled Logistics';
}

int _distanceMeters(GeoPoint a, GeoPoint b) {
  final dx = (a.lat - b.lat) * 111000.0;
  final dy = (a.lng - b.lng) * 111000.0;
  return math.sqrt(dx * dx + dy * dy).round();
}

String _clock(DateTime d) {
  final h = d.hour;
  final am = h >= 12 ? 'PM' : 'AM';
  final hr = h % 12 == 0 ? 12 : h % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$hr:$m $am';
}

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
  return '${d.month}/${d.day}';
}

// Returns (text, bg, fg, icon)
(String, Color, Color, IconData)? _badgeForGig(String id) {
  final h = id.hashCode.abs() % 4;
  if (h == 0)
    return (
      'Urgent',
      const Color(0xFFFFE4E6),
      const Color(0xFFB91C1C),
      Icons.local_fire_department_rounded,
    );
  if (h == 1)
    return (
      'Today Only',
      const Color(0xFFFFEDD5),
      const Color(0xFF9A3412),
      Icons.warning_amber_rounded,
    );
  return null;
}

(String, Color, Color, IconData)? _secondaryBadgeForGig(String id) {
  final h = id.hashCode.abs() % 6;
  if (h == 0)
    return (
      '2 slots left',
      const Color(0xFFEFF6FF),
      const Color(0xFF1D4ED8),
      Icons.people_alt_rounded,
    );
  if (h == 1)
    return (
      '1 slots left',
      const Color(0xFFEFF6FF),
      const Color(0xFF1D4ED8),
      Icons.people_alt_rounded,
    );
  if (h == 2)
    return (
      'Applied',
      const Color(0xFFDCFCE7),
      const Color(0xFF166534),
      Icons.check_circle_rounded,
    );
  if (h == 3)
    return (
      '5 slots left',
      const Color(0xFFEFF6FF),
      const Color(0xFF1D4ED8),
      Icons.people_alt_rounded,
    );
  return null;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/business_identity.dart';
import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../location/davao_del_sur_scope.dart';
import '../../../location/geo_distance.dart';
import '../../../location/user_geo_point.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../notifications/notification_repository.dart';
import '../../../ratings/mock_ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../notifications/notifications_screen.dart';
import 'worker_gig_details_screen.dart';

/// Worker **Home**: dashboard (greeting, stats, active shift, quick actions,
/// nearby jobs). Map lives on [WorkerFindJobsScreen].
class WorkerGigsScreen extends StatefulWidget {
  const WorkerGigsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.session,
    required this.shift,
    required this.ratings,
    required this.onOpenFindJobs,
    required this.onOpenMyShift,
  });

  final MarketplaceRepository repo;
  final NotificationRepository notifications;
  final SessionController session;
  final ShiftRepository shift;
  final MockRatingsRepository ratings;
  final VoidCallback onOpenFindJobs;
  final VoidCallback onOpenMyShift;

  @override
  State<WorkerGigsScreen> createState() => _WorkerGigsScreenState();
}

class _WorkerGigsScreenState extends State<WorkerGigsScreen> {
  bool _loading = true;
  String? _error;

  List<Gig> _nearby = const [];
  int _unread = 0;
  Map<String, String> _businessNames = const {};
  double _ratingAvg = 0;
  int _completedShifts = 0;
  int _appliedJobs = 0;
  _ActiveShiftSnap? _active;

  GeoPoint _anchor = DavaoDelSurScope.defaultCenter;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final g = await tryGetCurrentUserGeoPoint();
    if (!mounted) return;
    if (g != null && DavaoDelSurScope.contains(g)) {
      setState(() => _anchor = g);
    }
    await _load();
  }

  Future<Map<String, String>> _fetchBusinessNames(Iterable<String> ids) async {
    final unique = ids.toSet().where((e) => e.isNotEmpty).toList();
    final out = <String, String>{for (final id in unique) id: 'Business'};
    if (!SupabaseConfig.isConfigured || unique.isEmpty) return out;
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id,identity_snapshot')
          .inFilter('id', unique);
      for (final raw in rows as List<dynamic>) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = m['id'] as String?;
        if (id == null) continue;
        final biz = businessIdentityFromProfileIdentitySnapshot(
          m['identity_snapshot'],
        );
        if (biz != null && biz.displayName.trim().isNotEmpty) {
          out[id] = biz.displayName.trim();
        }
      }
    } catch (_) {}
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final workerId = appActorId(widget.session, mockFallback: 'worker');
      final items = await widget.repo.listOpenJobsFeed(sortCenter: _anchor);
      final apps = await widget.repo.listApplications();
      final applied = apps.where((a) => a.workerId == workerId).length;
      final sessions = await widget.shift.listShiftSessions();
      final completed = sessions
          .where((s) => s.workerId == workerId && s.checkOutAt != null)
          .length;
      final rating = workerId.isEmpty ? 0.0 : await widget.ratings.averageForUser(workerId);

      final notifs = workerId.isEmpty
          ? <AppNotification>[]
          : await widget.notifications.listForUser(workerId);
      final unread = notifs.where((n) => n.readAt == null).length;

      final bizIds = items.map((g) => g.businessId).toSet();
      for (final a in apps) {
        if (a.workerId != workerId || a.status != ApplicationStatus.hired) {
          continue;
        }
        if (!items.any((g) => g.id == a.gigId)) {
          final hg = await widget.repo.getGig(a.gigId);
          if (hg != null) bizIds.add(hg.businessId);
        }
      }
      final names = await _fetchBusinessNames(bizIds);
      final active = await _resolveActiveShift(
        workerId,
        apps,
        items,
        sessions,
        names,
      );

      if (!mounted) return;
      setState(() {
        _nearby = items;
        _businessNames = names;
        _unread = unread;
        _ratingAvg = rating;
        _completedShifts = completed;
        _appliedJobs = applied;
        _active = active;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<_ActiveShiftSnap?> _resolveActiveShift(
    String workerId,
    List<GigApplication> apps,
    List<Gig> gigPool,
    List<ShiftSession> sessions,
    Map<String, String> businessNames,
  ) async {
    if (workerId.isEmpty) return null;
    final hiredIds = apps
        .where(
          (a) => a.workerId == workerId && a.status == ApplicationStatus.hired,
        )
        .map((a) => a.gigId)
        .toSet();
    final byId = {for (final g in gigPool) g.id: g};
    for (final gid in hiredIds) {
      var g = byId[gid];
      g ??= await widget.repo.getGig(gid);
      if (g == null || g.status == GigStatus.cancelled) continue;
      ShiftSession? mine;
      for (final s in sessions) {
        if (s.gigId == gid && s.workerId == workerId) {
          mine = s;
          break;
        }
      }
      if (mine?.checkOutAt != null) continue;
      final biz = _employerDisplayName(g, businessNames);
      return _ActiveShiftSnap(gig: g, company: biz);
    }
    return null;
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _firstName() {
    final n = widget.session.state.workerIdentity?.displayName.trim();
    if (n == null || n.isEmpty) {
      final e = widget.session.state.email ?? '';
      if (e.isEmpty) return 'there';
      return e.split('@').first;
    }
    return n.split(RegExp(r'\s+')).first;
  }

  List<Gig> get _previewJobs {
    final open = _nearby.where((g) => g.status == GigStatus.open).toList();
    open.sort((a, b) {
      final da = geoDistanceMetersApprox(_anchor, a.location);
      final db = geoDistanceMetersApprox(_anchor, b.location);
      return da.compareTo(db);
    });
    return open.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final name = _firstName();

    return ColoredBox(
      color: const Color(0xFFF8F9FF),
      child: RefreshIndicator(
        color: const Color(0xFF2563EB),
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _HomeHeader(
                greeting: _greeting(),
                name: name,
                unread: _unread,
                completed: _completedShifts,
                rating: _ratingAvg,
                appliedJobs: _appliedJobs,
                onBell: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => NotificationsScreen(
                        repo: widget.notifications,
                        session: widget.session,
                      ),
                    ),
                  );
                  if (mounted) await _load();
                },
              ),
            ),
            if (_active != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: _ActiveShiftBanner(
                    shift: _active!,
                    onView: widget.onOpenMyShift,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _QuickActionsRow(
                  onFindJobs: widget.onOpenFindJobs,
                  onMyShift: widget.onOpenMyShift,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Open jobs',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1C1E),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: widget.onOpenFindJobs,
                      child: Text(
                        'See all >',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: const Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _InlineError(message: _error!, onRetry: _load),
                ),
              )
            else if (_previewJobs.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Text(
                    'No open jobs in the feed yet. Try Find Jobs to browse the full list.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.4,
                      color: const Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverList.separated(
                  itemCount: _previewJobs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final g = _previewJobs[i];
                    return _DashboardJobCard(
                      gig: g,
                      businessName: _employerDisplayName(g, _businessNames),
                      distanceKm:
                          geoDistanceMetersApprox(_anchor, g.location) / 1000.0,
                      payAccent: _payAccentForGig(g),
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => WorkerGigDetailsScreen(
                              repo: widget.repo,
                              notifications: widget.notifications,
                              session: widget.session,
                              gigId: g.id,
                            ),
                          ),
                        );
                        if (mounted) await _load();
                      },
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottom),
                child: _RatingSummaryCard(
                  rating: _ratingAvg,
                  completed: _completedShifts,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveShiftSnap {
  const _ActiveShiftSnap({required this.gig, required this.company});
  final Gig gig;
  final String company;
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.greeting,
    required this.name,
    required this.unread,
    required this.completed,
    required this.rating,
    required this.appliedJobs,
    required this.onBell,
  });

  final String greeting;
  final String name;
  final int unread;
  final int completed;
  final double rating;
  final int appliedJobs;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final ratingLine =
        rating > 0 ? '${rating.toStringAsFixed(1)}★' : '—';

    return Container(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Color(0x330F172A),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0B1220),
                    Color(0xFF0F4C44),
                    Color(0xFF10B981),
                  ],
                  stops: [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -70,
            right: -50,
            child: IgnorePointer(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -90,
            child: IgnorePointer(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF34D399).withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
          Positioned(
            top: 100,
            left: -40,
            child: IgnorePointer(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, topInset + 18, 20, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting 👋',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.92),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.85,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Material(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            padding: const EdgeInsets.all(10),
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            onPressed: onBell,
                            icon: const Icon(
                              Icons.notifications_none_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        if (unread > 0)
                          Positioned(
                            right: 2,
                            top: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Text(
                                unread > 9 ? '9+' : '$unread',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _HeroGlassStat(
                        leading: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        value: '$completed',
                        label: 'Completed',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroGlassStat(
                        leading: const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFBBF24),
                          size: 28,
                        ),
                        value: ratingLine,
                        label: 'Rating',
                      ),
                    ),
                    const SizedBox(width: 10),
                      Expanded(
                      child: _HeroGlassStat(
                        leading: Icon(
                          Icons.send_rounded,
                          color: const Color(0xFF6366F1),
                          size: 26,
                        ),
                        value: '$appliedJobs',
                        label: 'Applied',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroGlassStat extends StatelessWidget {
  const _HeroGlassStat({
    required this.leading,
    required this.value,
    required this.label,
  });

  final Widget leading;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.38),
        ),
      ),
      child: Column(
        children: [
          leading,
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.15,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveShiftBanner extends StatelessWidget {
  const _ActiveShiftBanner({
    required this.shift,
    required this.onView,
  });

  final _ActiveShiftSnap shift;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final g = shift.gig;
    final start = g.startAt.toLocal();
    final h = start.hour;
    final am = h >= 12 ? 'PM' : 'AM';
    final hr = h % 12 == 0 ? 12 : h % 12;
    final m = start.minute.toString().padLeft(2, '0');
    final timeStr = '$hr:$m $am';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF22C55E),
            Color(0xFF14B8A6),
            Color(0xFF0EA5E9),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active Shift',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  g.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${shift.company} · $timeStr',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: Colors.white.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onView,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'View',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onFindJobs,
    required this.onMyShift,
  });

  final VoidCallback onFindJobs;
  final VoidCallback onMyShift;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickTile(
            icon: Icons.search_rounded,
            iconBg: const Color(0xFFE8EFFF),
            iconColor: const Color(0xFF6750A4),
            title: 'Find Jobs',
            subtitle: 'Browse open jobs',
            subtitleAccent: false,
            onTap: onFindJobs,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickTile(
            icon: Icons.schedule_rounded,
            iconBg: const Color(0xFFE8F7EC),
            iconColor: const Color(0xFF0F766E),
            title: 'My Shift',
            subtitle: 'Attendance & QR',
            subtitleAccent: false,
            onTap: onMyShift,
          ),
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.subtitleAccent,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool subtitleAccent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1D3557),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: subtitleAccent ? 13 : 12,
                    fontWeight:
                        subtitleAccent ? FontWeight.w800 : FontWeight.w600,
                    height: 1.3,
                    color: subtitleAccent
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF74777F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardJobCard extends StatelessWidget {
  const _DashboardJobCard({
    required this.gig,
    required this.businessName,
    required this.distanceKm,
    required this.payAccent,
    required this.onTap,
  });

  final Gig gig;
  final String businessName;
  final double distanceKm;
  final Color payAccent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pay = _dashboardPayLine(gig);
    final minutes = gig.endAt.difference(gig.startAt).inMinutes;
    final hoursDec = math.max(0.25, minutes / 60.0);
    final hoursLabel = hoursDec == hoursDec.roundToDouble()
        ? '${hoursDec.round()} hrs'
        : '${hoursDec.toStringAsFixed(1)} hrs';
    final urgent = gig.isUrgent || _descriptionMarksUrgent(gig.description);
    final todayOnly = _isTodayOnlyShift(gig);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AgapColors.borderSubtle.withValues(alpha: 0.85),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LeadingCatIcon(category: gig.category),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gig.title,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1D3557),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        businessName,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AgapColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          _MiniMeta(
                            icon: Icons.place_outlined,
                            text: '${distanceKm.toStringAsFixed(1)} km',
                          ),
                          _MiniMeta(icon: Icons.schedule_rounded, text: hoursLabel),
                          if (gig.isBoostedActive)
                            const _MiniPill(
                              text: 'Boosted',
                              bg: Color(0xFFEDE9FE),
                              fg: Color(0xFF5B21B6),
                            ),
                          if (urgent)
                            _MiniPill(
                              text: 'Urgent',
                              bg: const Color(0xFFFFE4E6),
                              fg: const Color(0xFFB91C1C),
                            )
                          else if (todayOnly)
                            const _MiniPill(
                              text: 'Today Only',
                              bg: Color(0xFFFFEDD5),
                              fg: Color(0xFF9A3412),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pay.$1,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: payAccent,
                      ),
                    ),
                    Text(
                      pay.$2,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AgapColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeadingCatIcon extends StatelessWidget {
  const _LeadingCatIcon({required this.category});
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
                : Icons.work_rounded;
    final tint = l.contains('warehouse')
        ? const Color(0xFFEDE9FE)
        : l.contains('food')
            ? const Color(0xFFFFE4E6)
            : const Color(0xFFE0F2FE);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: const Color(0xFF334155), size: 22),
    );
  }
}

class _MiniMeta extends StatelessWidget {
  const _MiniMeta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AgapColors.textMuted),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AgapColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({
    required this.text,
    required this.bg,
    required this.fg,
  });

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

class _RatingSummaryCard extends StatelessWidget {
  const _RatingSummaryCard({
    required this.rating,
    required this.completed,
  });

  final double rating;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final v = rating.clamp(0.0, 5.0);
    final hasRating = rating > 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EAEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Rating',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1A1C1E),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: List.generate(5, (i) {
                        final fill = hasRating && (i + 1) <= v.round();
                        return Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.star_rounded,
                            size: 26,
                            color: fill
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFFE5E7EB),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Based on $completed shift${completed == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF74777F),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasRating)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    rating.toStringAsFixed(1),
                    style: GoogleFonts.inter(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1A1C1E),
                      height: 1,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: hasRating ? v / 5.0 : 0,
              minHeight: 12,
              backgroundColor: const Color(0xFFE5E7EB),
              color: hasRating
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFFE5E7EB),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
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
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

Color _payAccentForGig(Gig g) {
  final h = g.id.hashCode.abs();
  const colors = <Color>[
    Color(0xFF6750A4),
    Color(0xFFB3261E),
    Color(0xFFE91E8C),
  ];
  return colors[h % colors.length];
}

(String, String) _dashboardPayLine(Gig g) {
  final total = g.pay.amount / 100.0;
  final minutes = g.endAt.difference(g.startAt).inMinutes;
  final hours = math.max(0.25, minutes / 60.0);
  final eventish = g.category.toLowerCase().contains('event');
  if (eventish) {
    return ('₱${total.round()}', '/event');
  }
  if (hours <= 10) {
    return ('₱${(total / hours).round()}', '/hr');
  }
  return ('₱${total.round()}', '/day');
}

bool _descriptionMarksUrgent(String description) {
  final l = description.toLowerCase();
  return l.contains('marked as urgent') || l.contains('urgent:');
}

bool _isTodayOnlyShift(Gig g) {
  final s = g.startAt.toLocal();
  final e = g.endAt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final sd = DateTime(s.year, s.month, s.day);
  final ed = DateTime(e.year, e.month, e.day);
  return sd == today && ed == today;
}

String _employerDisplayName(Gig g, Map<String, String> businessNames) {
  final resolved = businessNames[g.businessId];
  if (resolved != null &&
      resolved != 'Business' &&
      resolved.trim().isNotEmpty) {
    return resolved;
  }
  final addr = g.addressLabel.trim();
  if (addr.isNotEmpty) {
    final short = addr.split(',').first.trim();
    if (short.length > 38) return '${short.substring(0, 35)}…';
    return short;
  }
  if (_looksLikeUuid(g.businessId)) {
    return 'Your employer';
  }
  return _companyFromBusinessId(g.businessId);
}

bool _looksLikeUuid(String id) {
  final clean = id.trim().toLowerCase();
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  ).hasMatch(clean);
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

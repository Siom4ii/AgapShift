import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../profile/worker_display_names.dart';
import '../../../notifications/notification_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import '../marketplace/business_gig_applicants_screen.dart';
import '../marketplace/business_gigs_screen.dart';
import '../messages/message_thread_screen.dart';
import '../profile/business_view_worker_profile_screen.dart';

class BusinessHomeScreen extends StatefulWidget {
  const BusinessHomeScreen({
    super.key,
    required this.repo,
    required this.session,
    required this.shiftRepo,
    required this.notifications,
    required this.payments,
    required this.ratings,
    required this.onPostJob,
    required this.onFindWorkers,
    required this.onOpenNotifications,
    required this.onOpenInbox,
    this.notificationUnreadCount = 0,
    this.inboxUnreadCount = 0,
  });

  final MarketplaceRepository repo;
  final SessionController session;
  final ShiftRepository shiftRepo;
  final NotificationRepository notifications;
  final PaymentsRepository payments;
  final RatingsRepository ratings;
  final VoidCallback onPostJob;
  final VoidCallback onFindWorkers;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenInbox;
  final int notificationUnreadCount;
  final int inboxUnreadCount;

  @override
  State<BusinessHomeScreen> createState() => _BusinessHomeScreenState();
}

class _BusinessHomeScreenState extends State<BusinessHomeScreen> {
  List<Gig> _gigs = const [];
  List<GigApplication> _applications = const [];
  bool _loading = true;

  int _totalHired = 0;
  int _pendingApplicantCount = 0;
  int _applicantsLast7Days = 0;
  int _hiresLast7Days = 0;
  double _businessRatingAvg = 0;
  List<_Applicant> _recentApplicants = const [];

  static final _headerGradient = LinearGradient(
    colors: [
      AgapColors.businessGreenDeep,
      AgapColors.businessGreen,
      AgapColors.businessGreenLight,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final businessId = appActorId(widget.session, mockFallback: 'business');
      final all = await widget.repo.listGigs();
      final mine = all.where((g) => g.businessId == businessId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final apps = await widget.repo.listApplications();
      final avgRating = await widget.ratings.averageForUser(businessId);

      final myGigIds = mine.map((g) => g.id).toSet();
      final gigById = {for (final g in mine) g.id: g};

      final hired = apps
          .where(
            (a) =>
                myGigIds.contains(a.gigId) &&
                a.status == ApplicationStatus.hired,
          )
          .length;
      final pending = apps
          .where(
            (a) =>
                myGigIds.contains(a.gigId) &&
                a.status == ApplicationStatus.applied,
          )
          .length;

      final weekAgo = DateTime.now().toUtc().subtract(const Duration(days: 7));
      final applicantsWeek = apps
          .where(
            (a) =>
                myGigIds.contains(a.gigId) &&
                a.status == ApplicationStatus.applied &&
                a.createdAt.isAfter(weekAgo),
          )
          .length;
      final hiresWeek = apps
          .where(
            (a) =>
                myGigIds.contains(a.gigId) &&
                a.status == ApplicationStatus.hired &&
                a.createdAt.isAfter(weekAgo),
          )
          .length;

      final pendingApps = apps
          .where(
            (a) =>
                myGigIds.contains(a.gigId) &&
                a.status == ApplicationStatus.applied,
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final topPending = pendingApps.take(5).toList();
      final nameByWorker = await fetchWorkerDisplayNamesById(
        topPending.map((a) => a.workerId).toSet(),
      );

      final recent = <_Applicant>[];
      for (final app in topPending) {
        final gig = gigById[app.gigId];
        final workerAvg =
            await widget.ratings.averageForUser(app.workerId);
        final resolved = nameByWorker[app.workerId];
        final name = resolved != null && resolved.isNotEmpty
            ? resolved
            : applicantDisplayNameFallback(app.workerId);
        final appliedLocal = app.createdAt.toLocal();
        final hoursOld = DateTime.now().difference(appliedLocal).inHours;
        final availabilityLine = hoursOld < 6
            ? 'Just applied — respond while they are online'
            : hoursOld < 24
                ? 'Applied in the last 24 hours'
                : 'Awaiting your review';
        recent.add(
          _Applicant(
            workerId: app.workerId,
            gigId: app.gigId,
            initials: applicantInitialsFromName(name, app.workerId),
            name: name,
            tags: gig != null ? 'Applied · ${gig.title}' : 'Pending application',
            rating: workerAvg > 0 ? workerAvg : 0,
            km: 0,
            availabilityLine: availabilityLine,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _gigs = mine;
        _applications = apps;
        _totalHired = hired;
        _pendingApplicantCount = pending;
        _applicantsLast7Days = applicantsWeek;
        _hiresLast7Days = hiresWeek;
        _businessRatingAvg = avgRating;
        _recentApplicants = recent;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Registered trade / corporate name from onboarding (`identity_snapshot`).
  String get _businessName {
    final n = widget.session.state.businessIdentity?.displayName.trim();
    if (n != null && n.isNotEmpty) return n;
    return _businessDisplayName(widget.session.state.email ?? '');
  }

  String get _ratingHeader =>
      _businessRatingAvg > 0 ? '${_businessRatingAvg.toStringAsFixed(1)}★' : '—';

  int _hiredCountForGig(String gigId) => _applications
      .where(
        (a) =>
            a.gigId == gigId && a.status == ApplicationStatus.hired,
      )
      .length;
  bool get _verified =>
      widget.session.state.accountStatus == AccountStatus.verified;

  Future<void> _openApplicants(Gig gig) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BusinessGigApplicantsScreen(
          repo: widget.repo,
          notifications: widget.notifications,
          ratings: widget.ratings,
          session: widget.session,
          shiftRepo: widget.shiftRepo,
          gig: gig,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openManageJobPosts() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BusinessGigsScreen(
          repo: widget.repo,
          notifications: widget.notifications,
          payments: widget.payments,
          ratings: widget.ratings,
          session: widget.session,
          shiftRepo: widget.shiftRepo,
        ),
      ),
    );
    await _load();
  }

  int get _activeListingCount => _gigs
      .where(
        (g) =>
            g.status != GigStatus.cancelled && g.status != GigStatus.completed,
      )
      .length;

  String get _insightLine {
    if (_applicantsLast7Days > 0 && _pendingApplicantCount > 0) {
      return '$_applicantsLast7Days applicant${_applicantsLast7Days == 1 ? '' : 's'} in the last 7 days — quick replies help you win talent.';
    }
    if (_hiresLast7Days > 0) {
      return '$_hiresLast7Days hire${_hiresLast7Days == 1 ? '' : 's'} in the last week. Great momentum.';
    }
    if (_pendingApplicantCount > 0) {
      return 'You have people waiting — review applicants from each job card.';
    }
    return 'Post shifts or browse Find Workers to keep your pipeline warm.';
  }

  Future<void> _openDmToApplicant(String workerId, String displayName) async {
    final scope = MarketplaceScope.tryOf(context);
    if (scope == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Messaging is unavailable here.')),
      );
      return;
    }
    try {
      final cid = await scope.messaging.getOrCreateConversation(
        otherUserId: workerId,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MessageThreadScreen(
            conversationId: cid,
            title: displayName,
            peerUserId: workerId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: $e')),
      );
    }
  }

  void _openWorkerProfile(String workerId) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BusinessViewWorkerProfileScreen(
          workerId: workerId,
          ratings: widget.ratings,
          shiftRepo: widget.shiftRepo,
        ),
      ),
    );
  }

  Future<void> _openApplicantsForGigId(String gigId) async {
    final matches = _gigs.where((g) => g.id == gigId);
    if (matches.isEmpty) return;
    await _openApplicants(matches.first);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ShellChromeBackground(
      kind: ShellChromeKind.business,
      child: RefreshIndicator(
        onRefresh: _load,
        color: AgapColors.businessGreen,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(gradient: _headerGradient),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 16),
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
                                  'Business Dashboard',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _businessName,
                                  style: GoogleFonts.inter(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _verified
                                          ? 'Verified Business'
                                          : 'Pending verification',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withValues(
                                          alpha: 0.95,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Material(
                                color: Colors.white.withValues(alpha: 0.22),
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 44,
                                    minHeight: 44,
                                  ),
                                  onPressed: widget.onOpenInbox,
                                  tooltip: 'Messages',
                                  icon: Badge(
                                    isLabelVisible: widget.inboxUnreadCount > 0,
                                    label: Text(
                                      widget.inboxUnreadCount > 99
                                          ? '99+'
                                          : '${widget.inboxUnreadCount}',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    backgroundColor: Colors.red.shade600,
                                    child: const Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Material(
                                color: Colors.white.withValues(alpha: 0.22),
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 44,
                                    minHeight: 44,
                                  ),
                                  onPressed: widget.onOpenNotifications,
                                  icon: Badge(
                                    isLabelVisible: widget.notificationUnreadCount > 0,
                                    label: Text(
                                      widget.notificationUnreadCount > 99
                                          ? '99+'
                                          : '${widget.notificationUnreadCount}',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    backgroundColor: Colors.red.shade600,
                                    child: const Icon(
                                      Icons.notifications_outlined,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _HeaderStat(
                              icon: Icons.groups_rounded,
                              iconColor: const Color(0xFF7C3AED),
                              label: 'Total Hired',
                              value: '$_totalHired',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _HeaderStat(
                              icon: Icons.assignment_turned_in_outlined,
                              iconColor: const Color(0xFFEC4899),
                              label: 'Active Jobs',
                              value: '$_activeListingCount',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _HeaderStat(
                              icon: Icons.star_rounded,
                              iconColor: const Color(0xFFFFD700),
                              label: 'Rating',
                              value: _ratingHeader,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              color: Colors.white.withValues(alpha: 0.95),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$_activeListingCount active listing${_activeListingCount == 1 ? '' : 's'} · '
                                '$_hiresLast7Days hire${_hiresLast7Days == 1 ? '' : 's'} this week',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                  color: Colors.white.withValues(alpha: 0.95),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _insightLine,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 118,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _QuickActionCard(
                                filled: true,
                                icon: Icons.add_rounded,
                                title: 'Post a Job',
                                subtitle: 'Hire workers now',
                                onTap: widget.onPostJob,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _QuickActionCard(
                                filled: false,
                                icon: Icons.person_search_rounded,
                                title: 'Find Workers',
                                subtitle: _pendingApplicantCount == 0
                                    ? 'No pending applicants'
                                    : '$_pendingApplicantCount pending now',
                                onTap: widget.onFindWorkers,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Active Job Posts',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _openManageJobPosts,
                      child: Text(
                        'Manage all ›',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          color: AgapColors.businessGreen,
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
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_gigs.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _SectionCard(
                    child: Text(
                      'No active posts yet. Tap “Post a Job” to create one.',
                      style: GoogleFonts.inter(
                        color: AgapColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                sliver: SliverList.separated(
                  itemCount: _gigs.length.clamp(0, 6),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final g = _gigs[i];
                    return ShellStaggerItem(
                      index: i,
                      child: ShellLift(
                        child: _ActiveJobCard(
                          gig: g,
                          index: i,
                          hiredCount: _hiredCountForGig(g.id),
                          onOpen: () => _openApplicants(g),
                        ),
                      ),
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recent Applicants',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _openManageJobPosts,
                      child: Text(
                        'Manage posts ›',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          color: AgapColors.businessGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_recentApplicants.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                sliver: SliverList.separated(
                  itemCount: _recentApplicants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => ShellStaggerItem(
                    index: i,
                    child: ShellLift(
                      child: _ApplicantTile(
                      a: _recentApplicants[i],
                      onMessage: () => _openDmToApplicant(
                        _recentApplicants[i].workerId,
                        _recentApplicants[i].name,
                      ),
                      onProfile: () =>
                          _openWorkerProfile(_recentApplicants[i].workerId),
                      onApplicants: () => _openApplicantsForGigId(
                        _recentApplicants[i].gigId,
                      ),
                    ),
                    ),
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: _SectionCard(
                    child: Text(
                      'No pending applicants right now.',
                      style: GoogleFonts.inter(
                        color: AgapColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: 24 + bottomInset)),
          ],
        ),
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: iconColor ?? Colors.white.withValues(alpha: 0.95),
              size: 18,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.filled,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool filled;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AgapColors.businessGreen : Colors.white,
      elevation: filled ? 3 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: filled
            ? BorderSide.none
            : BorderSide(
                color: AgapColors.businessGreen.withValues(alpha: 0.38),
                width: 1.5,
              ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: filled ? Colors.white : AgapColors.businessGreen,
                size: 22,
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: filled ? Colors.white : const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: filled
                      ? Colors.white.withValues(alpha: 0.92)
                      : AgapColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgapColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// Wallet UI removed (no digital wallet in app for now).

class _ActiveJobCard extends StatelessWidget {
  const _ActiveJobCard({
    required this.gig,
    required this.index,
    required this.hiredCount,
    required this.onOpen,
  });

  final Gig gig;
  final int index;
  final int hiredCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final slots = (gig.workersNeeded != null && gig.workersNeeded! > 0)
        ? gig.workersNeeded!
        : 1;
    final filled = hiredCount.clamp(0, slots);
    final frac = slots == 0 ? 0.0 : (filled / slots).clamp(0.0, 1.0);
    final dayPay = (gig.pay.amount / 100).round();
    final cat = _categoryAccent(gig, index);
    final status = _gigStatusPresentation(gig);
    final urgent = gig.isUrgent;

    final inner = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: cat.gradient,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: cat.gradient.last.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(cat.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gig.title,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$filled/$slots hired · ₱$dayPay/day',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AgapColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: status.bg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: status.border),
                      boxShadow: [
                        if (status.glow != null)
                          BoxShadow(
                            color: status.glow!,
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        if (urgent && gig.status == GigStatus.open)
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: Text(
                      status.label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: status.fg,
                      ),
                    ),
                  ),
                ],
              ),
              if (urgent) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 16,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Urgent — prioritize applicants',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 6,
                  backgroundColor: AgapColors.borderSubtle.withValues(
                    alpha: 0.5,
                  ),
                  color: status.progressColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!urgent) return inner;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.deepOrange.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: inner,
    );
  }
}

({String label, Color bg, Color fg, Color border, Color? glow, Color progressColor})
    _gigStatusPresentation(Gig gig) {
  switch (gig.status) {
    case GigStatus.open:
      return (
        label: 'Open',
        bg: AgapColors.businessMint,
        fg: AgapColors.businessGreenDeep,
        border: AgapColors.businessGreen.withValues(alpha: 0.35),
        glow: null,
        progressColor: AgapColors.businessGreen,
      );
    case GigStatus.filled:
      return (
        label: 'Filled',
        bg: const Color(0xFFFFF7ED),
        fg: const Color(0xFF9A3412),
        border: const Color(0xFFFDBA74),
        glow: null,
        progressColor: const Color(0xFFEA580C),
      );
    case GigStatus.ongoing:
      return (
        label: 'Live',
        bg: const Color(0xFFECFEFF),
        fg: const Color(0xFF0E7490),
        border: const Color(0xFF67E8F9),
        glow: null,
        progressColor: const Color(0xFF0891B2),
      );
    case GigStatus.completed:
      return (
        label: 'Completed',
        bg: const Color(0xFFEFF6FF),
        fg: const Color(0xFF1D4ED8),
        border: const Color(0xFFBFDBFE),
        glow: null,
        progressColor: const Color(0xFF2563EB),
      );
    case GigStatus.cancelled:
      return (
        label: 'Cancelled',
        bg: const Color(0xFFFEF2F2),
        fg: const Color(0xFFB91C1C),
        border: const Color(0xFFFECACA),
        glow: null,
        progressColor: AgapColors.textMuted,
      );
  }
}

({List<Color> gradient, IconData icon}) _categoryAccent(Gig gig, int index) {
  final t = '${gig.category} ${gig.title}'.toLowerCase();
  if (t.contains('food') ||
      t.contains('cook') ||
      t.contains('kitchen') ||
      t.contains('waiter')) {
    return (
      gradient: [const Color(0xFFF97316), const Color(0xFFEA580C)],
      icon: Icons.restaurant_menu_rounded,
    );
  }
  if (t.contains('retail') || t.contains('store') || t.contains('cashier')) {
    return (
      gradient: [const Color(0xFF6366F1), const Color(0xFF4338CA)],
      icon: Icons.storefront_outlined,
    );
  }
  if (t.contains('event') || t.contains('singer') || t.contains('crew')) {
    return (
      gradient: [const Color(0xFFEC4899), const Color(0xFFDB2777)],
      icon: Icons.celebration_outlined,
    );
  }
  if (t.contains('warehouse') || t.contains('stock')) {
    return (
      gradient: [const Color(0xFF64748B), const Color(0xFF334155)],
      icon: Icons.inventory_2_outlined,
    );
  }
  final alt = <({List<Color> gradient, IconData icon})>[
    (
      gradient: [const Color(0xFF22C55E), AgapColors.businessGreenDeep],
      icon: Icons.work_outline_rounded,
    ),
    (
      gradient: [const Color(0xFF38BDF8), const Color(0xFF0284C7)],
      icon: Icons.handyman_outlined,
    ),
    (
      gradient: [const Color(0xFFA855F7), const Color(0xFF7E22CE)],
      icon: Icons.cleaning_services_outlined,
    ),
  ];
  return alt[index % alt.length];
}

class _Applicant {
  const _Applicant({
    required this.workerId,
    required this.gigId,
    required this.initials,
    required this.name,
    required this.tags,
    required this.rating,
    required this.km,
    required this.availabilityLine,
  });

  final String workerId;
  final String gigId;
  final String initials;
  final String name;
  final String tags;
  final double rating;
  final double km;
  final String availabilityLine;
}

class _ApplicantTile extends StatelessWidget {
  const _ApplicantTile({
    required this.a,
    required this.onMessage,
    required this.onProfile,
    required this.onApplicants,
  });

  final _Applicant a;
  final VoidCallback onMessage;
  final VoidCallback onProfile;
  final VoidCallback onApplicants;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onApplicants,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AgapColors.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AgapColors.businessGreenDeep,
                      child: Text(
                        a.initials,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  a.name,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.verified_rounded,
                                size: 18,
                                color: AgapColors.businessGreen,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            a.tags,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AgapColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            a.availabilityLine,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AgapColors.businessGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: const Color(0xFFEAB308),
                            ),
                            Text(
                              a.rating > 0 ? a.rating.toStringAsFixed(1) : '—',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${a.km} km',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onApplicants,
                      icon: const Icon(Icons.group_outlined, size: 16),
                      label: Text(
                        'Review',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AgapColors.businessGreenDeep,
                        side: BorderSide(
                          color: AgapColors.businessGreen.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onMessage,
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                      label: Text(
                        'Message',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onProfile,
                      icon: const Icon(Icons.person_outline_rounded, size: 16),
                      label: Text(
                        'Profile',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AgapColors.textMuted,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        visualDensity: VisualDensity.compact,
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

// (removed) _formatPesoCompact

String _businessDisplayName(String email) {
  if (email.isEmpty) return 'Your business';
  final local = email.split('@').first;
  if (local.isEmpty) return 'Your business';
  final words = local
      .split(RegExp(r'[._-]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'Your business';
  return words
      .map(
        (w) =>
            '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1).toLowerCase() : ''}',
      )
      .join(' ');
}

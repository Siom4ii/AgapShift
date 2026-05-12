import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/business_identity.dart';
import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../profile/worker_display_names.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import '../../widgets/verification_status_card.dart';
import '../subscriptions/employer_subscription_screen.dart';
import 'business_hiring_history_screen.dart';
import '../ratings/user_ratings_screen.dart';

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({
    super.key,
    required this.session,
    required this.marketRepo,
    required this.ratings,
    this.payments,
    this.embedded = false,

    /// Public business view (e.g. worker opened your listing). Hide on your own Profile tab.
    this.showFollowFab = true,
    this.onLogout,
    this.onOpenNotifications,
    this.onOpenInbox,
    this.notificationUnreadCount = 0,
    this.inboxUnreadCount = 0,
  });

  final SessionController session;
  final MarketplaceRepository marketRepo;
  final RatingsRepository ratings;
  final PaymentsRepository? payments;
  final bool embedded;
  final bool showFollowFab;
  final Future<void> Function()? onLogout;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenInbox;
  final int notificationUnreadCount;
  final int inboxUnreadCount;

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  double _avg = 0;
  List<Gig> _recentGigs = const [];
  List<Rating> _reviews = const [];
  BusinessIdentityDisplay? _identity;
  int _totalHired = 0;
  int _totalPaidCentavos = 0;
  int _activeOpenGigs = 0;
  int _hireFillPct = 0;
  List<_RecentHireVm> _recentHires = const [];

  @override
  void initState() {
    super.initState();
    // Seeded from session KV (profile merge) so the Profile tab does not flash
    // "Your business" while a duplicate identity fetch runs.
    _identity = widget.session.state.businessIdentity;
    _load();
  }

  BusinessIdentityDisplay? get _effectiveIdentity =>
      _identity ?? widget.session.state.businessIdentity;

  Future<void> _load() async {
    final userId = appActorId(widget.session, mockFallback: '');
    final avg = await widget.ratings.averageForUser(userId);
    final gigs = await widget.marketRepo.listGigs();
    final posted = gigs.where((g) => g.businessId == userId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final reviews = await widget.ratings.listForUser(userId);
    final apps = await widget.marketRepo.listApplications();
    final myGigIds = posted.map((g) => g.id).toSet();
    final gigById = {for (final g in posted) g.id: g};

    final hiredApps = apps
        .where(
          (a) =>
              myGigIds.contains(a.gigId) &&
              a.status == ApplicationStatus.hired,
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final activeOpen = posted
        .where(
          (g) =>
              g.status == GigStatus.open ||
              g.status == GigStatus.filled ||
              g.status == GigStatus.ongoing,
        )
        .length;
    final fillPct = posted.isEmpty
        ? 0
        : ((hiredApps.length / posted.length) * 100).round().clamp(0, 100);

    var paidCentavos = 0;
    if (widget.payments != null) {
      final ledger = await widget.payments!.listLedger(userId);
      for (final t in ledger) {
        if (t.type == TransactionType.escrowFunding) {
          paidCentavos += t.amount.amount;
        }
      }
    }

    final hiredSlice = hiredApps.take(5).toList();
    final nameByWorker =
        await fetchWorkerDisplayNamesById(hiredSlice.map((a) => a.workerId).toSet());

    final workerHireCounts = <String, int>{};
    for (final a in hiredApps) {
      workerHireCounts[a.workerId] = (workerHireCounts[a.workerId] ?? 0) + 1;
    }

    final recentHires = <_RecentHireVm>[];
    for (var idx = 0; idx < hiredSlice.length; idx++) {
      final a = hiredSlice[idx];
      final g = gigById[a.gigId];
      final wAvg = await widget.ratings.averageForUser(a.workerId);
      final stars = wAvg > 0 ? wAvg.round().clamp(1, 5) : 0;
      final payPesos = g == null ? 0 : (g.pay.amount / 100).round();
      final resolved = nameByWorker[a.workerId]?.trim();
      final displayName = (resolved != null && resolved.isNotEmpty)
          ? resolved
          : applicantDisplayNameFallback(a.workerId);
      final hireCount = workerHireCounts[a.workerId] ?? 0;
      String? relationshipTag;
      if (hireCount >= 3) {
        relationshipTag = 'Favorite worker';
      } else if (hireCount >= 2) {
        relationshipTag = 'Rehired';
      } else if (idx == 0) {
        relationshipTag = 'Active worker';
      }
      recentHires.add(
        _RecentHireVm(
          workerId: a.workerId,
          name: displayName,
          role: g?.title ?? 'Shift',
          when: _relativeWhen(a.createdAt.toLocal()),
          amount: '₱${_formatThousandsInt(payPesos)}',
          stars: stars,
          relationshipTag: relationshipTag,
        ),
      );
    }

    BusinessIdentityDisplay? identity;
    if (SupabaseConfig.isConfigured) {
      try {
        final uid = Supabase.instance.client.auth.currentUser?.id;
        if (uid != null) {
          final row = await Supabase.instance.client
              .from('profiles')
              .select('identity_snapshot')
              .eq('id', uid)
              .maybeSingle();
          if (row != null) {
            identity = businessIdentityFromProfileIdentitySnapshot(
              row['identity_snapshot'],
            );
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _avg = avg;
      _recentGigs = posted.take(2).toList();
      _reviews = reviews.take(3).toList();
      _identity = identity;
      _totalHired = hiredApps.length;
      _totalPaidCentavos = paidCentavos;
      _activeOpenGigs = activeOpen;
      _hireFillPct = fillPct;
      _recentHires = recentHires;
    });
  }

  String _relativeWhen(DateTime local) {
    final now = DateTime.now();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    return '${local.month}/${local.day}';
  }

  String _paidCompact(int centavos) {
    final p = centavos / 100.0;
    if (p <= 0) return '₱0';
    if (p >= 1000000) return '₱${(p / 1000000).toStringAsFixed(1)}M';
    if (p >= 1000) return '₱${(p / 1000).toStringAsFixed(1)}k';
    return '₱${p.round()}';
  }

  String get _bizName =>
      _effectiveIdentity?.displayName ?? 'Your business';

  String get _subtitle =>
      _effectiveIdentity?.tagline ??
      'Complete registration to show your business details';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        return _buildContent(context);
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    final verified =
        widget.session.state.accountStatus == AccountStatus.verified;
    final ratingShow = _avg > 0 ? _avg : 0.0;
    final reviewCount = _reviews.length;

    final bottomInset = widget.showFollowFab ? 100.0 : 28.0;
    final body = ShellChromeBackground(
      kind: ShellChromeKind.business,
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: widget.embedded && !widget.showFollowFab
                  ? EdgeInsets.fromLTRB(
                      0,
                      0,
                      0,
                      widget.embedded && !widget.showFollowFab
                          ? bottomInset + 28
                          : bottomInset,
                    )
                  : EdgeInsets.fromLTRB(
                      20,
                      widget.embedded ? 12 : 8,
                      20,
                      bottomInset,
                    ),
              children: [
                if (widget.embedded && !widget.showFollowFab) ...[
                  _BusinessProfileOwnerTab(
                    bizName: _bizName,
                    tagline: _subtitle,
                    addressLine: _effectiveIdentity?.addressLine,
                    phone: _effectiveIdentity?.phone,
                    ratingShow: ratingShow,
                    verified: verified,
                    workersHired: _totalHired,
                    totalPaidLabel: widget.payments == null
                        ? '—'
                        : _paidCompact(_totalPaidCentavos),
                    activeOpenGigs: _activeOpenGigs,
                    hireFillPct: _hireFillPct,
                    recentHires: _recentHires,
                    session: widget.session,
                    onLogout: widget.onLogout,
                    onOpenHiringHistory: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => BusinessHiringHistoryScreen(
                            session: widget.session,
                            marketRepo: widget.marketRepo,
                            ratings: widget.ratings,
                          ),
                        ),
                      );
                    },
                    onOpenNotifications: widget.onOpenNotifications,
                    onOpenInbox: widget.onOpenInbox,
                    notificationUnreadCount: widget.notificationUnreadCount,
                    inboxUnreadCount: widget.inboxUnreadCount,
                  ),
                ] else ...[
                  if (!widget.showFollowFab) ...[
                    Text(
                      'Your public profile — how workers see your business',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.35,
                        color: AgapColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _BusinessHeaderCard(
                    name: _bizName,
                    subtitle: _subtitle,
                    verified: verified,
                    rating: ratingShow,
                    reviewCount: reviewCount,
                    addressLine: _effectiveIdentity?.addressLine,
                    phone: _effectiveIdentity?.phone,
                  ),
                  const SizedBox(height: 16),
                  VerificationStatusCard(session: widget.session),
                  const SizedBox(height: 16),
                  _AboutCard(),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Recent Gigs',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {},
                        child: Text(
                          'View all',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: AgapColors.businessGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_recentGigs.isEmpty) ...[
                    _DemoGigCard(
                      title: 'Warehouse Picker/Packer',
                      totalPeso: 180,
                      hourlyPeso: 22.50,
                      location: 'Makati, NCR',
                      schedule: 'Tomorrow, 8:00 AM - 4:00 PM',
                      tags: const [
                        _TagSpec(
                          'High Demand',
                          Color(0xFFDBEAFE),
                          Color(0xFF1E40AF),
                        ),
                        _TagSpec(
                          'Indoor',
                          Color(0xFFE0F2FE),
                          Color(0xFF0369A1),
                        ),
                        _TagSpec(
                          'Certification Required',
                          Color(0xFFE8F5EF),
                          Color(0xFF005C39),
                        ),
                        _TagSpec(
                          'Night Shift',
                          Color(0xFFE0E7FF),
                          Color(0xFF4338CA),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DemoGigCard(
                      title: 'Event Setup Assistant',
                      totalPeso: 220,
                      hourlyPeso: 27.50,
                      location: 'BGC, Taguig',
                      schedule: 'Sat, 6:00 AM - 2:00 PM',
                      tags: const [
                        _TagSpec(
                          'High Demand',
                          Color(0xFFDBEAFE),
                          Color(0xFF1E40AF),
                        ),
                        _TagSpec(
                          'Outdoor',
                          Color(0xFFE0F2FE),
                          Color(0xFF0369A1),
                        ),
                      ],
                    ),
                  ] else
                    ..._recentGigs.map(
                      (g) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _GigCardFromModel(
                          gig: g,
                          tagSeed: g.id.hashCode,
                        ),
                      ),
                    ),
                  if (_recentGigs.isNotEmpty) const SizedBox(height: 12),
                  const SizedBox(height: 8),
                  Text(
                    'Worker Reviews',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        final userId = appActorId(widget.session, mockFallback: '');
                        if (userId.isEmpty) return;
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => UserRatingsScreen(
                              ratings: widget.ratings,
                              userId: userId,
                              title: 'Business reviews',
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'View all reviews',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_reviews.isEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'No reviews yet.',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          color: AgapColors.textMuted,
                        ),
                      ),
                    ),
                  ] else
                    ..._reviews.map(
                      (r) => _ReviewCard(
                        name: 'Review',
                        shifts: 0,
                        stars: r.stars,
                        body: r.feedback ?? 'No comment provided.',
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (widget.showFollowFab)
            Positioned(
              right: 20,
              bottom: 24,
              child: FloatingActionButton.extended(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Following (demo)')),
                  );
                },
                backgroundColor: AgapColors.businessGreenDeep,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  'Follow Business',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.embedded) {
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AgapShift',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            color: AgapColors.businessGreen,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              backgroundColor: AgapColors.businessMint,
              child: Icon(
                Icons.storefront_rounded,
                color: AgapColors.businessGreenDeep,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

class _RecentHireVm {
  const _RecentHireVm({
    required this.workerId,
    required this.name,
    required this.role,
    required this.when,
    required this.amount,
    required this.stars,
    this.relationshipTag,
  });

  final String workerId;
  final String name;
  final String role;
  final String when;
  final String amount;
  final int stars;
  /// e.g. Active worker, Rehired, Trusted regular (proxy for “favorite”).
  final String? relationshipTag;
}

String _formatThousandsInt(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    if (i > 0 && fromEnd % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

class _BusinessProfileOwnerTab extends StatelessWidget {
  const _BusinessProfileOwnerTab({
    required this.bizName,
    required this.tagline,
    this.addressLine,
    this.phone,
    required this.ratingShow,
    required this.verified,
    required this.workersHired,
    required this.totalPaidLabel,
    required this.activeOpenGigs,
    required this.hireFillPct,
    required this.recentHires,
    required this.session,
    required this.onLogout,
    this.onOpenHiringHistory,
    this.onOpenNotifications,
    this.onOpenInbox,
    this.notificationUnreadCount = 0,
    this.inboxUnreadCount = 0,
  });

  final String bizName;
  final String tagline;
  final String? addressLine;
  final String? phone;
  final double ratingShow;
  final bool verified;
  final int workersHired;
  final String totalPaidLabel;
  final int activeOpenGigs;
  final int hireFillPct;
  final List<_RecentHireVm> recentHires;
  final SessionController session;
  final Future<void> Function()? onLogout;
  final VoidCallback? onOpenHiringHistory;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenInbox;
  final int notificationUnreadCount;
  final int inboxUnreadCount;

  String get _initials {
    final parts = bizName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'B';
    if (parts.length == 1) {
      final p = parts[0];
      return p.length >= 2
          ? p.substring(0, 2).toUpperCase()
          : p[0].toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final hasRating = ratingShow > 0;
    final ratingText = hasRating
        ? '${ratingShow.toStringAsFixed(1)} ($workersHired hires)'
        : 'No ratings yet ($workersHired hires)';

    final showPaid = totalPaidLabel != '₱0' && totalPaidLabel != '—';

    final insightMessage = hireFillPct >= 35 && verified
        ? '$hireFillPct% of your listings led to a hire — strong employer signal on AgapShift.'
        : 'Tip: reply to applicants within a few hours to build a "fast responder" reputation.';

    final highlightHires = workersHired > 0;
    final highlightRating = hasRating && ratingShow >= 4.5;
    final highlightListings = !highlightRating && !highlightHires && activeOpenGigs > 0;

    return ColoredBox(
      color: const Color(0xFFF3F4F6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AgapColors.businessGreenDeep,
                        AgapColors.businessGreen,
                        AgapColors.businessGreenLight.withValues(alpha: 0.6),
                        const Color(0xFFE8EDF5),
                        const Color(0xFFF3F4F6),
                      ],
                      stops: const [0.0, 0.16, 0.42, 0.72, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -36,
                top: topInset + 8,
                child: IgnorePointer(
                  child: Container(
                    width: 176,
                    height: 176,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -52,
                top: topInset + 120,
                child: IgnorePointer(
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 64,
                top: topInset + 72,
                child: IgnorePointer(
                  child: Transform.rotate(
                    angle: 0.35,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: topInset + 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'My Profile',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        if (onOpenInbox != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: IconButton(
                                tooltip: 'Messages',
                                icon: Badge(
                                  isLabelVisible: inboxUnreadCount > 0,
                                  label: Text(
                                    inboxUnreadCount > 99
                                        ? '99+'
                                        : '$inboxUnreadCount',
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
                                  ),
                                ),
                                onPressed: onOpenInbox,
                              ),
                            ),
                          ),
                        if (onOpenNotifications != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: IconButton(
                                tooltip: 'Notifications',
                                icon: Badge(
                                  isLabelVisible: notificationUnreadCount > 0,
                                  label: Text(
                                    notificationUnreadCount > 99
                                        ? '99+'
                                        : '$notificationUnreadCount',
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
                                  ),
                                ),
                                onPressed: onOpenNotifications,
                              ),
                            ),
                          ),
                        Material(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            icon: const Icon(
                              Icons.edit_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Edit profile (demo)'),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _BizProfileSummaryCard(
                      initials: _initials,
                      name: bizName,
                      verified: verified,
                      tagline: tagline,
                      hasRating: hasRating,
                      ratingValue: ratingShow,
                      ratingText: ratingText,
                      addressLine: addressLine ?? '',
                      phone: phone ?? '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PressScale(
                            child: _BizMetricCard(
                              iconBoxColor:
                                  AgapColors.businessMint.withValues(alpha: 0.9),
                              icon: Icons.groups_outlined,
                              iconColor: AgapColors.businessGreenDeep,
                              value: '$workersHired',
                              valueColor: AgapColors.businessGreenDeep,
                              label: 'Workers hired',
                              microTag: workersHired == 0
                                  ? 'Start hiring today'
                                  : 'Keep growing',
                              microTagColor: AgapColors.businessGreenDeep,
                              emphasized: highlightHires,
                              accentBarColor: highlightHires
                                  ? AgapColors.businessGreen
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PressScale(
                            child: _BizMetricCard(
                              iconBoxColor: const Color(0xFFFFF8E1),
                              icon: Icons.star_rounded,
                              iconColor: const Color(0xFFFFC107),
                              value: hasRating ? ratingShow.toStringAsFixed(1) : '—',
                              valueColor: hasRating
                                  ? const Color(0xFFE65100)
                                  : AgapColors.textMuted,
                              label: 'Rating',
                              microTag: hasRating
                                  ? (ratingShow >= 4.5
                                      ? 'Top employer'
                                      : (ratingShow >= 4.0
                                          ? 'Excellent'
                                          : 'Keep it up'))
                                  : 'Earn stars',
                              microTagColor: const Color(0xFFE65100),
                              emphasized: highlightRating,
                              accentBarColor: highlightRating
                                  ? const Color(0xFFFFB300)
                                  : null,
                              rewardGlow: highlightRating,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PressScale(
                            child: _BizMetricCard(
                              iconBoxColor: const Color(0xFFE8EFFF),
                              icon: showPaid
                                  ? Icons.payments_outlined
                                  : Icons.work_outline,
                              iconColor: const Color(0xFF2563EB),
                              value: showPaid ? totalPaidLabel : '$activeOpenGigs',
                              valueColor: AgapColors.businessGreenDeep,
                              label: showPaid ? 'Total paid' : 'Open listings',
                              microTag: showPaid
                                  ? 'All-time'
                                  : (activeOpenGigs == 0
                                      ? 'Post your first'
                                      : 'Live now'),
                              microTagColor: const Color(0xFF2563EB),
                              emphasized: highlightListings,
                              accentBarColor: highlightListings
                                  ? const Color(0xFF2563EB)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!verified)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: VerificationStatusCard(session: session),
                    ),
                  if (hireFillPct > 0 || verified) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _InsightTipCard(message: insightMessage),
                    ),
                  ],
                  const SizedBox(height: 18),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BizSectionCard(
                  title: 'Recent Hires',
                  icon: Icons.history_rounded,
                  child: recentHires.isEmpty
                      ? Text(
                          'Completed hires will appear here after you hire a worker.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            height: 1.45,
                            color: AgapColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : _RecentHiresExpandable(recentHires: recentHires),
                ),
                const SizedBox(height: 14),
                _BizSectionCard(
                  title: 'Shortcuts',
                  icon: Icons.apps_rounded,
                  child: Column(
                    children: [
                      _ShortcutProfileTile(
                        icon: Icons.workspace_premium_outlined,
                        title: 'Employer subscription',
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => EmployerSubscriptionScreen(
                                session: session,
                              ),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      _ShortcutProfileTile(
                        icon: Icons.history_rounded,
                        title: 'Hiring History',
                        onTap: onOpenHiringHistory ??
                            () => ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Hiring history'),
                                  ),
                                ),
                      ),
                      const Divider(height: 1),
                      _ShortcutProfileTile(
                        icon: Icons.notifications_outlined,
                        title: 'Notifications',
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Notifications')),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onLogout == null
                      ? null
                      : () async {
                          await onLogout!();
                        },
                  icon: Icon(Icons.logout_rounded, color: Colors.red.shade700),
                  label: Text(
                    'Log Out',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PressScale extends StatefulWidget {
  const _PressScale({required this.child});

  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _scale = 0.97),
      onPointerUp: (_) => setState(() => _scale = 1),
      onPointerCancel: (_) => setState(() => _scale = 1),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _BizProfileSummaryCard extends StatelessWidget {
  const _BizProfileSummaryCard({
    required this.initials,
    required this.name,
    required this.verified,
    required this.tagline,
    required this.hasRating,
    required this.ratingValue,
    required this.ratingText,
    required this.addressLine,
    required this.phone,
  });

  final String initials;
  final String name;
  final bool verified;
  final String tagline;
  final bool hasRating;
  final double ratingValue;
  final String ratingText;
  final String addressLine;
  final String phone;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AgapColors.businessGreenDeep,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AgapColors.businessGreenDeep,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AgapColors.businessGreen,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Verified',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tagline,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: AgapColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ...List.generate(5, (i) {
                        final filled =
                            hasRating && i < ratingValue.round().clamp(0, 5);
                        return Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: filled
                                ? const Color(0xFFFFC107)
                                : const Color(0xFFE0E0E0),
                          ),
                        );
                      }),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ratingText,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (addressLine.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 16,
                          color: AgapColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            addressLine,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AgapColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (phone.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: 16,
                          color: Color(0xFFDB2777),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            phone,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AgapColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BizMetricCard extends StatelessWidget {
  const _BizMetricCard({
    required this.iconBoxColor,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.valueColor,
    required this.label,
    this.microTag,
    this.microTagColor,
    this.emphasized = false,
    this.accentBarColor,
    this.rewardGlow = false,
  });

  final Color iconBoxColor;
  final IconData icon;
  final Color iconColor;
  final String value;
  final Color valueColor;
  final String label;
  final String? microTag;
  final Color? microTagColor;
  final bool emphasized;
  final Color? accentBarColor;
  final bool rewardGlow;

  @override
  Widget build(BuildContext context) {
    final sub = microTag?.trim();
    final glowAmber = emphasized && rewardGlow;

    final shadows = <BoxShadow>[
      if (glowAmber) ...[
        BoxShadow(
          color: const Color(0xFFFFC107).withValues(alpha: 0.36),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: const Color(0xFFFFE082).withValues(alpha: 0.22),
          blurRadius: 14,
          spreadRadius: -2,
          offset: const Offset(0, 4),
        ),
      ] else if (emphasized)
        BoxShadow(
          color: AgapColors.businessGreenDeep.withValues(alpha: 0.16),
          blurRadius: 20,
          offset: const Offset(0, 7),
        )
      else
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: glowAmber
              ? const Color(0xFFFFB300).withValues(alpha: 0.55)
              : (emphasized
                  ? AgapColors.businessGreenDeep.withValues(alpha: 0.42)
                  : AgapColors.borderSubtle),
          width: emphasized ? 1.5 : 1,
        ),
        gradient: glowAmber
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFBF5),
                  Color(0xFFFFF4E0),
                ],
              )
            : null,
        color: glowAmber ? null : Colors.white,
        boxShadow: shadows,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (accentBarColor != null)
            Container(
              width: 4,
              height: 92,
              margin: const EdgeInsets.only(right: 10, top: 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accentBarColor!,
                    accentBarColor!.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconBoxColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AgapColors.textMuted,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: emphasized ? 19 : 18,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 4),
                if (sub != null && sub.isNotEmpty) ...[
                  Text(
                    sub,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: microTagColor ?? AgapColors.businessGreenDeep,
                      letterSpacing: 0.2,
                    ),
                  ),
                ] else
                  const SizedBox(height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightTipCard extends StatelessWidget {
  const _InsightTipCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFD8F5E4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AgapColors.businessGreen.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: AgapColors.businessGreen.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: AgapColors.businessGreenDeep),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            AgapColors.businessGreen.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 22,
                    color: AgapColors.businessGreenDeep,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    softWrap: true,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                      color: const Color(0xFF14532D),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BizSectionCard extends StatelessWidget {
  const _BizSectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AgapColors.borderSubtle),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              const Color(0xFFFAFBFF).withValues(alpha: 0.9),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AgapColors.businessGreenDeep,
                  ),
                ),
                const Spacer(),
                Icon(
                  icon,
                  size: 20,
                  color: AgapColors.businessGreenDeep.withValues(alpha: 0.45),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _RecentHiresExpandable extends StatefulWidget {
  const _RecentHiresExpandable({required this.recentHires});

  final List<_RecentHireVm> recentHires;

  @override
  State<_RecentHiresExpandable> createState() => _RecentHiresExpandableState();
}

class _RecentHiresExpandableState extends State<_RecentHiresExpandable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hires = widget.recentHires;
    final showToggle = hires.length > 3;
    final shown = _expanded ? hires : hires.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.only(left: 32, bottom: 6),
              child: Divider(
                height: 1,
                color: Color(0xFFE5E7EB),
              ),
            ),
          _PressScale(
            child: _RecentHireRow(
              initials: applicantInitialsFromName(
                shown[i].name,
                shown[i].workerId,
              ),
              name: shown[i].name,
              role: shown[i].role,
              when: shown[i].when,
              amount: shown[i].amount,
              stars: shown[i].stars,
              relationshipTag: shown[i].relationshipTag,
              dense: true,
            ),
          ),
        ],
        if (showToggle) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AgapColors.businessGreenDeep,
              ),
              label: Text(
                _expanded ? 'Show less' : 'View all (${hires.length})',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  color: AgapColors.businessGreenDeep,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ShortcutProfileTile extends StatelessWidget {
  const _ShortcutProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AgapColors.businessGreen.withValues(alpha: 0.08),
        highlightColor: AgapColors.businessGreen.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AgapColors.businessMint.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AgapColors.businessGreen.withValues(alpha: 0.12),
                  ),
                ),
                child: Icon(
                  icon,
                  color: AgapColors.businessGreenDeep,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AgapColors.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentHireRow extends StatelessWidget {
  const _RecentHireRow({
    this.initials,
    required this.name,
    required this.role,
    required this.when,
    required this.amount,
    required this.stars,
    this.relationshipTag,
    this.dense = false,
  });

  final String? initials;
  final String name;
  final String role;
  final String when;
  final String amount;
  final int stars;
  final String? relationshipTag;
  final bool dense;

  String get _avatarText {
    if (initials != null && initials!.isNotEmpty) return initials!;
    return name.isNotEmpty ? name[0] : '?';
  }

  @override
  Widget build(BuildContext context) {
    final avatarR = dense ? 18.0 : 20.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        final amountText = Text(
          amount,
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        );
        final starsRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            5,
            (i) => Icon(
              Icons.star_rounded,
              size: 16,
              color: i < stars
                  ? const Color(0xFFEAB308)
                  : AgapColors.borderSubtle,
            ),
          ),
        );

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 12 : 10,
            vertical: dense ? 10 : 6,
          ),
          child: Row(
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: avatarR,
                backgroundColor: AgapColors.businessGreenDeep,
                child: Text(
                  _avatarText,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: initials != null && initials!.length > 1 ? 11 : 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '$role · $when',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AgapColors.textMuted,
                      ),
                    ),
                    if (relationshipTag != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AgapColors.mintSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AgapColors.businessGreen
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            relationshipTag!,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AgapColors.businessGreenDeep,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (narrow)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    amountText,
                    const SizedBox(height: 4),
                    starsRow,
                  ],
                )
              else ...[
                amountText,
                const SizedBox(width: 8),
                starsRow,
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BusinessHeaderCard extends StatelessWidget {
  const _BusinessHeaderCard({
    required this.name,
    required this.subtitle,
    required this.verified,
    required this.rating,
    required this.reviewCount,
    this.addressLine,
    this.phone,
  });

  final String name;
  final String subtitle;
  final bool verified;
  final double rating;
  final int reviewCount;
  final String? addressLine;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111827),
                            ),
                          ),
                        ),
                        if (verified) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.verified_rounded,
                            color: AgapColors.businessGreen,
                            size: 22,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AgapColors.textMuted,
                      ),
                    ),
                    if (addressLine != null &&
                        addressLine!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: AgapColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              addressLine!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF374151),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (phone != null && phone!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_outlined,
                            size: 16,
                            color: AgapColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            phone!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.star_rounded,
                  color: const Color(0xFFEAB308),
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  reviewCount > 0
                      ? '${rating.toStringAsFixed(1)} ($reviewCount reviews)'
                      : (rating > 0
                          ? rating.toStringAsFixed(1)
                          : 'No reviews yet'),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AgapColors.businessGreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatPill(
                icon: Icons.groups_rounded,
                iconColor: AgapColors.businessGreenDeep,
                label: '500+ Hires',
              ),
              _StatPill(
                icon: Icons.place_rounded,
                iconColor: const Color(0xFF2563EB),
                label: 'Multiple Locations',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AgapColors.pageBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AgapColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatefulWidget {
  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const full =
        'We operate nationwide warehousing and last-mile support for retail and e-commerce brands. '
        'Our teams value safety, punctuality, and clear communication on every shift.';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgapColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AgapColors.businessGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'About',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _expanded || full.length <= 120
                ? full
                : '${full.substring(0, 120)}…',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: const Color(0xFF374151),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: AgapColors.businessGreen,
            ),
            child: Text(
              _expanded ? 'Show less' : 'Read more',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagSpec {
  const _TagSpec(this.label, this.bg, this.fg);
  final String label;
  final Color bg;
  final Color fg;
}

class _DemoGigCard extends StatelessWidget {
  const _DemoGigCard({
    required this.title,
    required this.totalPeso,
    required this.hourlyPeso,
    required this.location,
    required this.schedule,
    required this.tags,
  });

  final String title;
  final double totalPeso;
  final double hourlyPeso;
  final String location;
  final String schedule;
  final List<_TagSpec> tags;

  @override
  Widget build(BuildContext context) {
    return _GigCardShell(
      title: title,
      totalStr: '₱${totalPeso.toStringAsFixed(0)}',
      hourlyStr: '₱${hourlyPeso.toStringAsFixed(2)}/HR',
      location: location,
      schedule: schedule,
      tags: tags,
    );
  }
}

class _GigCardFromModel extends StatelessWidget {
  const _GigCardFromModel({required this.gig, required this.tagSeed});

  final Gig gig;
  final int tagSeed;

  @override
  Widget build(BuildContext context) {
    final hours = _gigHours(gig);
    final hourly = (gig.pay.amount / 100) / hours;
    final total = gig.pay.amount / 100;
    final loc = gig.addressLabel;
    final sched =
        '${_fmtDay(gig.startAt.toLocal())}, ${_fmtTime(gig.startAt.toLocal())} - ${_fmtTime(gig.endAt.toLocal())}';
    final tags = _tagsForSeed(tagSeed);
    return _GigCardShell(
      title: gig.title,
      totalStr: '₱${total.toStringAsFixed(0)}',
      hourlyStr: '₱${hourly.toStringAsFixed(2)}/HR',
      location: loc,
      schedule: sched,
      tags: tags,
    );
  }
}

List<_TagSpec> _tagsForSeed(int seed) {
  final all = const [
    _TagSpec('High Demand', Color(0xFFDBEAFE), Color(0xFF1E40AF)),
    _TagSpec('Indoor', Color(0xFFE0F2FE), Color(0xFF0369A1)),
    _TagSpec('Certification Required', Color(0xFFFFEDD5), Color(0xFF9A3412)),
    _TagSpec('Night Shift', Color(0xFFE0E7FF), Color(0xFF4338CA)),
  ];
  final r = math.Random(seed);
  final n = 2 + r.nextInt(2);
  return List.generate(n, (i) => all[(i + seed.abs()) % all.length]);
}

double _gigHours(Gig g) {
  var h = g.endAt.difference(g.startAt).inMinutes / 60.0;
  if (h < 0.25) h = 8.0;
  return h;
}

String _fmtDay(DateTime d) {
  final today = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
  return '${d.month}/${d.day}';
}

String _fmtTime(DateTime d) {
  final h = d.hour;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = h >= 12 ? 'PM' : 'AM';
  final hr = h % 12 == 0 ? 12 : h % 12;
  return '$hr:$m $ap';
}

class _GigCardShell extends StatelessWidget {
  const _GigCardShell({
    required this.title,
    required this.totalStr,
    required this.hourlyStr,
    required this.location,
    required this.schedule,
    required this.tags,
  });

  final String title;
  final String totalStr;
  final String hourlyStr;
  final String location;
  final String schedule;
  final List<_TagSpec> tags;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgapColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    totalStr,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: AgapColors.businessGreen,
                    ),
                  ),
                  Text(
                    hourlyStr,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 16, color: AgapColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  location,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AgapColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 16,
                color: AgapColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                schedule,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AgapColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: t.bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      t.label,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.fg,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.name,
    required this.shifts,
    required this.stars,
    required this.body,
  });

  final String name;
  final int shifts;
  final int stars;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgapColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: AgapColors.businessMint,
                child: Text(
                  name.isNotEmpty ? name[0] : '?',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Worked $shifts shifts',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AgapColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: i < stars
                        ? const Color(0xFFEAB308)
                        : AgapColors.borderSubtle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.45,
              color: const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

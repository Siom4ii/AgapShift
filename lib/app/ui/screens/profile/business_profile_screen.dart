import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/business_identity.dart';
import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../ratings/mock_ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import '../../widgets/verification_status_card.dart';

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
  });

  final SessionController session;
  final MarketplaceRepository marketRepo;
  final MockRatingsRepository ratings;
  final PaymentsRepository? payments;
  final bool embedded;
  final bool showFollowFab;
  final Future<void> Function()? onLogout;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenInbox;
  final int notificationUnreadCount;

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

    var paidCentavos = 0;
    if (widget.payments != null) {
      final ledger = await widget.payments!.listLedger(userId);
      for (final t in ledger) {
        if (t.type == TransactionType.escrowFunding) {
          paidCentavos += t.amount.amount;
        }
      }
    }

    final recentHires = <_RecentHireVm>[];
    for (final a in hiredApps.take(5)) {
      final g = gigById[a.gigId];
      final wAvg = await widget.ratings.averageForUser(a.workerId);
      final stars = wAvg > 0 ? wAvg.round().clamp(1, 5) : 0;
      final payPesos = g == null ? 0 : (g.pay.amount / 100).round();
      recentHires.add(
        _RecentHireVm(
          workerId: a.workerId,
          name: _workerLabel(a.workerId),
          role: g?.title ?? 'Shift',
          when: _relativeWhen(a.createdAt.toLocal()),
          amount: '₱${_formatThousandsInt(payPesos)}',
          stars: stars,
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
      _recentHires = recentHires;
    });
  }

  String _workerLabel(String id) {
    final t = id.trim();
    if (t.length <= 12) return 'Worker $t';
    return 'Worker …${t.substring(t.length - 6)}';
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
              padding: EdgeInsets.fromLTRB(
                20,
                widget.embedded ? 12 : 8,
                20,
                widget.embedded && !widget.showFollowFab
                    ? bottomInset + 28
                    : bottomInset,
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
                    recentHires: _recentHires,
                    session: widget.session,
                    onLogout: widget.onLogout,
                    onOpenNotifications: widget.onOpenNotifications,
                    onOpenInbox: widget.onOpenInbox,
                    notificationUnreadCount: widget.notificationUnreadCount,
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
                  const SizedBox(height: 12),
                  if (_reviews.isEmpty) ...[
                    _ReviewCard(
                      name: 'Michael T.',
                      shifts: 5,
                      stars: 5,
                      body: _demoReviewBody,
                    ),
                  ] else
                    ..._reviews.map(
                      (r) => _ReviewCard(
                        name: 'Worker ${r.raterUserId.split('@').first}',
                        shifts: 3 + r.stars,
                        stars: r.stars,
                        body:
                            r.feedback ??
                            'Reliable and professional on every shift.',
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

const _demoReviewBody =
    'Outstanding partner — clear instructions, safe warehouse, and fair pay. Highly recommend for gig workers.';

class _RecentHireVm {
  const _RecentHireVm({
    required this.workerId,
    required this.name,
    required this.role,
    required this.when,
    required this.amount,
    required this.stars,
  });

  final String workerId;
  final String name;
  final String role;
  final String when;
  final String amount;
  final int stars;
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

String _initialsFromPersonName(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  if (parts.isNotEmpty && parts[0].length >= 2) {
    return parts[0].substring(0, 2).toUpperCase();
  }
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
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
    required this.recentHires,
    required this.session,
    required this.onLogout,
    this.onOpenNotifications,
    this.onOpenInbox,
    this.notificationUnreadCount = 0,
  });

  final String bizName;
  final String tagline;
  final String? addressLine;
  final String? phone;
  final double ratingShow;
  final bool verified;
  final int workersHired;
  final String totalPaidLabel;
  final List<_RecentHireVm> recentHires;
  final SessionController session;
  final Future<void> Function()? onLogout;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenInbox;
  final int notificationUnreadCount;

  static final _headerGradient = LinearGradient(
    colors: [
      AgapColors.businessGreenDeep,
      AgapColors.businessGreen,
      AgapColors.businessGreenLight,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

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
    // Tall enough that the profile card + verified footer never paint under the stats strip.
    final headerStackHeight = verified ? 332.0 : 252.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: headerStackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 120,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: _headerGradient),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'Business Profile',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (onOpenInbox != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                onPressed: onOpenInbox,
                                tooltip: 'Messages',
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
                                    size: 22,
                                  ),
                                ),
                                onPressed: onOpenNotifications,
                                tooltip: 'Notifications',
                              ),
                            ),
                          ),
                        Material(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Edit profile (demo)'),
                                ),
                              );
                            },
                            tooltip: 'Edit',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: 68,
                child: Material(
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
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
                                color: AgapColors.businessGreen,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _initials,
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          bizName,
                                          style: GoogleFonts.inter(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF111827),
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                      if (verified)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 6,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AgapColors.mintSurface,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.verified_rounded,
                                                  size: 14,
                                                  color:
                                                      AgapColors.businessGreen,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Verified',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                    color: AgapColors
                                                        .primaryBright,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    tagline,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: AgapColors.textMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      ...List.generate(
                                        5,
                                        (i) => Padding(
                                          padding: const EdgeInsets.only(
                                            right: 2,
                                          ),
                                          child: Icon(
                                            Icons.star_rounded,
                                            size: 20,
                                            color: i <
                                                    math.min(
                                                      5,
                                                      ratingShow.round(),
                                                    ) &&
                                                ratingShow > 0
                                                ? const Color(0xFFEAB308)
                                                : AgapColors.borderSubtle,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        ratingShow > 0
                                            ? ratingShow.toStringAsFixed(1)
                                            : '—',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: const Color(0xFFEAB308),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (addressLine != null &&
                            addressLine!.trim().isNotEmpty) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 20,
                                color: AgapColors.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  addressLine!,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF374151),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (phone != null && phone!.trim().isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(
                                Icons.phone_outlined,
                                size: 20,
                                color: const Color(0xFFDB2777),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  phone!,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF374151),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if ((addressLine == null || addressLine!.trim().isEmpty) &&
                            (phone == null || phone!.trim().isEmpty))
                          Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 20,
                                color: AgapColors.textMuted,
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Icons.phone_outlined,
                                size: 20,
                                color: const Color(0xFFDB2777),
                              ),
                            ],
                          ),
                        if (verified) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Divider(
                              height: 1,
                              color: AgapColors.borderSubtle,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 20,
                                  color: AgapColors.businessGreen,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Account verified · Full access to AgapShift features',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AgapColors.businessGreen,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!verified) ...[
          VerificationStatusCard(session: session),
          const SizedBox(height: 16),
        ],
        _UnifiedStatsStrip(
          workersHired: workersHired,
          ratingLabel: ratingShow > 0 ? ratingShow.toStringAsFixed(1) : '—',
          totalPaidLabel: totalPaidLabel,
        ),
        const SizedBox(height: 20),
        Text(
          'Recent Hires',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AgapColors.borderSubtle),
          ),
          child: recentHires.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No hires recorded yet. Hire applicants from your job posts.',
                    style: GoogleFonts.inter(
                      color: AgapColors.textMuted,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < recentHires.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _RecentHireRow(
                        initials: _initialsFromPersonName(recentHires[i].name),
                        name: recentHires[i].name,
                        role: recentHires[i].role,
                        when: recentHires[i].when,
                        amount: recentHires[i].amount,
                        stars: recentHires[i].stars,
                        dense: true,
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 20),
        Text(
          'Shortcuts',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AgapColors.borderSubtle),
          ),
          child: Column(
            children: [
              _SlimProfileTile(
                icon: Icons.description_outlined,
                title: 'Business Documents',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Business documents')),
                ),
              ),
              const Divider(height: 1),
              _SlimProfileTile(
                icon: Icons.history_rounded,
                title: 'Hiring History',
                onTap: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Hiring history'))),
              ),
              const Divider(height: 1),
              _SlimProfileTile(
                icon: Icons.insights_outlined,
                title: 'Expense Analytics',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Expense analytics')),
                ),
              ),
              const Divider(height: 1),
              _SlimProfileTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                onTap: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Notifications'))),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
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
    );
  }
}

/// Single bordered row instead of three separate stat cards.
class _UnifiedStatsStrip extends StatelessWidget {
  const _UnifiedStatsStrip({
    required this.workersHired,
    required this.ratingLabel,
    required this.totalPaidLabel,
  });

  final int workersHired;
  final String ratingLabel;
  final String totalPaidLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgapColors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCell(
              icon: Icons.groups_outlined,
              iconColor: const Color(0xFF6D28D9),
              value: '$workersHired',
              valueColor: AgapColors.businessGreen,
              label: 'Workers hired',
            ),
          ),
          Container(width: 1, height: 44, color: AgapColors.borderSubtle),
          Expanded(
            child: _StatCell(
              icon: Icons.star_rounded,
              iconColor: const Color(0xFFEAB308),
              value: ratingLabel,
              valueColor: const Color(0xFFEAB308),
              label: 'Rating',
            ),
          ),
          Container(width: 1, height: 44, color: AgapColors.borderSubtle),
          Expanded(
            child: _StatCell(
              icon: Icons.payments_outlined,
              iconColor: AgapColors.textMuted,
              value: totalPaidLabel,
              valueColor: const Color(0xFF111827),
              label: 'Total paid',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.valueColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final Color valueColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AgapColors.textMuted,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlimProfileTile extends StatelessWidget {
  const _SlimProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      leading: Icon(icon, color: AgapColors.businessGreen, size: 22),
      title: Text(
        title,
        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: AgapColors.textMuted,
        size: 22,
      ),
      onTap: onTap,
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
    this.dense = false,
  });

  final String? initials;
  final String name;
  final String role;
  final String when;
  final String amount;
  final int stars;
  final bool dense;

  String get _avatarText {
    if (initials != null && initials!.isNotEmpty) return initials!;
    return name.isNotEmpty ? name[0] : '?';
  }

  @override
  Widget build(BuildContext context) {
    final avatarR = dense ? 18.0 : 20.0;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 12 : 10,
        vertical: dense ? 10 : 6,
      ),
      child: Row(
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
              ],
            ),
          ),
          Text(amount, style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Row(
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
          ),
        ],
      ),
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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/business_identity.dart';
import '../../../../domain/enums.dart';
import '../../../../domain/worker_identity.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../subscriptions/worker_subscription_screen.dart';
import '../ratings/user_ratings_screen.dart';

/// Worker profile primary blue (mock).
const Color _kProfileBlue = Color(0xFF1A4384);

/// Success green for badges / earnings (mock).
const Color _kProfileGreen = Color(0xFF4CAF50);

String _initialsFromName(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.isEmpty) return '•';
  if (parts.length == 1) {
    final p = parts.single;
    return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p[0].toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

class WorkerProfileScreen extends StatefulWidget {
  const WorkerProfileScreen({
    super.key,
    required this.session,
    required this.shiftRepo,
    required this.ratings,
    required this.marketRepo,
    required this.payments,
    this.embedded = false,
    this.onOpenMessages,
    this.inboxUnreadCount = 0,
    this.onOpenNotifications,
    this.onLogout,
  });

  final SessionController session;
  final ShiftRepository shiftRepo;
  final RatingsRepository ratings;
  final MarketplaceRepository marketRepo;
  final PaymentsRepository payments;
  final bool embedded;
  final VoidCallback? onOpenMessages;
  final int inboxUnreadCount;
  final VoidCallback? onOpenNotifications;
  final Future<void> Function()? onLogout;

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _RecentShiftVm {
  const _RecentShiftVm({
    required this.title,
    required this.businessName,
    required this.businessInitials,
    required this.payLabel,
    required this.dateLabel,
    required this.ratingStars,
  });

  final String title;
  final String businessName;
  final String businessInitials;
  final String payLabel;
  final String dateLabel;
  final double ratingStars;
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  double _avg = 0;
  int _completed = 0;
  WorkerIdentityDisplay? _worker;
  int _applicationsCount = 0;
  List<_RecentShiftVm> _recentShifts = const [];

  @override
  void initState() {
    super.initState();
    _worker = widget.session.state.workerIdentity;
    _load();
  }

  WorkerIdentityDisplay? get _effectiveWorker =>
      _worker ?? widget.session.state.workerIdentity;

  Future<Map<String, String>> _businessNamesForIds(Set<String> ids) async {
    final out = <String, String>{};
    for (final id in ids) {
      out[id] = 'Business';
    }
    if (!SupabaseConfig.isConfigured || ids.isEmpty) return out;
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id,identity_snapshot')
          .inFilter('id', ids.toList());
      final list = rows as List<dynamic>;
      for (final raw in list) {
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
    final userId = appActorId(widget.session, mockFallback: '');
    final avg = await widget.ratings.averageForUser(userId);
    final sessions = await widget.shiftRepo.listShiftSessions();
    final completed = sessions
        .where((s) => s.workerId == userId && s.checkOutAt != null)
        .toList();

    final apps = await widget.marketRepo.listApplications();
    final applicationsCount =
        apps.where((a) => a.workerId == userId).length;

    completed.sort(
      (a, b) => (b.checkOutAt ?? DateTime(1970)).compareTo(
        a.checkOutAt ?? DateTime(1970),
      ),
    );
    final recentSessions = completed.take(5).toList();

    final gigs = await widget.marketRepo.listGigs();
    final gigById = {for (final g in gigs) g.id: g};

    final businessIds =
        recentSessions.map((s) => s.businessId).toSet();
    final names = await _businessNamesForIds(businessIds);

    WorkerIdentityDisplay? identity;
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
            identity = workerIdentityFromProfileIdentitySnapshot(
              row['identity_snapshot'],
            );
          }
        }
      } catch (_) {}
    }

    final recentVm = <_RecentShiftVm>[];
    for (final s in recentSessions) {
      final gig = gigById[s.gigId];
      final title = gig?.title ?? 'Shift';
      final business = names[s.businessId] ?? 'Business';
      final payLabel = gig != null ? _formatPhp(gig.pay.amount) : '—';
      final dateLabel = _shiftSubtitleDate(s.checkOutAt);
      recentVm.add(
        _RecentShiftVm(
          title: title,
          businessName: business,
          businessInitials: _initialsFromName(business),
          payLabel: payLabel,
          dateLabel: dateLabel,
          ratingStars: avg > 0 ? avg : 0,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _avg = avg;
      _completed = completed.length;
      _worker = identity;
      _applicationsCount = applicationsCount;
      _recentShifts = recentVm;
    });
  }

  static String _formatPhp(int centavos) {
    final php = centavos / 100.0;
    if (php >= 1000) {
      final k = php / 1000;
      if (k >= 10) return '₱${k.toStringAsFixed(0)}k';
      return '₱${k.toStringAsFixed(1)}k';
    }
    return '₱${php.toStringAsFixed(0)}';
  }

  static String _shiftSubtitleDate(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(local.year, local.month, local.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}';
  }

  String get _displayName {
    final w = _effectiveWorker;
    if (w != null && w.displayName.trim().isNotEmpty) {
      return w.displayName.trim();
    }
    return 'Worker';
  }

  String _avatarInitials(String name) => _initialsFromName(name);

  bool get _verified =>
      widget.session.state.accountStatus == AccountStatus.verified;

  String get _locationLine {
    final a = _effectiveWorker?.addressLine?.trim();
    if (a != null && a.isNotEmpty) return a;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final hasRating = _avg > 0;
    final ratingText = hasRating
        ? '${_avg.toStringAsFixed(1)} ($_completed shifts)'
        : 'No ratings yet ($_completed shifts)';

    final highlightRating = hasRating && _avg >= 4.0;
    final highlightCompleted = !highlightRating && _completed > 0;
    final highlightApps =
        !highlightRating && !highlightCompleted && _applicationsCount > 0;

    final body = ColoredBox(
      color: const Color(0xFFF3F4F6),
      child: RefreshIndicator(
        color: _kProfileBlue,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(0, 0, 0, widget.embedded ? 100 : 24),
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
                            _kProfileBlue,
                            const Color(0xFF2563EB),
                            const Color(0xFF8EB4F0),
                            const Color(0xFFD5E1F5),
                            const Color(0xFFE8EDF5),
                            const Color(0xFFF3F4F6),
                          ],
                          stops: const [0.0, 0.14, 0.38, 0.58, 0.78, 1.0],
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
                          color: Colors.white.withValues(alpha: 0.09),
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
                          color: Colors.white.withValues(alpha: 0.06),
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
                            color: Colors.white.withValues(alpha: 0.05),
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
                            if (widget.onOpenMessages != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Material(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.antiAlias,
                                  child: IconButton(
                                    tooltip: 'Messages',
                                    icon: Badge(
                                      isLabelVisible:
                                          widget.inboxUnreadCount > 0,
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
                                      ),
                                    ),
                                    onPressed: widget.onOpenMessages,
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
                                      content: Text(
                                        'Profile editing coming soon',
                                      ),
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
                        child: _ProfileSummaryCard(
                          initials: _avatarInitials(_displayName),
                          name: _displayName,
                          verified: _verified,
                          ratingText: ratingText,
                          hasRating: hasRating,
                          ratingValue: _avg,
                          locationLine: _locationLine,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _PressScale(
                                child: _MetricCard(
                                  iconBoxColor: _kProfileGreen,
                                  icon: Icons.check_rounded,
                                  iconColor: Colors.white,
                                  value: '$_completed',
                                  valueColor: _kProfileBlue,
                                  label: 'Shifts Done',
                                  microTag: _completed >= 3
                                      ? 'On a roll'
                                      : (_completed > 0 ? 'Solid track' : null),
                                  microTagColor: const Color(0xFF059669),
                                  emphasized: highlightCompleted,
                                  accentBarColor: highlightCompleted
                                      ? _kProfileGreen
                                      : null,
                                  rewardGlow: false,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _PressScale(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () {
                                    final userId = appActorId(
                                      widget.session,
                                      mockFallback: '',
                                    );
                                    if (userId.isEmpty) return;
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) => UserRatingsScreen(
                                          ratings: widget.ratings,
                                          userId: userId,
                                          title: 'My reviews',
                                        ),
                                      ),
                                    );
                                  },
                                  child: _MetricCard(
                                    iconBoxColor: const Color(0xFFFFF8E1),
                                    icon: Icons.star_rounded,
                                    iconColor: const Color(0xFFFFC107),
                                    value: hasRating
                                        ? _avg.toStringAsFixed(1)
                                        : '—',
                                    valueColor: const Color(0xFFE65100),
                                    label: 'Avg Rating',
                                    microTag: !hasRating
                                        ? null
                                        : (_avg >= 4.5
                                            ? 'Top rated'
                                            : (_avg >= 4.0
                                                ? 'Excellent'
                                                : 'Keep it up')),
                                    microTagColor: const Color(0xFFE65100),
                                    emphasized: highlightRating,
                                    accentBarColor: highlightRating
                                        ? const Color(0xFFFFB300)
                                        : null,
                                    rewardGlow: highlightRating,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _PressScale(
                                child: _MetricCard(
                                  iconBoxColor: const Color(0xFFE8EFFF),
                                  icon: Icons.send_rounded,
                                  iconColor: const Color(0xFF5C6BC0),
                                  value: '$_applicationsCount',
                                  valueColor: _kProfileBlue,
                                  label: 'Applications',
                                  microTag: _applicationsCount > 0
                                      ? 'Stay visible'
                                      : null,
                                  microTagColor: const Color(0xFF3949AB),
                                  emphasized: highlightApps,
                                  accentBarColor: highlightApps
                                      ? const Color(0xFF5C6BC0)
                                      : null,
                                  rewardGlow: false,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _RecentShiftsCard(shifts: _recentShifts),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _WorkerPremiumSubscriptionTile(
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => WorkerSubscriptionScreen(
                        session: widget.session,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ProfileMenuCard(
                onResume: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Resume (demo)')),
                  );
                },
                onCertifications: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Certifications (demo)')),
                  );
                },
                onIdVerification: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ID verification (demo)')),
                  );
                },
                onMessages: widget.onOpenMessages,
                onNotifications: widget.onOpenNotifications,
                onLogout: widget.onLogout,
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(top: false, child: body),
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

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({
    required this.initials,
    required this.name,
    required this.verified,
    required this.ratingText,
    required this.hasRating,
    required this.ratingValue,
    required this.locationLine,
  });

  final String initials;
  final String name;
  final bool verified;
  final String ratingText;
  final bool hasRating;
  final double ratingValue;
  final String locationLine;

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
                color: const Color(0xFF2E7D32),
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
                            color: _kProfileBlue,
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
                            color: _kProfileGreen,
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ...List.generate(5, (i) {
                        final filled = hasRating && i < ratingValue.round().clamp(0, 5);
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
                  if (locationLine.isNotEmpty) ...[
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
                            locationLine,
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
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
          color: const Color(0xFFFFC107).withValues(alpha: 0.38),
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
          color: _kProfileBlue.withValues(alpha: 0.18),
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
                  ? _kProfileBlue.withValues(alpha: 0.42)
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
                      color: microTagColor ?? const Color(0xFF059669),
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

class _RecentShiftsCard extends StatelessWidget {
  const _RecentShiftsCard({required this.shifts});

  final List<_RecentShiftVm> shifts;

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
                  'Recent Shifts',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _kProfileBlue,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.history_rounded,
                  size: 20,
                  color: _kProfileBlue.withValues(alpha: 0.45),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (shifts.isEmpty)
              Text(
                'Completed shifts will appear here after you check out.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.45,
                  color: AgapColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              ...shifts.asMap().entries.map((e) {
                final i = e.key;
                final s = e.value;
                final isLast = i == shifts.length - 1;
                return Column(
                  children: [
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.only(left: 32, bottom: 6),
                        child: Divider(height: 1, color: Color(0xFFE5E7EB)),
                      ),
                    _PressScale(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                          border: Border.all(
                                            color: const Color(0xFF2563EB),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      if (!isLast)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Container(
                                            width: 2,
                                            height: 52,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  const Color(0xFF2563EB)
                                                      .withValues(alpha: 0.45),
                                                  const Color(0xFF2563EB)
                                                      .withValues(alpha: 0.08),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF6366F1),
                                        Color(0xFF8B5CF6),
                                      ],
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    s.businessInitials,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              s.title,
                                              style: GoogleFonts.inter(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: const Color(0xFF111827),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDCFCE7),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.check_circle_rounded,
                                                  size: 13,
                                                  color: _kProfileGreen,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Completed',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: const Color(
                                                      0xFF166534,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${s.businessName} · ${s.dateLabel}',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AgapColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      s.payLabel,
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(5, (si) {
                                        final filled = s.ratingStars > 0 &&
                                            si <
                                                s.ratingStars
                                                    .round()
                                                    .clamp(0, 5);
                                        return Icon(
                                          Icons.star_rounded,
                                          size: 14,
                                          color: filled
                                              ? const Color(0xFFFFC107)
                                              : const Color(0xFFE0E0E0),
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _WorkerPremiumSubscriptionTile extends StatefulWidget {
  const _WorkerPremiumSubscriptionTile({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_WorkerPremiumSubscriptionTile> createState() =>
      _WorkerPremiumSubscriptionTileState();
}

class _WorkerPremiumSubscriptionTileState
    extends State<_WorkerPremiumSubscriptionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      child: Material(
        elevation: 7,
        shadowColor: const Color(0xFF5B21B6).withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final v = _ctrl.value;
              return LayoutBuilder(
                builder: (context, c) {
                  final bandLeft = -100.0 + (c.maxWidth + 200) * v;
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    fit: StackFit.passthrough,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-1.1 + 2.2 * v, -0.85),
                              end: Alignment(0.35 + 2.2 * v, 1.05),
                              colors: const [
                                Color(0xFF6D28D9),
                                Color(0xFF9D74F2),
                                Color(0xFF7C3AED),
                                Color(0xFF4C1D95),
                              ],
                              stops: const [0.0, 0.32, 0.62, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: bandLeft,
                        top: 0,
                        bottom: 0,
                        width: 96,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.transparent,
                                  Colors.white.withValues(alpha: 0.18),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.22),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.workspace_premium_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Worker subscription',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Most workers get hired 2x faster',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withValues(
                                        alpha: 0.95,
                                      ),
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Priority placement, boosts, and hiring insights',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuCard extends StatelessWidget {
  const _ProfileMenuCard({
    required this.onResume,
    required this.onCertifications,
    required this.onIdVerification,
    required this.onMessages,
    required this.onNotifications,
    required this.onLogout,
  });

  final VoidCallback onResume;
  final VoidCallback onCertifications;
  final VoidCallback onIdVerification;
  final VoidCallback? onMessages;
  final VoidCallback? onNotifications;
  final Future<void> Function()? onLogout;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AgapColors.borderSubtle),
        ),
        child: Column(
          children: [
            _PressScale(
              child: _MenuRow(
                icon: Icons.description_outlined,
                iconBg: const Color(0xFFE3F2FD),
                iconColor: const Color(0xFF1565C0),
                title: 'My Resume',
                onTap: onResume,
              ),
            ),
            const Divider(height: 1),
            _PressScale(
              child: _MenuRow(
                icon: Icons.workspace_premium_outlined,
                iconBg: const Color(0xFFFFF8E1),
                iconColor: const Color(0xFFF9A825),
                title: 'Certifications',
                onTap: onCertifications,
              ),
            ),
            const Divider(height: 1),
            _PressScale(
              child: _MenuRow(
                icon: Icons.verified_user_outlined,
                iconBg: const Color(0xFFE8F5E9),
                iconColor: _kProfileGreen,
                title: 'ID Verification',
                onTap: onIdVerification,
              ),
            ),
            if (onMessages != null) ...[
              const Divider(height: 1),
              _PressScale(
                child: _MenuRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  iconBg: const Color(0xFFE3F2FD),
                  iconColor: _kProfileBlue,
                  title: 'Messages',
                  onTap: onMessages!,
                ),
              ),
            ],
            const Divider(height: 1),
            _PressScale(
              child: _MenuRow(
                icon: Icons.notifications_outlined,
                iconBg: const Color(0xFFE1F5FE),
                iconColor: const Color(0xFF0277BD),
                title: 'Notifications',
                onTap: onNotifications ?? () {},
              ),
            ),
            if (onLogout != null) ...[
              const Divider(height: 1),
              _PressScale(
                child: _MenuRow(
                  icon: Icons.logout_rounded,
                  iconBg: const Color(0xFFFFEBEE),
                  iconColor: const Color(0xFFC62828),
                  title: 'Log out',
                  onTap: () => onLogout!(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFD),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: _kProfileBlue.withValues(alpha: 0.1),
        highlightColor: Colors.white.withValues(alpha: 0.65),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

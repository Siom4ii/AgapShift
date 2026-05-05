import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/business_identity.dart';
import '../../../../domain/enums.dart';
import '../../../../domain/worker_identity.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../ratings/mock_ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';

/// Worker profile primary blue (mock).
const Color _kProfileBlue = Color(0xFF1A4384);

/// Success green for badges / earnings (mock).
const Color _kProfileGreen = Color(0xFF4CAF50);

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
    this.onOpenNotifications,
    this.onLogout,
  });

  final SessionController session;
  final ShiftRepository shiftRepo;
  final MockRatingsRepository ratings;
  final MarketplaceRepository marketRepo;
  final PaymentsRepository payments;
  final bool embedded;
  final VoidCallback? onOpenMessages;
  final VoidCallback? onOpenNotifications;
  final Future<void> Function()? onLogout;

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _RecentShiftVm {
  const _RecentShiftVm({
    required this.title,
    required this.businessName,
    required this.payLabel,
    required this.dateLabel,
    required this.ratingStars,
  });

  final String title;
  final String businessName;
  final String payLabel;
  final String dateLabel;
  final double ratingStars;
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  double _avg = 0;
  int _completed = 0;
  WorkerIdentityDisplay? _worker;
  int _totalEarnedCentavos = 0;
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

    final wallet = await widget.payments.getWallet(userId);
    final totalEarned = wallet.available.amount + wallet.pending.amount;

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
      _totalEarnedCentavos = totalEarned;
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

  String _avatarInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return 'W';
    if (parts.length == 1) {
      final p = parts.single;
      return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

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
              alignment: Alignment.topCenter,
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(20, topInset + 12, 12, 56),
                  color: _kProfileBlue,
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
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: Colors.white,
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
                          icon: const Icon(Icons.edit_rounded, color: Colors.white),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile editing coming soon'),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: topInset + 56,
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
              ],
            ),
            const SizedBox(height: 88),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      iconBoxColor: _kProfileGreen,
                      icon: Icons.check_rounded,
                      iconColor: Colors.white,
                      value: '$_completed',
                      valueColor: _kProfileBlue,
                      label: 'Shifts Done',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      iconBoxColor: const Color(0xFFFFF8E1),
                      icon: Icons.star_rounded,
                      iconColor: const Color(0xFFFFC107),
                      value: hasRating ? _avg.toStringAsFixed(1) : '—',
                      valueColor: const Color(0xFFE65100),
                      label: 'Avg Rating',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      iconBoxColor: const Color(0xFFEFEBE9),
                      icon: Icons.paid_rounded,
                      iconColor: const Color(0xFF5D4037),
                      value: _totalEarnedCentavos > 0
                          ? _formatPhp(_totalEarnedCentavos)
                          : '₱0',
                      valueColor: _kProfileGreen,
                      label: 'Total Earned',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _RecentShiftsCard(shifts: _recentShifts),
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
        padding: const EdgeInsets.all(16),
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
                  const SizedBox(height: 8),
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
  });

  final Color iconBoxColor;
  final IconData icon;
  final Color iconColor;
  final String value;
  final Color valueColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgapColors.borderSubtle),
      ),
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
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AgapColors.textMuted,
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
    return Container(
      width: double.infinity,
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
          Text(
            'Recent Shifts',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _kProfileBlue,
            ),
          ),
          const SizedBox(height: 12),
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
              return Column(
                children: [
                  if (i > 0) const Divider(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: _kProfileGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.title,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${s.businessName} • ${s.dateLabel}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AgapColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                            children: List.generate(5, (i) {
                              final filled = s.ratingStars > 0 &&
                                  i < s.ratingStars.round().clamp(0, 5);
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
                ],
              );
            }),
        ],
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
    return Container(
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
        children: [
          _MenuRow(
            icon: Icons.description_outlined,
            iconBg: const Color(0xFFE3F2FD),
            iconColor: const Color(0xFF1565C0),
            title: 'My Resume',
            onTap: onResume,
          ),
          const Divider(height: 1),
          _MenuRow(
            icon: Icons.workspace_premium_outlined,
            iconBg: const Color(0xFFFFF8E1),
            iconColor: const Color(0xFFF9A825),
            title: 'Certifications',
            onTap: onCertifications,
          ),
          const Divider(height: 1),
          _MenuRow(
            icon: Icons.verified_user_outlined,
            iconBg: const Color(0xFFE8F5E9),
            iconColor: _kProfileGreen,
            title: 'ID Verification',
            onTap: onIdVerification,
          ),
          if (onMessages != null) ...[
            const Divider(height: 1),
            _MenuRow(
              icon: Icons.chat_bubble_outline_rounded,
              iconBg: const Color(0xFFE3F2FD),
              iconColor: _kProfileBlue,
              title: 'Messages',
              onTap: onMessages!,
            ),
          ],
          const Divider(height: 1),
          _MenuRow(
            icon: Icons.notifications_outlined,
            iconBg: const Color(0xFFE1F5FE),
            iconColor: const Color(0xFF0277BD),
            title: 'Notifications',
            onTap: onNotifications ?? () {},
          ),
          if (onLogout != null) ...[
            const Divider(height: 1),
            _MenuRow(
              icon: Icons.logout_rounded,
              iconBg: const Color(0xFFFFEBEE),
              iconColor: const Color(0xFFC62828),
              title: 'Log out',
              onTap: () => onLogout!(),
            ),
          ],
        ],
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
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
    );
  }
}

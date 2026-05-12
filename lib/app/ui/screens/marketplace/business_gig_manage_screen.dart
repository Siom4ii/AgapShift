import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../notifications/notification_repository.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../ratings/rate_user_screen.dart';
import '../shift/employer_attendance_qr_screen.dart';
import 'business_gig_applicants_screen.dart';

class BusinessGigManageScreen extends StatefulWidget {
  const BusinessGigManageScreen({
    super.key,
    required this.gig,
    required this.session,
    required this.repo,
    required this.notifications,
    required this.ratings,
    required this.shiftRepo,
  });

  final Gig gig;
  final SessionController session;
  final MarketplaceRepository repo;
  final NotificationRepository notifications;
  final RatingsRepository ratings;
  final ShiftRepository shiftRepo;

  @override
  State<BusinessGigManageScreen> createState() => _BusinessGigManageScreenState();
}

class _BusinessGigManageScreenState extends State<BusinessGigManageScreen> {
  bool _loadingAttendance = false;
  String? _attendanceError;
  String? _hiredWorkerId;
  List<ShiftDaySummary> _summaries = const [];
  int _ratingRefreshTick = 0;
  int _applicantCount = 0;

  static const _bg = Color(0xFFF6F7FB);
  static const _titleNavy = Color(0xFF0F172A);

  static final _headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AgapColors.businessGreenDeep,
      AgapColors.businessGreen,
      AgapColors.businessGreenLight,
    ],
  );

  @override
  void initState() {
    super.initState();
    _loadAttendance();
    _loadApplicantsCount();
  }

  String _dateLine(DateTime a, DateTime b) {
    String fmt(DateTime d) {
      final l = d.toLocal();
      return '${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')}/${l.year}';
    }

    if (fmt(a) == fmt(b)) return fmt(a);
    return '${fmt(a)} → ${fmt(b)}';
  }

  String _timeLine(DateTime a, DateTime b) {
    String t(DateTime d) {
      final l = d.toLocal();
      final h = l.hour;
      final ap = h >= 12 ? 'PM' : 'AM';
      final hr = h % 12 == 0 ? 12 : h % 12;
      final m = l.minute.toString().padLeft(2, '0');
      return '$hr:$m $ap';
    }

    return '${t(a)} – ${t(b)}';
  }

  Future<void> _loadAttendance() async {
    setState(() {
      _loadingAttendance = true;
      _attendanceError = null;
    });
    try {
      final wid = await widget.repo.getHiredWorkerId(widget.gig.id);
      if (wid == null || wid.isEmpty) {
        if (!mounted) return;
        setState(() {
          _hiredWorkerId = null;
          _summaries = const [];
        });
        return;
      }
      final rows = await widget.shiftRepo.listWorkDaySummaries(
        gigId: widget.gig.id,
        workerId: wid,
      );
      if (!mounted) return;
      setState(() {
        _hiredWorkerId = wid;
        _summaries = rows;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _attendanceError = '$e');
    } finally {
      if (mounted) setState(() => _loadingAttendance = false);
    }
  }

  Future<void> _loadApplicantsCount() async {
    try {
      final apps = await widget.repo.listApplicants(widget.gig.id);
      if (!mounted) return;
      setState(() => _applicantCount = apps.length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _applicantCount = 0);
    }
  }

  Future<void> _openApplicants() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BusinessGigApplicantsScreen(
          repo: widget.repo,
          notifications: widget.notifications,
          session: widget.session,
          gig: widget.gig,
          ratings: widget.ratings,
          shiftRepo: widget.shiftRepo,
        ),
      ),
    );
    await _loadAttendance();
    await _loadApplicantsCount();
  }

  Future<void> _openQr(AttendanceScanType type) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EmployerAttendanceQrScreen(
          shiftRepo: widget.shiftRepo,
          gig: widget.gig,
          initialType: type,
        ),
      ),
    );
    await _loadAttendance();
  }

  bool _allCheckedOutForGig(Gig g, List<ShiftDaySummary> rows) {
    if (rows.isEmpty) return false;
    final start = g.startAt.toLocal();
    final end = g.endAt.toLocal();
    var cur = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    final byDay = <String, ShiftDaySummary>{};
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    for (final r in rows) {
      final l = r.workDay.toLocal();
      byDay[key(DateTime(l.year, l.month, l.day))] = r;
    }
    while (!cur.isAfter(last)) {
      final s = byDay[key(cur)];
      if (s?.checkOut == null) return false;
      cur = cur.add(const Duration(days: 1));
    }
    return true;
  }

  Future<void> _openRateWorker({
    required String businessUserId,
    required String workerId,
    required Gig gig,
  }) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RateUserScreen(
          ratings: widget.ratings,
          gigId: gig.id,
          raterUserId: businessUserId,
          ratedUserId: workerId,
          title: 'Rate the worker for "${gig.title}"',
        ),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      setState(() => _ratingRefreshTick++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gig;
    final payDay = (g.pay.amount / 100).round();
    final expired = !g.endAt.toUtc().isAfter(DateTime.now().toUtc());
    final completed =
        g.status == GigStatus.completed || expired || _allCheckedOutForGig(g, _summaries);
    final multiDay = g.startAt.toLocal().day != g.endAt.toLocal().day ||
        g.startAt.toLocal().month != g.endAt.toLocal().month ||
        g.startAt.toLocal().year != g.endAt.toLocal().year;
    final businessUserId = appActorId(widget.session, mockFallback: '');
    final attendanceLockedReason = expired
        ? 'Attendance is disabled for expired listings.'
        : (_hiredWorkerId == null
            ? 'Hire a worker to enable attendance tracking.'
            : null);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadAttendance,
          color: AgapColors.businessGreen,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(gradient: _headerGradient),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                right: -40,
                                top: -24,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 160,
                                    height: 160,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          Colors.white.withValues(alpha: 0.08),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: -52,
                                top: 56,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 140,
                                    height: 140,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          Colors.white.withValues(alpha: 0.06),
                                    ),
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Material(
                                        color: Colors.white.withValues(alpha: 0.22),
                                        shape: const CircleBorder(),
                                        clipBehavior: Clip.antiAlias,
                                        child: IconButton(
                                          onPressed: () =>
                                              Navigator.of(context).maybePop(),
                                          icon: const Icon(
                                            Icons.arrow_back_ios_new_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Job listing',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white.withValues(
                                                  alpha: 0.9,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              g.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                height: 1.15,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.16,
                                              ),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.work_rounded,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${g.category} · ₱$payDay/day',
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${_dateLine(g.startAt, g.endAt)} • ${_timeLine(g.startAt, g.endAt)}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white.withValues(
                                                    alpha: 0.9,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  _Pill(
                                                    label: completed
                                                        ? 'Completed'
                                                        : (expired ? 'Expired' : 'Open'),
                                                    bg: Colors.white.withValues(
                                                      alpha: 0.18,
                                                    ),
                                                    fg: Colors.white,
                                                    border: Colors.white.withValues(
                                                      alpha: 0.22,
                                                    ),
                                                  ),
                                                  if (g.workersNeeded != null &&
                                                      g.workersNeeded! > 0)
                                                    _Pill(
                                                      label:
                                                          '${_hiredWorkerId == null ? 0 : 1}/${g.workersNeeded} hired',
                                                      bg: Colors.white.withValues(
                                                        alpha: 0.18,
                                                      ),
                                                      fg: Colors.white,
                                                      border: Colors.white.withValues(
                                                        alpha: 0.22,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        FilledButton(
                                          onPressed: _openApplicants,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            foregroundColor:
                                                AgapColors.businessGreenDeep,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                          child: Text(
                                            _applicantCount > 0
                                                ? 'Applicants ($_applicantCount)'
                                                : 'Applicants',
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Column(
                      children: [
                        _SectionCard(
                          title: 'Overview',
                          child: Column(
                            children: [
                              _InfoTile(
                                icon: Icons.place_outlined,
                                label: 'Work site',
                                value: g.addressLabel,
                              ),
                              const SizedBox(height: 10),
                              _InfoTile(
                                icon: Icons.calendar_today_outlined,
                                label: 'Dates',
                                value: _dateLine(g.startAt, g.endAt),
                              ),
                              const SizedBox(height: 10),
                              _InfoTile(
                                icon: Icons.schedule_rounded,
                                label: 'Time',
                                value: _timeLine(g.startAt, g.endAt),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (completed &&
                            _hiredWorkerId != null &&
                            businessUserId.isNotEmpty) ...[
                          _SectionCard(
                            title: 'Rating',
                            child: FutureBuilder<Rating?>(
                              key: ValueKey('rate_${g.id}_$_ratingRefreshTick'),
                              future: widget.ratings.getForShift(
                                gigId: g.id,
                                raterUserId: businessUserId,
                                ratedUserId: _hiredWorkerId!,
                              ),
                              builder: (context, snap) {
                                if (snap.connectionState == ConnectionState.waiting) {
                                  return Row(
                                    children: [
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Loading…',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          color: AgapColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  );
                                }
                                final r = snap.data;
                                if (r == null) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'This listing is done. You can rate the worker now.',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w700,
                                          color: AgapColors.textMuted,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: () => _openRateWorker(
                                            businessUserId: businessUserId,
                                            workerId: _hiredWorkerId!,
                                            gig: g,
                                          ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AgapColors.businessGreen,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 13),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                          icon: const Icon(Icons.rate_review_rounded),
                                          label: Text(
                                            'Rate worker',
                                            style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          color: Color(0xFFF59E0B),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '${r.stars}/5',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w900,
                                            color: _titleNavy,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          'Submitted',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w800,
                                            color: AgapColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if ((r.feedback ?? '').trim().isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        r.feedback!.trim(),
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w600,
                                          height: 1.45,
                                          color: _titleNavy,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _SectionCard(
                          title: 'Details',
                          child: _DetailsBreakdown(description: g.description),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'Attendance (Clock in/out)',
                          trailing: _loadingAttendance
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton(
                                  tooltip: 'Refresh',
                                  onPressed: _loadAttendance,
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _BannerNote(
                                tone: (expired || _hiredWorkerId == null)
                                    ? _BannerTone.info
                                    : _BannerTone.success,
                                text: expired
                                    ? 'This listing is expired. Attendance QR is disabled.'
                                    : _hiredWorkerId == null
                                    ? 'No hired worker yet. Once you hire someone, they can scan your QR to record attendance.'
                                    : 'Show the QR and let the worker scan it for check-in and check-out.',
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: (expired || _hiredWorkerId == null)
                                          ? null
                                          : () => _openQr(AttendanceScanType.checkIn),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AgapColors.businessGreen,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 13),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      icon: const Icon(Icons.login_rounded),
                                      label: Text(
                                        'Check-in QR',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: (expired || _hiredWorkerId == null)
                                          ? null
                                          : () => _openQr(AttendanceScanType.checkOut),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AgapColors.businessGreenDeep,
                                        side: BorderSide(
                                          color: AgapColors.businessGreenDeep.withValues(alpha: 0.35),
                                        ),
                                        padding: const EdgeInsets.symmetric(vertical: 13),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                      icon: const Icon(Icons.logout_rounded),
                                      label: Text(
                                        'Check-out QR',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (attendanceLockedReason != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.lock_outline_rounded,
                                      size: 16,
                                      color:
                                          AgapColors.textMuted.withValues(alpha: 0.85),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        attendanceLockedReason,
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          height: 1.35,
                                          fontWeight: FontWeight.w600,
                                          color: AgapColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 14),
                              if (_attendanceError != null)
                                _InlineError(text: _attendanceError!)
                              else if (_hiredWorkerId == null)
                                const SizedBox.shrink()
                              else if (_summaries.isEmpty)
                                Text(
                                  'No scans yet.',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    color: AgapColors.textMuted,
                                  ),
                                )
                              else ...[
                                for (final s in _summaries)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _AttendanceDayRow(summary: s),
                                  ),
                                if (multiDay)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      'Multi-day gig: select the correct day when showing the QR.',
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AgapColors.textMuted,
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
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
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AgapColors.borderSubtle.withValues(alpha: 0.95)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AgapColors.businessMint.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AgapColors.businessGreenDeep.withValues(alpha: 0.12),
            ),
          ),
          child: Icon(icon, size: 18, color: AgapColors.businessGreenDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                  color: AgapColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: fg,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _DetailsBreakdown extends StatelessWidget {
  const _DetailsBreakdown({required this.description});

  final String description;

  static const _kTitleNavy = Color(0xFF0F172A);

  ({String? desc, String? req, String? benefits, String? workers}) _split() {
    final raw = description.trim();
    if (raw.isEmpty) return (desc: null, req: null, benefits: null, workers: null);

    String? takeLineValue(String prefix) {
      final m = RegExp(
        '^\\s*${RegExp.escape(prefix)}\\s*:\\s*(.+)\\s*\$',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(raw);
      return m?.group(1)?.trim();
    }

    final req = takeLineValue('Requirements');
    final benefits = takeLineValue('Benefits');
    final workers = takeLineValue('Workers needed');

    // Description = lines that are not the labeled lines above.
    final filtered = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .where(
          (l) =>
              !l.toLowerCase().startsWith('requirements:') &&
              !l.toLowerCase().startsWith('benefits:') &&
              !l.toLowerCase().startsWith('workers needed:'),
        )
        .toList();
    final desc = filtered.isEmpty ? null : filtered.join('\n');

    return (desc: desc, req: req, benefits: benefits, workers: workers);
  }

  @override
  Widget build(BuildContext context) {
    final parts = _split();

    Widget row({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AgapColors.businessMint.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AgapColors.businessGreenDeep.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: AgapColors.businessGreenDeep,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w800,
                    color: AgapColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                    color: _kTitleNavy,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final children = <Widget>[];
    if ((parts.desc ?? '').trim().isNotEmpty) {
      children.add(
        row(
          icon: Icons.description_outlined,
          label: 'Description',
          value: parts.desc!.trim(),
        ),
      );
    }
    if ((parts.req ?? '').trim().isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 12));
      children.add(
        row(
          icon: Icons.checklist_rounded,
          label: 'Requirements',
          value: parts.req!.trim(),
        ),
      );
    }
    if ((parts.benefits ?? '').trim().isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 12));
      children.add(
        row(
          icon: Icons.card_giftcard_rounded,
          label: 'Benefits',
          value: parts.benefits!.trim(),
        ),
      );
    }
    if ((parts.workers ?? '').trim().isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 12));
      children.add(
        row(
          icon: Icons.groups_outlined,
          label: 'Workers needed',
          value: parts.workers!.trim(),
        ),
      );
    }

    if (children.isEmpty) {
      return Text(
        description,
        style: GoogleFonts.inter(
          fontSize: 13.5,
          height: 1.55,
          fontWeight: FontWeight.w500,
          color: _kTitleNavy,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

enum _BannerTone { info, success }

class _BannerNote extends StatelessWidget {
  const _BannerNote({required this.tone, required this.text});

  final _BannerTone tone;
  final String text;

  Color get _bg => switch (tone) {
        _BannerTone.info => const Color(0xFFEFF6FF),
        _BannerTone.success => const Color(0xFFECFDF5),
      };

  Color get _border => switch (tone) {
        _BannerTone.info => const Color(0xFFBFDBFE),
        _BannerTone.success => const Color(0xFFBBF7D0),
      };

  Color get _fg => switch (tone) {
        _BannerTone.info => const Color(0xFF1E40AF),
        _BannerTone.success => const Color(0xFF065F46),
      };

  IconData get _icon => switch (tone) {
        _BannerTone.info => Icons.info_outline_rounded,
        _BannerTone.success => Icons.check_circle_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: _fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12.8,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: _fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB91C1C),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceDayRow extends StatelessWidget {
  const _AttendanceDayRow({required this.summary});

  final ShiftDaySummary summary;

  String _dayLabel(DateTime d) {
    final l = d.toLocal();
    return '${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')}/${l.year}';
  }

  String _time(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    final h = l.hour;
    final ap = h >= 12 ? 'PM' : 'AM';
    final hr = h % 12 == 0 ? 12 : h % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '$hr:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgapColors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dayLabel(summary.workDay),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'In: ${_time(summary.checkIn)}  •  Out: ${_time(summary.checkOut)}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: AgapColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.qr_code_2_rounded, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }
}


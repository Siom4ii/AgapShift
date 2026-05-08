import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../location/user_geo_point.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../location/davao_del_sur_scope.dart';
import '../../../profile/worker_display_names.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../shift/shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import '../ratings/rate_user_screen.dart';
import 'worker_attendance_scan_screen.dart';

class WorkerShiftScreen extends StatefulWidget {
  const WorkerShiftScreen({
    super.key,
    required this.marketRepo,
    required this.shiftRepo,
    required this.session,
    this.showAppBar = true,
  });

  final MarketplaceRepository marketRepo;
  final ShiftRepository shiftRepo;
  final SessionController session;
  final bool showAppBar;

  @override
  State<WorkerShiftScreen> createState() => _WorkerShiftScreenState();
}

class _WorkerShiftScreenState extends State<WorkerShiftScreen> {
  bool _loading = false;
  String? _error;
  Gig? _gig;
  /// True when this gig is only an application — worker is not hired yet (no QR).
  bool _isAwaitingHire = false;
  List<ShiftDaySummary> _daySummaries = const [];
  /// Local calendar day selected for QR & summary (start of day).
  DateTime? _selectedWorkDayLocal;
  GeoPoint _distanceAnchor = DavaoDelSurScope.defaultCenter;
  String? _ratingPromptedForGigId;
  int _ratingRefreshTick = 0;
  /// Employer display + gig category (under job title). Never raw UUIDs.
  String _employerLine = '';

  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<DateTime> _gigCalendarDays(Gig g) {
    final s = g.startAt.toLocal();
    final e = g.endAt.toLocal();
    var cur = DateTime(s.year, s.month, s.day);
    final end = DateTime(e.year, e.month, e.day);
    final out = <DateTime>[];
    while (!cur.isAfter(end)) {
      out.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return out;
  }

  String _ymdLocal(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  ShiftDaySummary? _summaryForDay(DateTime localDay, [List<ShiftDaySummary>? rows]) {
    final list = rows ?? _daySummaries;
    final key = _ymdLocal(localDay);
    for (final s in list) {
      if (_ymdLocal(s.workDay) == key) return s;
    }
    return null;
  }

  bool _shiftFullyCheckedOut(Gig gig, List<ShiftDaySummary> summaries) {
    final span = _gigCalendarDays(gig);
    if (span.isEmpty) return false;
    for (final d in span) {
      if (_summaryForDay(d, summaries)?.checkOut == null) return false;
    }
    return true;
  }

  String _shortDateLabel(DateTime localDay) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final l = localDay.toLocal();
    return '${months[l.month - 1]} ${l.day}';
  }

  Future<void> _openScan({
    required Gig gig,
    required String workerId,
  }) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WorkerAttendanceScanScreen(
          shiftRepo: widget.shiftRepo,
          gig: gig,
          workerId: workerId,
        ),
      ),
    );
    if (ok == true) {
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userPt = await tryGetCurrentUserGeoPoint();
      final workerId = appActorId(widget.session, mockFallback: '');
      final gigs = await widget.marketRepo.listGigs();
      final gigById = {for (final g in gigs) g.id: g};
      Gig? selected;
      var awaitingHire = false;

      if (workerId.isNotEmpty) {
        final apps = await widget.marketRepo.listApplications();

        final hiredGigIds = apps
            .where(
              (a) =>
                  a.workerId == workerId &&
                  a.status == ApplicationStatus.hired,
            )
            .map((a) => a.gigId)
            .toSet();
        final hiredGigs = <Gig>[];
        for (final gid in hiredGigIds) {
          final g = gigById[gid] ?? await widget.marketRepo.getGig(gid);
          if (g == null) continue;
          if (g.status == GigStatus.cancelled) continue;
          hiredGigs.add(g);
        }
        // Prefer the active/nearest hired gig (not just the oldest one),
        // otherwise workers can be shown the wrong shift and see "Pending".
        final now = DateTime.now().toUtc();
        Gig? pickNearest(List<Gig> list) {
          if (list.isEmpty) return null;
          Gig? best;
          int? bestScore;
          for (final g in list) {
            final s = g.startAt.toUtc();
            final e = g.endAt.toUtc();
            final int score;
            if (!now.isBefore(s) && now.isBefore(e)) {
              // Active gigs first.
              score = 0;
            } else if (now.isBefore(s)) {
              // Upcoming: sooner is better.
              score = 10 + s.difference(now).inMinutes.abs();
            } else {
              // Past: most recently ended is better.
              score = 1000 + now.difference(e).inMinutes.abs();
            }
            if (best == null || (bestScore != null && score < bestScore)) {
              best = g;
              bestScore = score;
            }
          }
          return best ?? list.first;
        }
        hiredGigs.sort((a, b) => a.startAt.compareTo(b.startAt));

        if (hiredGigs.isNotEmpty) {
          selected = pickNearest(hiredGigs);
          awaitingHire = false;
        } else {
          final pendingGigs = <Gig>[];
          for (final a in apps) {
            if (a.workerId != workerId ||
                a.status != ApplicationStatus.applied) {
              continue;
            }
            final g = gigById[a.gigId] ?? await widget.marketRepo.getGig(a.gigId);
            if (g == null) continue;
            if (g.status == GigStatus.cancelled) continue;
            if (g.status == GigStatus.completed) continue;
            if (g.status == GigStatus.filled ||
                g.status == GigStatus.ongoing) {
              final hw = await widget.marketRepo.getHiredWorkerId(g.id);
              if (hw != null && hw != workerId) continue;
            }
            pendingGigs.add(g);
          }
          pendingGigs.sort((a, b) => a.startAt.compareTo(b.startAt));
          if (pendingGigs.isNotEmpty) {
            selected = pendingGigs.first;
            awaitingHire = true;
          }
        }
      }

      List<ShiftDaySummary> summaries = const [];
      DateTime? selectedDay;
      if (selected != null && !awaitingHire && workerId.isNotEmpty) {
        summaries = await widget.shiftRepo.listWorkDaySummaries(
          gigId: selected.id,
          workerId: workerId,
        );
        final span = _gigCalendarDays(selected);
        if (span.isNotEmpty) {
          final n = DateTime.now();
          final today = DateTime(n.year, n.month, n.day);
          final startLocal = selected.startAt.toLocal();
          final endLocal = selected.endAt.toLocal();
          final startDay = DateTime(startLocal.year, startLocal.month, startLocal.day);
          final endDay = DateTime(endLocal.year, endLocal.month, endLocal.day);
          final preferredDay = (today.isBefore(startDay) || today.isAfter(endDay))
              ? startDay
              : today;
          selectedDay = span.firstWhere(
            (d) => _ymdLocal(d) == _ymdLocal(preferredDay),
            orElse: () => span.first,
          );
        }
      }

      var employerLine = '';
      if (selected != null) {
        employerLine = await _employerSubtitleForGig(selected);
      }

      if (!mounted) return;
      setState(() {
        _distanceAnchor = userPt ?? DavaoDelSurScope.defaultCenter;
        _gig = selected;
        _isAwaitingHire = awaitingHire;
        _daySummaries = summaries;
        _selectedWorkDayLocal = selectedDay;
        _employerLine = employerLine;
      });
      await _maybePromptRatingAfterShiftComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _employerSubtitleForGig(Gig g) async {
    final bizName = await _fetchBusinessDisplayName(g.businessId);
    final cat = g.category.trim();
    if (cat.isNotEmpty) return '$bizName · $cat';
    return bizName;
  }

  Future<String> _fetchBusinessDisplayName(String businessId) async {
    if (businessId.isEmpty) return 'Business';
    final m = await fetchWorkerDisplayNamesById({businessId});
    final n = m[businessId]?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Business';
  }

  Future<void> _maybePromptRatingAfterShiftComplete() async {
    final gig = _gig;
    final workerId = appActorId(widget.session, mockFallback: '');
    if (gig == null ||
        workerId.isEmpty ||
        !_shiftFullyCheckedOut(gig, _daySummaries) ||
        _ratingPromptedForGigId == gig.id) {
      return;
    }
    _ratingPromptedForGigId = gig.id;
    final gigAfter = await widget.marketRepo.getGig(gig.id);
    if (gigAfter == null || !mounted) return;
    final ratings = MarketplaceScope.of(context).ratings;
    final existing = await ratings.getForShift(
      gigId: gig.id,
      raterUserId: workerId,
      ratedUserId: gigAfter.businessId,
    );
    if (!mounted || existing != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RateUserScreen(
          ratings: ratings,
          gigId: gig.id,
          raterUserId: workerId,
          ratedUserId: gigAfter.businessId,
          title: 'Rate the business for "${gigAfter.title}"',
        ),
      ),
    );
  }

  Future<void> _openRateBusiness({
    required RatingsRepository ratings,
    required Gig gig,
    required String workerId,
  }) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RateUserScreen(
          ratings: ratings,
          gigId: gig.id,
          raterUserId: workerId,
          ratedUserId: gig.businessId,
          title: 'Rate the business for "${gig.title}"',
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
    final gig = _gig;
    final selDay = _selectedWorkDayLocal;
    final daySum =
        gig != null && selDay != null ? _summaryForDay(selDay) : null;
    final checkIn = daySum?.checkIn?.toLocal();
    final checkOut = daySum?.checkOut?.toLocal();
    final allDone =
        gig != null && _shiftFullyCheckedOut(gig, _daySummaries);
    final loadingNoGig = _loading && gig == null;
    final status = loadingNoGig
        ? 'Loading…'
        : gig == null
            ? 'No shift assigned'
            : _isAwaitingHire
                ? 'Application pending'
                : allDone
                    ? 'Completed'
                    : _daySummaries.any((s) => s.checkIn != null)
                        ? 'In progress'
                        : 'Upcoming';

    final payPhp = gig == null ? 0 : (gig.pay.amount / 100.0).round();
    final distanceKm = gig == null
        ? 0.0
        : _distanceKm(
            _distanceAnchor,
            gig.location,
          );

    final canCheckIn = gig != null &&
        !_isAwaitingHire &&
        selDay != null &&
        checkIn == null;
    final canCheckOut = gig != null &&
        !_isAwaitingHire &&
        selDay != null &&
        checkIn != null &&
        checkOut == null;
    final showAttendanceScan =
        gig != null && !_isAwaitingHire && (canCheckIn || canCheckOut);
    final spanDays = gig == null ? const <DateTime>[] : _gigCalendarDays(gig);
    final multiDay = spanDays.length > 1;
    final dayCtx =
        multiDay && selDay != null ? _shortDateLabel(selDay) : null;
    final workerId = appActorId(widget.session, mockFallback: '');
    final ratings = MarketplaceScope.of(context).ratings;

    final body = SafeArea(
      child: ShellChromeBackground(
        kind: ShellChromeKind.worker,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            children: [
              Row(
                children: [
                  if (widget.showAppBar)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        borderRadius: BorderRadius.circular(999),
                        child: Ink(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AgapColors.borderSubtle.withValues(
                                alpha: 0.9,
                              ),
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Shift',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: loadingNoGig
                                    ? const Color(0xFF2563EB)
                                    : gig == null
                                        ? const Color(0xFF9CA3AF)
                                        : _isAwaitingHire || status == 'Upcoming'
                                            ? const Color(0xFFF59E0B)
                                            : status == 'In progress'
                                                ? const Color(0xFF22C55E)
                                                : const Color(0xFF6B7280),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              status,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AgapColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_loading && gig != null)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _InlineError(message: _error!, onRetry: _load),
                ),
              if (loadingNoGig)
                const _LoadingShiftCard()
              else if (gig == null)
                _EmptyShiftCard(now: _now)
              else
                _ShiftSummaryCard(
                  title: gig.title,
                  company: _employerLine.isNotEmpty ? _employerLine : 'Business',
                  payPhp: payPhp,
                  checkIn: checkIn,
                  checkOut: checkOut,
                  applicationPending: _isAwaitingHire,
                  selectedDayLabel: dayCtx,
                ),
              const SizedBox(height: 14),
              if (gig != null)
                _LocationCard(
                  address: gig.addressLabel,
                  distanceKm: distanceKm,
                ),
              if (gig != null) ...[
                const SizedBox(height: 14),
                if (_isAwaitingHire)
                  _AwaitingHireNote()
                else ...[
                  if (multiDay)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _WorkDayChipsRow(
                        days: spanDays,
                        selected: selDay,
                        ymdLocal: _ymdLocal,
                        labelFor: _shortDateLabel,
                        onSelect: (d) {
                          setState(() => _selectedWorkDayLocal = d);
                        },
                      ),
                    ),
                  _DailyAttendanceSection(
                    gig: gig,
                    summaries: _daySummaries,
                    ymdLocal: _ymdLocal,
                    shortLabel: _shortDateLabel,
                  ),
                  const SizedBox(height: 12),
                  if (allDone && workerId.isNotEmpty) ...[
                    _RatingListingCard(
                      key: ValueKey('rate_${gig.id}_$_ratingRefreshTick'),
                      future: ratings.getForShift(
                        gigId: gig.id,
                        raterUserId: workerId,
                        ratedUserId: gig.businessId,
                      ),
                      onRate: () => _openRateBusiness(
                        ratings: ratings,
                        gig: gig,
                        workerId: workerId,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showAttendanceScan && workerId.isNotEmpty) ...[
                    _ScanEmployerQrCard(
                      isCheckOut: canCheckOut,
                      multiDay: multiDay,
                      dayLabel: _shortDateLabel(selDay),
                      onScan: () => _openScan(gig: gig, workerId: workerId),
                    ),
                    const SizedBox(height: 12),
                    _SecurityNote(),
                  ],
                ],
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!widget.showAppBar) {
      return body;
    }
    return Scaffold(backgroundColor: AgapColors.pageBackground, body: body);
  }
}

class _ShiftSummaryCard extends StatelessWidget {
  const _ShiftSummaryCard({
    required this.title,
    required this.company,
    required this.payPhp,
    required this.checkIn,
    required this.checkOut,
    this.applicationPending = false,
    this.selectedDayLabel,
  });

  final String title;
  final String company;
  final int payPhp;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final bool applicationPending;
  /// When set, times are for this calendar workday (multi-day gigs).
  final String? selectedDayLabel;

  @override
  Widget build(BuildContext context) {
    String t(DateTime? d) {
      if (d == null) return 'Pending';
      final h = d.hour;
      final am = h >= 12 ? 'PM' : 'AM';
      final hr = h % 12 == 0 ? 12 : h % 12;
      final m = d.minute.toString().padLeft(2, '0');
      return '$hr:$m $am';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      applicationPending
                          ? 'Applied gig'
                          : (selectedDayLabel != null
                              ? 'Shift · $selectedDayLabel'
                              : 'Today\'s Shift'),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      company,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Pay',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱$payPhp',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (applicationPending)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Text(
                'Check-in & check-out unlock after the business hires you.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: Colors.white,
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    icon: Icons.schedule_rounded,
                    label: 'Check-in',
                    value: t(checkIn),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiniStat(
                    icon: Icons.schedule_rounded,
                    label: 'Check-out',
                    value: t(checkOut),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.95)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
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

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.address, required this.distanceKm});
  final String address;
  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AgapColors.borderSubtle.withValues(alpha: 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.place_rounded, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job Location',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  address,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${distanceKm.toStringAsFixed(1)} km from your location',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6366F1),
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

class _ScanEmployerQrCard extends StatelessWidget {
  const _ScanEmployerQrCard({
    required this.isCheckOut,
    required this.multiDay,
    required this.dayLabel,
    required this.onScan,
  });

  final bool isCheckOut;
  final bool multiDay;
  final String? dayLabel;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final title = isCheckOut ? 'Check-out — scan employer' : 'Check-in — scan employer';
    final subtitle = isCheckOut
        ? (multiDay && dayLabel != null
            ? 'Scan the employer QR to clock out for $dayLabel.'
            : 'Scan the employer QR to end this workday.')
        : (multiDay && dayLabel != null
            ? 'Scan the employer QR to clock in for $dayLabel.'
            : 'Scan the employer QR to start this workday.');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AgapColors.borderSubtle.withValues(alpha: 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF2563EB).withValues(alpha: 0.18),
              ),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AgapColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onScan,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              'Scan',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _AwaitingHireNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You\'ve applied for this gig. Check-in opens after the business hires you.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E40AF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Each workday needs its own check-in and check-out scan. Pick the day above, '
              'then scan the employer QR.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkDayChipsRow extends StatelessWidget {
  const _WorkDayChipsRow({
    required this.days,
    required this.selected,
    required this.ymdLocal,
    required this.labelFor,
    required this.onSelect,
  });

  final List<DateTime> days;
  final DateTime? selected;
  final String Function(DateTime) ymdLocal;
  final String Function(DateTime) labelFor;
  final void Function(DateTime) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Workdays',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final d in days) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      labelFor(d),
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                    selected: selected != null && ymdLocal(d) == ymdLocal(selected!),
                    onSelected: (_) => onSelect(d),
                    selectedColor: const Color(0xFFDDD6FE),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: AgapColors.borderSubtle.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyAttendanceSection extends StatelessWidget {
  const _DailyAttendanceSection({
    required this.gig,
    required this.summaries,
    required this.ymdLocal,
    required this.shortLabel,
  });

  final Gig gig;
  final List<ShiftDaySummary> summaries;
  final String Function(DateTime) ymdLocal;
  final String Function(DateTime) shortLabel;

  String _t(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    final h24 = l.hour;
    final h = h24 > 12 ? h24 - 12 : (h24 == 0 ? 12 : h24);
    final ap = h24 >= 12 ? 'PM' : 'AM';
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final s = gig.startAt.toLocal();
    final e = gig.endAt.toLocal();
    var cur = DateTime(s.year, s.month, s.day);
    final end = DateTime(e.year, e.month, e.day);
    final span = <DateTime>[];
    while (!cur.isAfter(end)) {
      span.add(cur);
      cur = cur.add(const Duration(days: 1));
    }

    ShiftDaySummary? forDay(DateTime d) {
      final key = ymdLocal(d);
      for (final x in summaries) {
        if (ymdLocal(x.workDay) == key) return x;
      }
      return null;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AgapColors.borderSubtle.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance by day',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),
          for (final d in span)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      shortLabel(d),
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'In ${_t(forDay(d)?.checkIn)} · Out ${_t(forDay(d)?.checkOut)}',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: AgapColors.textMuted,
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

class _RatingListingCard extends StatelessWidget {
  const _RatingListingCard({
    super.key,
    required this.future,
    required this.onRate,
  });

  final Future<Rating?> future;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AgapColors.borderSubtle.withValues(alpha: 0.95),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FutureBuilder<Rating?>(
        future: future,
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
                  'Loading rating…',
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
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rate this listing',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your shift is completed. Please rate the business.',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: AgapColors.textMuted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onRate,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.rate_review_rounded),
                    label: Text(
                      'Rate business',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900),
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
                  const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  Text(
                    '${r.stars}/5',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Your rating',
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
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ],
          );
        },
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
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingShiftCard extends StatelessWidget {
  const _LoadingShiftCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AgapColors.borderSubtle.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading your shift…',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hang on while we fetch your schedule.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AgapColors.textMuted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyShiftCard extends StatelessWidget {
  const _EmptyShiftCard({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AgapColors.borderSubtle.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No active shift yet',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Once you\'re hired for a gig, your shift details will appear here.',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AgapColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Now: ${now.toLocal()}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AgapColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

double _distanceKm(GeoPoint a, GeoPoint b) {
  final dx = (a.lat - b.lat) * 111000.0;
  final dy = (a.lng - b.lng) * 111000.0;
  return (math.sqrt(dx * dx + dy * dy)) / 1000.0;
}

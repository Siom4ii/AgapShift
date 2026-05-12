import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../location/user_geo_point.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../supabase/supabase_config.dart';
import '../../../location/davao_del_sur_scope.dart';
import '../../../profile/worker_display_names.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../shift/shift_repository.dart';
import '../../../shift/worker_hired_shift_display.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import '../ratings/rate_user_screen.dart';
import '../ratings/user_ratings_screen.dart';
import 'worker_attendance_scan_screen.dart';

/// Human-readable duration between check-in and check-out (local times).
String? formatWorkedDuration(DateTime? checkIn, DateTime? checkOut) {
  if (checkIn == null || checkOut == null) return null;
  final start = checkIn.toLocal();
  final end = checkOut.toLocal();
  final diff = end.difference(start);
  if (diff.isNegative) return null;
  if (diff.inMinutes < 1) return 'Under 1 min';
  final h = diff.inHours;
  final m = diff.inMinutes.remainder(60);
  if (h >= 1) return '${h}h ${m}m';
  final mins = diff.inMinutes;
  return '$mins min${mins == 1 ? '' : 's'}';
}

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

  /// Whether the worker already submitted a rating for this gig (from server).
  bool _hasRating = false;

  /// Employer account verified (Supabase `profiles.account_status`).
  bool _employerVerified = false;
  DateTime? _ratingCreatedAt;

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

  /// True when the gig's scheduled window has ended (UTC vs [Gig.endAt]).
  bool _gigPastEnd(Gig g) => DateTime.now().toUtc().isAfter(g.endAt.toUtc());

  String _shiftSummaryTopBadge({
    required Gig gig,
    required bool awaitingHire,
    required bool multiDay,
    required DateTime? selDay,
    String? dayCtx,
  }) {
    if (awaitingHire) return 'Applied gig';
    if (multiDay && dayCtx != null) return 'Shift · $dayCtx';
    final span = gigCalendarDaysLocal(gig);
    if (span.isEmpty) return "Today's Shift";
    final anchor = selDay ?? span.first;
    final anchorDay = DateTime(anchor.year, anchor.month, anchor.day);
    final n = _now;
    final today = DateTime(n.year, n.month, n.day);
    if (ymdLocal(today) == ymdLocal(anchorDay)) return "Today's Shift";
    return 'Shift · ${_shortDateLabel(anchorDay)}';
  }

  String _shortDateLabel(DateTime localDay) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final l = localDay.toLocal();
    return '${months[l.month - 1]} ${l.day}';
  }

  String _workerFirstName() {
    final n = widget.session.state.workerIdentity?.displayName.trim();
    if (n == null || n.isEmpty) {
      final e = widget.session.state.email ?? '';
      if (e.isEmpty) return 'there';
      return e.split('@').first;
    }
    return n.split(RegExp(r'\s+')).first;
  }

  String _headerGreetingForHour() {
    final h = _now.hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _headerDateLine() {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = _now;
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  int _completedWorkdaysWithCheckoutToday() {
    final n = _now;
    final today = DateTime(n.year, n.month, n.day);
    var c = 0;
    for (final s in _daySummaries) {
      final wd = DateTime(
        s.workDay.year,
        s.workDay.month,
        s.workDay.day,
      );
      if (wd == today && s.checkOut != null) c++;
    }
    return c;
  }

  String _relativeAgo(DateTime pastLocal, DateTime nowLocal) {
    final diff = nowLocal.difference(pastLocal);
    if (diff.isNegative || diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m min${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hr${h == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 14) {
      final d = diff.inDays;
      return '$d day${d == 1 ? '' : 's'} ago';
    }
    return 'recently';
  }

  String? _headerStatusSubtitle({
    required Gig? gig,
    required String status,
    required bool loadingNoGig,
    required DateTime now,
    DateTime? latestCheckout,
    DateTime? ratingCreatedAt,
  }) {
    if (loadingNoGig) return null;
    if (gig == null) {
      return 'Browse open jobs when you\'re ready for your next shift.';
    }
    if (_isAwaitingHire) {
      return 'Waiting for the employer to hire you — then check-in unlocks.';
    }
    switch (status) {
      case 'Completed':
        final n = _completedWorkdaysWithCheckoutToday();
        if (n > 0) {
          return n == 1
              ? 'You completed 1 workday today. Nice work.'
              : 'You completed $n workdays today. Nice work.';
        }
        final parts = <String>['This shift is fully checked out. Well done.'];
        if (latestCheckout != null) {
          parts.add('Checked out ${_relativeAgo(latestCheckout, now)}');
        }
        if (ratingCreatedAt != null) {
          final rLocal = ratingCreatedAt.toLocal();
          final rDay = DateTime(rLocal.year, rLocal.month, rLocal.day);
          final nDay = DateTime(now.year, now.month, now.day);
          if (rDay == nDay) {
            parts.add('Rating shared today');
          } else if (now.difference(ratingCreatedAt).inHours < 72) {
            parts.add('Rating shared ${_relativeAgo(rLocal, now)}');
          }
        }
        return parts.join(' · ');
      case 'In progress':
        return 'You\'re on the clock — scan check-out when you finish.';
      case 'Upcoming':
        return 'Your shift hasn\'t started yet. Check-in opens on the workday.';
      case 'Expired':
        return 'This shift ended before attendance was finished in the app.';
      case 'Application pending':
        return null;
      default:
        return null;
    }
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
        hiredGigs.sort((a, b) => a.startAt.compareTo(b.startAt));

        if (hiredGigs.isNotEmpty) {
          selected = await pickDisplayedHiredShift(
            hiredGigs: hiredGigs,
            workerId: workerId,
            shiftRepo: widget.shiftRepo,
          );
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
        final span = gigCalendarDaysLocal(selected);
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
            (d) => ymdLocal(d) == ymdLocal(preferredDay),
            orElse: () => span.first,
          );
        }
      }

      var employerLine = '';
      if (selected != null) {
        employerLine = await _employerSubtitleForGig(selected);
      }

      var hasRating = false;
      Rating? ratingSnap;
      if (selected != null && !awaitingHire && workerId.isNotEmpty) {
        if (!mounted) return;
        try {
          final ratings = MarketplaceScope.of(context).ratings;
          final existing = await ratings.getForShift(
            gigId: selected.id,
            raterUserId: workerId,
            ratedUserId: selected.businessId,
          );
          hasRating = existing != null;
          ratingSnap = existing;
        } catch (_) {}
      }

      var employerVerified = false;
      if (selected != null) {
        employerVerified = await _fetchEmployerVerified(selected.businessId);
      }

      if (!mounted) return;
      setState(() {
        _distanceAnchor = userPt ?? DavaoDelSurScope.defaultCenter;
        _gig = selected;
        _isAwaitingHire = awaitingHire;
        _daySummaries = summaries;
        _selectedWorkDayLocal = selectedDay;
        _employerLine = employerLine;
        _hasRating = hasRating;
        _employerVerified = employerVerified;
        _ratingCreatedAt = ratingSnap?.createdAt;
      });
      await _maybePromptRatingAfterShiftComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _fetchEmployerVerified(String businessId) async {
    if (!SupabaseConfig.isConfigured || businessId.isEmpty) return false;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('account_status')
          .eq('id', businessId)
          .maybeSingle();
      return (row?['account_status'] as String?) ==
          AccountStatus.verified.name;
    } catch (_) {
      return false;
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
        !shiftFullyCheckedOut(gig, _daySummaries) ||
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
      setState(() {
        _hasRating = true;
        _ratingRefreshTick++;
        _ratingCreatedAt = DateTime.now();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gig = _gig;
    final selDay = _selectedWorkDayLocal;
    final daySum =
        gig != null && selDay != null
            ? shiftDaySummaryFor(selDay, _daySummaries)
            : null;
    final checkIn = daySum?.checkIn?.toLocal();
    final checkOut = daySum?.checkOut?.toLocal();
    final allDone =
        gig != null && shiftFullyCheckedOut(gig, _daySummaries);
    final gigPastEnd = gig != null && _gigPastEnd(gig);
    final expiredIncomplete = gig != null && gigPastEnd && !allDone;
    final loadingNoGig = _loading && gig == null;
    final status = loadingNoGig
        ? 'Loading…'
        : gig == null
            ? 'No shift assigned'
            : _isAwaitingHire
                ? 'Application pending'
                : expiredIncomplete
                    ? 'Expired'
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
        checkIn == null &&
        !gigPastEnd;
    final canCheckOut = gig != null &&
        !_isAwaitingHire &&
        selDay != null &&
        checkIn != null &&
        checkOut == null &&
        !gigPastEnd;
    final showAttendanceScan = gig != null &&
        !_isAwaitingHire &&
        (canCheckIn || canCheckOut) &&
        !expiredIncomplete;
    final spanDays = gig == null ? const <DateTime>[] : gigCalendarDaysLocal(gig);
    final multiDay = spanDays.length > 1;
    final dayCtx =
        multiDay && selDay != null ? _shortDateLabel(selDay) : null;
    final workerId = appActorId(widget.session, mockFallback: '');
    final ratings = MarketplaceScope.of(context).ratings;
    DateTime? latestCheckoutLocal;
    for (final s in _daySummaries) {
      final t = s.checkOut;
      if (t != null) {
        final l = t.toLocal();
        if (latestCheckoutLocal == null || l.isAfter(latestCheckoutLocal)) {
          latestCheckoutLocal = l;
        }
      }
    }
    final headerSubtitle = _headerStatusSubtitle(
      gig: gig,
      status: status,
      loadingNoGig: loadingNoGig,
      now: _now,
      latestCheckout: latestCheckoutLocal,
      ratingCreatedAt: _ratingCreatedAt,
    );
    final workDurationLabel = formatWorkedDuration(checkIn, checkOut);

    final body = SafeArea(
      child: ShellChromeBackground(
        kind: ShellChromeKind.worker,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          '${_headerGreetingForHour()}, ${_workerFirstName()} 👋',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _headerDateLine(),
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AgapColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ShiftStatusPill(status: status, loading: loadingNoGig),
                        if (headerSubtitle != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            headerSubtitle,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'My Shift',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.25,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_loading && gig != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
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
              else ...[
                _ShiftSummaryCard(
                  title: gig.title,
                  company: _employerLine.isNotEmpty ? _employerLine : 'Business',
                  employerVerified: _employerVerified,
                  payPhp: payPhp,
                  checkIn: checkIn,
                  checkOut: checkOut,
                  applicationPending: _isAwaitingHire,
                  workDurationLabel: workDurationLabel,
                  topBadge: (gigPastEnd && !allDone)
                      ? 'Expired shift'
                      : _shiftSummaryTopBadge(
                          gig: gig,
                          awaitingHire: _isAwaitingHire,
                          multiDay: multiDay,
                          selDay: selDay,
                          dayCtx: dayCtx,
                        ),
                ),
                if (!_isAwaitingHire) ...[
                  const SizedBox(height: 12),
                  _ShiftProgressTimeline(
                    checkedIn: checkIn != null,
                    checkedOut: checkOut != null,
                    rated: _hasRating,
                  ),
                ],
              ],
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
                        ymdLocal: ymdLocal,
                        labelFor: _shortDateLabel,
                        onSelect: (d) {
                          setState(() => _selectedWorkDayLocal = d);
                        },
                      ),
                    ),
                  _DailyAttendanceSection(
                    gig: gig,
                    summaries: _daySummaries,
                    ymdLocal: ymdLocal,
                    shortLabel: _shortDateLabel,
                  ),
                  const SizedBox(height: 12),
                  if (allDone && workerId.isNotEmpty) ...[
                    _RatingListingCard(
                      key: ValueKey('rate_${gig.id}_$_ratingRefreshTick'),
                      employerLine: _employerLine,
                      employerVerified: _employerVerified,
                      businessUserId: gig.businessId,
                      ratings: ratings,
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

class _ShiftStatusPill extends StatelessWidget {
  const _ShiftStatusPill({
    required this.status,
    required this.loading,
  });

  final String status;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late IconData icon;
    var label = status;

    if (loading) {
      bg = const Color(0xFFDBEAFE).withValues(alpha: 0.88);
      fg = const Color(0xFF1D4ED8);
      icon = Icons.hourglass_top_rounded;
    } else {
      switch (status) {
        case 'Completed':
          bg = const Color(0xFFD1FAE5).withValues(alpha: 0.92);
          fg = const Color(0xFF047857);
          icon = Icons.check_circle_rounded;
          label = 'Completed';
          break;
        case 'In progress':
          bg = const Color(0xFFDCFCE7).withValues(alpha: 0.9);
          fg = const Color(0xFF15803D);
          icon = Icons.bolt_rounded;
          break;
        case 'Upcoming':
          bg = const Color(0xFFFEF3C7).withValues(alpha: 0.92);
          fg = const Color(0xFFB45309);
          icon = Icons.event_available_rounded;
          break;
        case 'Expired':
          bg = const Color(0xFFE2E8F0).withValues(alpha: 0.95);
          fg = const Color(0xFF475569);
          icon = Icons.schedule_send_rounded;
          break;
        case 'Application pending':
          bg = const Color(0xFFEDE9FE).withValues(alpha: 0.95);
          fg = const Color(0xFF5B21B6);
          icon = Icons.mark_email_unread_rounded;
          break;
        case 'No shift assigned':
          bg = const Color(0xFFF1F5F9).withValues(alpha: 0.95);
          fg = const Color(0xFF64748B);
          icon = Icons.work_history_rounded;
          break;
        default:
          bg = const Color(0xFFF1F5F9).withValues(alpha: 0.95);
          fg = const Color(0xFF64748B);
          icon = Icons.info_outline_rounded;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftProgressTimeline extends StatefulWidget {
  const _ShiftProgressTimeline({
    required this.checkedIn,
    required this.checkedOut,
    required this.rated,
  });

  final bool checkedIn;
  final bool checkedOut;
  final bool rated;

  @override
  State<_ShiftProgressTimeline> createState() => _ShiftProgressTimelineState();
}

class _ShiftProgressTimelineState extends State<_ShiftProgressTimeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _stepEnter(int index) {
    final t = ((_ctrl.value * 1.25) - index * 0.17).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  double _lineGrow(int segmentIndex) {
    final t = ((_ctrl.value * 1.2) - 0.14 - segmentIndex * 0.2).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    const lineOn = Color(0xFF22C55E);
    const lineOff = Color(0xFFE2E8F0);
    const textDone = Color(0xFF0F172A);
    const textTodo = Color(0xFF94A3B8);

    Widget step(int index, String title, bool done, bool last) {
      final e = _stepEnter(index);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Transform.scale(
                  scale: 0.86 + 0.14 * e,
                  child: Opacity(
                    opacity: 0.25 + 0.75 * e,
                    child: Icon(
                      done ? Icons.check_circle_rounded : Icons.circle_outlined,
                      size: 20,
                      color: done ? lineOn : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                if (!last)
                  Builder(
                    builder: (context) {
                      final g = _lineGrow(index);
                      final active = done;
                      return Container(
                        width: 2,
                        height: 20 * g,
                        margin: const EdgeInsets.symmetric(vertical: 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: active
                              ? Color.lerp(
                                  lineOff,
                                  lineOn.withValues(alpha: 0.5),
                                  g,
                                )
                              : lineOff,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Opacity(
              opacity: 0.2 + 0.8 * e,
              child: Transform.translate(
                offset: Offset(0, 4 * (1 - e)),
                child: Padding(
                  padding: EdgeInsets.only(bottom: last ? 0 : 8),
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: done ? textDone : textTodo,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AgapColors.borderSubtle.withValues(alpha: 0.85),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your shift journey',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  step(0, 'Hired & confirmed', true, false),
                  step(1, 'Checked in', widget.checkedIn, false),
                  step(2, 'Checked out', widget.checkedOut, false),
                  step(3, 'You rated the business', widget.rated, true),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShiftSummaryCard extends StatelessWidget {
  const _ShiftSummaryCard({
    required this.title,
    required this.company,
    this.employerVerified = false,
    required this.payPhp,
    required this.checkIn,
    required this.checkOut,
    this.applicationPending = false,
    this.workDurationLabel,
    required this.topBadge,
  });

  final String title;
  final String company;
  final bool employerVerified;
  final int payPhp;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final bool applicationPending;
  final String? workDurationLabel;
  final String topBadge;

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

    final radius = BorderRadius.circular(20);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B21B6).withValues(alpha: 0.42),
            blurRadius: 36,
            spreadRadius: -4,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: const Color(0xFFA78BFA).withValues(alpha: 0.35),
            blurRadius: 48,
            spreadRadius: -12,
            offset: const Offset(0, 22),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF5B21B6),
                      Color(0xFF6D28D9),
                      Color(0xFF4338CA),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.85, -0.75),
                    radius: 1.15,
                    colors: [
                      Colors.white.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.85, 0.95),
                    radius: 1.05,
                    colors: [
                      const Color(0xFFEC4899).withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -50,
              bottom: -30,
              child: IgnorePointer(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),
            Positioned(
              right: -40,
              top: -40,
              child: IgnorePointer(
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFA78BFA).withValues(alpha: 0.22),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 24,
              top: 36,
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: -0.35,
                  child: Container(
                    width: 120,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.0),
                          Colors.white.withValues(alpha: 0.14),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
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
                            topBadge,
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
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            company,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                          ),
                          if (employerVerified) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 15,
                                  color: Colors.white.withValues(alpha: 0.95),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Verified employer',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white.withValues(alpha: 0.92),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₱$payPhp',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (applicationPending)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
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
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                          icon: Icons.login_rounded,
                          microCaption:
                              checkIn != null ? 'Checked in' : 'Check-in',
                          value: t(checkIn),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MiniStat(
                          icon: Icons.logout_rounded,
                          microCaption:
                              checkOut != null ? 'Checked out' : 'Check-out',
                          value: t(checkOut),
                        ),
                      ),
                    ],
                  ),
                  if (workDurationLabel != null) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          'Worked ${workDurationLabel!}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                    ),
                  ],
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.microCaption,
    required this.value,
  });

  final IconData icon;
  final String microCaption;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: Colors.white.withValues(alpha: 0.72),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  microCaption.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.45,
                    height: 1.2,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.2,
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
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  address,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${distanceKm.toStringAsFixed(1)} km from your location',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2563EB).withValues(alpha: 0.75),
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

class _AttendanceDayRow extends StatelessWidget {
  const _AttendanceDayRow({
    required this.dayLabel,
    required this.row,
    required this.timeStr,
  });

  final String dayLabel;
  final ShiftDaySummary? row;
  final String Function(DateTime?) timeStr;

  @override
  Widget build(BuildContext context) {
    final ci = row?.checkIn;
    final co = row?.checkOut;
    final complete = ci != null && co != null;
    final duration = formatWorkedDuration(ci, co);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: complete ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              complete ? Icons.verified_rounded : Icons.event_note_rounded,
              color: complete ? const Color(0xFF059669) : const Color(0xFF94A3B8),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      dayLabel,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: complete
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        complete ? 'Present' : 'Incomplete',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: complete
                              ? const Color(0xFF166534)
                              : const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${timeStr(ci)}  →  ${timeStr(co)}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: const Color(0xFF475569),
                  ),
                ),
                if (duration != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: const Color(0xFF64748B).withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$duration on the clock',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ),
                      if (complete)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFFDE68A).withValues(alpha: 0.9),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: Colors.amber.shade700,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'A+',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFFB45309),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (complete) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: const Color(0xFF059669),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Perfect attendance · this day',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                          color: const Color(0xFF047857),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
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
          const SizedBox(height: 12),
          for (final d in span)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AttendanceDayRow(
                dayLabel: shortLabel(d),
                row: forDay(d),
                timeStr: (DateTime? t) => _t(t),
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
    required this.ratings,
    required this.businessUserId,
    this.employerLine = '',
    this.employerVerified = false,
  });

  final Future<Rating?> future;
  final VoidCallback onRate;
  final RatingsRepository ratings;
  final String businessUserId;
  final String employerLine;
  final bool employerVerified;

  String _employerBadge() {
    final t = employerLine.trim();
    if (t.isEmpty) return 'Employer';
    final i = t.indexOf('·');
    if (i <= 0) return t;
    return t.substring(0, i).trim();
  }

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
                          if (employerVerified) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 16,
                                  color: Color(0xFF059669),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Verified employer',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: const Color(0xFF047857),
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

          final headline = r.stars >= 5
              ? 'Excellent performance'
              : r.stars >= 4
                  ? 'Strong work — keep it up'
                  : 'Thanks for sharing feedback';

          return Material(
            elevation: 8,
            shadowColor: const Color(0xFFF59E0B).withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFFFFFDF7),
                            const Color(0xFFFFF4D6),
                            const Color(0xFFFEF3C7),
                            const Color(0xFFFDE68A).withValues(alpha: 0.55),
                          ],
                          stops: const [0.0, 0.35, 0.72, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -28,
                    top: -24,
                    child: Icon(
                      Icons.star_rounded,
                      size: 130,
                      color: const Color(0xFFFFE082).withValues(alpha: 0.28),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 4,
                    child: Icon(
                      Icons.star_rounded,
                      size: 72,
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.14),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.4, -0.85),
                          radius: 1.1,
                          colors: [
                            Colors.white.withValues(alpha: 0.55),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Great work!',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: const Color(0xFF78350F),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFFFCD34D)
                                      .withValues(alpha: 0.85),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.12),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.storefront_rounded,
                                    size: 15,
                                    color: Colors.brown.shade600,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _employerBadge(),
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      color: const Color(0xFF78350F),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (employerVerified)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0xFF86EFAC),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.verified_rounded,
                                      size: 15,
                                      color: Color(0xFF047857),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Verified employer',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11.5,
                                        color: const Color(0xFF047857),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            for (var i = 1; i <= 5; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Icon(
                                  Icons.star_rounded,
                                  size: 28,
                                  color: i <= r.stars
                                      ? const Color(0xFFFBBF24)
                                      : const Color(0xFFE5E7EB),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Text(
                              '${r.stars}/5',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Your rating',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: const Color(0xFF92400E)
                                    .withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          headline,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: const Color(0xFFB45309),
                          ),
                        ),
                        if ((r.feedback ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            '“${r.feedback!.trim()}”',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                              fontStyle: FontStyle.italic,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ],
                        if (businessUserId.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    builder: (_) => UserRatingsScreen(
                                      ratings: ratings,
                                      userId: businessUserId,
                                      title:
                                          'Reviews · ${_employerBadge()}',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.open_in_new_rounded,
                                size: 18,
                              ),
                              label: Text(
                                'View full review',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
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

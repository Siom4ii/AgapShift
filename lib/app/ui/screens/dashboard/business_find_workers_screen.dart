import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../location/davao_del_sur_scope.dart';
import '../../../location/user_geo_point.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../marketplace/worker_discovery_loader.dart';
import '../../../notifications/notification_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../ratings/mock_ratings_repository.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/business_shell_bottom_nav.dart';
import '../../widgets/shell_screen_polish.dart';
import '../marketplace/business_gigs_screen.dart';
import '../messages/message_thread_screen.dart';

class BusinessFindWorkersScreen extends StatefulWidget {
  const BusinessFindWorkersScreen({
    super.key,
    required this.repo,
    required this.session,
    required this.ratings,
    required this.shiftRepo,
    required this.notifications,
    required this.payments,
    this.onOpenNotifications,
    this.onOpenInbox,
    this.notificationUnreadCount = 0,
  });

  final MarketplaceRepository repo;
  final SessionController session;
  final MockRatingsRepository ratings;
  final ShiftRepository shiftRepo;
  final NotificationRepository notifications;
  final PaymentsRepository payments;

  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenInbox;
  final int notificationUnreadCount;

  @override
  State<BusinessFindWorkersScreen> createState() =>
      _BusinessFindWorkersScreenState();
}

class _BusinessFindWorkersScreenState extends State<BusinessFindWorkersScreen> {
  final _search = TextEditingController();

  /// Chip index → filter key (matches worker Find Jobs categories).
  static const _categoryLabels = [
    'All',
    'Warehouse',
    'Food Service',
    'Retail',
    'Events',
  ];
  static const _categoryKeys = ['', 'warehouse', 'food', 'retail', 'event'];

  /// 0 = discover workers, 1 = job posts & applicants.
  int _section = 0;

  int get _sectionSafe => (_section == 0 || _section == 1) ? _section : 0;
  int _filter = 0;
  bool _loading = true;
  String? _error;
  String _locationSubtitle = DavaoDelSurScope.fallbackLocationLabel;
  List<DiscoverableWorker> _all = const [];

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _resolveLocation();
    await _load();
  }

  Future<void> _resolveLocation() async {
    final g = await tryGetCurrentUserGeoPoint();
    if (!mounted) return;
    if (g != null && DavaoDelSurScope.contains(g)) {
      setState(
        () => _locationSubtitle = 'Near you · ${DavaoDelSurScope.regionLabel}',
      );
    } else if (g != null && !DavaoDelSurScope.contains(g)) {
      setState(
        () => _locationSubtitle = DavaoDelSurScope.outsideRegionListLabel,
      );
    } else {
      setState(
        () => _locationSubtitle = DavaoDelSurScope.fallbackLocationLabel,
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await loadDiscoverableWorkers(
        repo: widget.repo,
        session: widget.session,
        ratings: widget.ratings,
        shiftRepo: widget.shiftRepo,
      );
      if (!mounted) return;
      setState(() => _all = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  List<DiscoverableWorker> get _filtered {
    final q = _search.text;
    final cat = _categoryKeys[_filter];
    return _all.where((w) {
      if (!categoryFilterPass(w, cat)) return false;
      return matchesWorkerSearch(w, q);
    }).toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final filtered = _filtered;
    final highlightCount = filtered
        .where((w) => w.availabilityHighlight)
        .length;
    final listSubtitle = _loading
        ? 'Loading workers…'
        : filtered.isEmpty
        ? ''
        : highlightCount > 0 && filtered.length > highlightCount
        ? '$highlightCount available now · ${filtered.length} workers'
        : highlightCount > 0
        ? '$highlightCount available now'
        : '${filtered.length} worker${filtered.length == 1 ? '' : 's'}';

    return ShellChromeBackground(
      kind: ShellChromeKind.business,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Find Workers',
                        style: GoogleFonts.inter(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                    if (widget.onOpenInbox != null ||
                        widget.onOpenNotifications != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.onOpenInbox != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: AgapColors.businessMint,
                                ),
                                onPressed: widget.onOpenInbox,
                                tooltip: 'Messages',
                                icon: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: AgapColors.businessGreenDeep,
                                  size: 22,
                                ),
                              ),
                            ),
                          if (widget.onOpenNotifications != null)
                            IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: AgapColors.businessMint,
                              ),
                              onPressed: widget.onOpenNotifications,
                              icon: Badge(
                                isLabelVisible:
                                    widget.notificationUnreadCount > 0,
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
                                child: Icon(
                                  Icons.notifications_outlined,
                                  color: AgapColors.businessGreenDeep,
                                  size: 22,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<int>(
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AgapColors.textMuted,
                    selectedForegroundColor: AgapColors.businessGreenDeep,
                    selectedBackgroundColor: AgapColors.businessMint,
                    side: const BorderSide(color: AgapColors.borderSubtle),
                  ),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment<int>(
                      value: 0,
                      label: Text('Discover'),
                      icon: Icon(Icons.person_search_outlined, size: 18),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('Job posts'),
                      icon: Icon(Icons.assignment_outlined, size: 18),
                    ),
                  ],
                  selected: {_sectionSafe},
                  onSelectionChanged: (Set<int> selected) {
                    if (selected.isEmpty) return;
                    final v = selected.first;
                    if (v != 0 && v != 1) return;
                    setState(() => _section = v);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _sectionSafe == 0
                ? RefreshIndicator(
                    color: AgapColors.businessGreen,
                    onRefresh: _load,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.place_outlined,
                                      size: 18,
                                      color: AgapColors.textMuted,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _locationSubtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          color: AgapColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _search,
                                  decoration: InputDecoration(
                                    hintText: 'Search by name or skill…',
                                    hintStyle: GoogleFonts.inter(
                                      color: AgapColors.textMuted,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search_rounded,
                                      color: AgapColors.textMuted,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: AgapColors.borderSubtle,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: AgapColors.borderSubtle,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: AgapColors.businessGreenDeep,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: _categoryLabels.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final sel = i == _filter;
                    return FilterChip(
                      label: Text(_categoryLabels[i]),
                      selected: sel,
                      onSelected: (_) => setState(() => _filter = i),
                      showCheckmark: false,
                      selectedColor: AgapColors.businessMint,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: sel
                            ? AgapColors.businessGreen
                            : AgapColors.borderSubtle,
                      ),
                      labelStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: sel
                            ? AgapColors.businessGreen
                            : AgapColors.textMuted,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 0,
                      ),
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  listSubtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AgapColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AgapColors.businessGreen,
                    ),
                  ),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _error!,
                    style: GoogleFonts.inter(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Text(
                    _all.isEmpty
                        ? 'No workers in the directory yet. '
                              'When workers apply to gigs in ${DavaoDelSurScope.regionLabel}, '
                              'they appear here.'
                        : 'No workers match your search or filters.',
                    style: GoogleFonts.inter(
                      color: AgapColors.textMuted,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottomSafe),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => ShellStaggerItem(
                    index: i,
                    child: ShellLift(child: _WorkerCard(worker: filtered[i])),
                  ),
                ),
              ),
          ],
        ),
      )
                : BusinessGigsScreen(
                    repo: widget.repo,
                    notifications: widget.notifications,
                    payments: widget.payments,
                    ratings: widget.ratings,
                    session: widget.session,
                    shiftRepo: widget.shiftRepo,
                    embedded: true,
                    suppressEmbeddedHeader: true,
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openWorkerDirectMessage({
  required BuildContext hostContext,
  required BuildContext modalContext,
  required DiscoverableWorker worker,
}) async {
  final scope = MarketplaceScope.tryOf(hostContext);
  if (scope == null) {
    ScaffoldMessenger.of(hostContext).showSnackBar(
      const SnackBar(content: Text('Messaging is unavailable here.')),
    );
    return;
  }
  try {
    final cid = await scope.messaging.getOrCreateConversation(
      otherUserId: worker.workerId,
    );
    if (modalContext.mounted) {
      Navigator.of(modalContext).pop();
    }
    if (!hostContext.mounted) return;
    await Navigator.of(hostContext).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MessageThreadScreen(
          conversationId: cid,
          title: worker.displayName,
        ),
      ),
    );
  } catch (e) {
    if (hostContext.mounted) {
      ScaffoldMessenger.of(hostContext).showSnackBar(
        SnackBar(content: Text('Could not start chat: $e')),
      );
    }
  }
}

void _showWorkerDetailSheet(BuildContext context, DiscoverableWorker w) {
  final media = MediaQuery.of(context);
  final navReserve = BusinessShellBottomNav.barHeight + media.padding.bottom;

  Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (modalContext, animation, secondaryAnimation) {
        return _WorkerDetailOverlayPage(
          worker: w,
          navReserve: navReserve,
          animation: animation,
          hostContext: context,
        );
      },
    ),
  );
}

/// Full-screen transparent route: dim only above the bottom nav; sheet slides up
/// from behind the nav strip (nav stays bright and tappable).
class _WorkerDetailOverlayPage extends StatelessWidget {
  const _WorkerDetailOverlayPage({
    required this.worker,
    required this.navReserve,
    required this.animation,
    required this.hostContext,
  });

  final DiscoverableWorker worker;
  final double navReserve;
  final Animation<double> animation;
  final BuildContext hostContext;

  static const Color _verifiedBlue = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context) {
    final viewH = MediaQuery.sizeOf(context).height;
    final availableH = (viewH - navReserve).clamp(180.0, viewH);
    final maxSheetH = (availableH * 0.72).clamp(260.0, viewH * 0.68);

    final ratingLine = worker.rating > 0
        ? '${worker.rating.toStringAsFixed(1)} (${worker.shiftsCompleted} shifts)'
        : '— (${worker.shiftsCompleted} shifts)';

    final dimCurve = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    final slideCurve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );

    return Theme(
      data: Theme.of(hostContext),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: navReserve,
            child: FadeTransition(
              opacity: dimCurve,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: ColoredBox(color: const Color(0x99000000)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: navReserve,
            child: ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(slideCurve),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxSheetH),
                    child: _WorkerDetailSheetPanel(
                      worker: worker,
                      ratingLine: ratingLine,
                      verifiedBlue: _verifiedBlue,
                      hostContext: hostContext,
                      modalContext: context,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerDetailSheetPanel extends StatelessWidget {
  const _WorkerDetailSheetPanel({
    required this.worker,
    required this.ratingLine,
    required this.verifiedBlue,
    required this.hostContext,
    required this.modalContext,
    required this.onClose,
  });

  final DiscoverableWorker worker;
  final String ratingLine;
  final Color verifiedBlue;
  final BuildContext hostContext;
  final BuildContext modalContext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final w = worker;
    return Material(
      color: Colors.white,
      elevation: 10,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              // Stack was only as tall as the drag pill; the close IconButton
              // overflowed downward and overlapped the verified badge row.
              child: SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AgapColors.borderSubtle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF6B7280),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFF3F4F6),
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF5EEAD4),
                              Color(0xFF14B8A6),
                              Color(0xFF0F766E),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF14B8A6),
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          w.initials,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    w.displayName,
                                    style: GoogleFonts.inter(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      height: 1.15,
                                      color: const Color(0xFF111827),
                                    ),
                                  ),
                                ),
                                if (w.verified) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.verified_rounded,
                                    size: 24,
                                    color: verifiedBlue,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 20,
                                  color: Color(0xFFEAB308),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  ratingLine,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    color: const Color(0xFF111827),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              w.availability,
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: w.availabilityHighlight
                                    ? AgapColors.businessGreen
                                    : AgapColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    (w.bio != null && w.bio!.trim().isNotEmpty)
                        ? w.bio!.trim()
                        : 'No bio yet. This worker may add more details after onboarding.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in w.skillTags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            t,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF6B21A8),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _WorkerStatTile(label: 'Rate', value: w.rateLabel),
                      const SizedBox(width: 10),
                      _WorkerStatTile(
                        label: 'Distance',
                        value: '${w.distanceKm.toStringAsFixed(1)} km',
                      ),
                      const SizedBox(width: 10),
                      _WorkerStatTile(
                        label: 'Age',
                        value: w.ageYears != null ? '${w.ageYears} yrs' : '—',
                      ),
                    ],
                  ),
                  if (w.hiredByMe) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AgapColors.businessMint.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AgapColors.businessGreen.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: AgapColors.businessGreen,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'You have hired this worker for one of your gigs.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AgapColors.businessGreen,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  _WorkerCircleAction(
                    icon: Icons.chat_bubble_outline_rounded,
                    onTap: () => _openWorkerDirectMessage(
                      hostContext: hostContext,
                      modalContext: modalContext,
                      worker: w,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Material(
                      elevation: w.hiredByMe ? 0 : 3,
                      shadowColor: AgapColors.businessGreen.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      color: w.hiredByMe
                          ? const Color(0xFFE5E7EB)
                          : AgapColors.businessGreen,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: w.hiredByMe
                            ? null
                            : () {
                                Navigator.of(modalContext).pop();
                                ScaffoldMessenger.of(hostContext).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Post or open a job, then hire ${w.displayName} from applicants.',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Center(
                            child: Text(
                              w.hiredByMe ? 'Already hired' : 'Hire Now',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: w.hiredByMe
                                    ? AgapColors.textMuted
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
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

class _WorkerStatTile extends StatelessWidget {
  const _WorkerStatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AgapColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF111827),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerCircleAction extends StatelessWidget {
  const _WorkerCircleAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(icon, color: const Color(0xFF374151), size: 22),
        ),
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({required this.worker});

  final DiscoverableWorker worker;

  @override
  Widget build(BuildContext context) {
    final w = worker;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showWorkerDetailSheet(context, w),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AgapColors.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
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
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8E0F5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            w.initials,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: const Color(0xFF4C1D95),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AgapColors.businessGreen,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
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
                                  w.displayName,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (w.verified) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.verified_rounded,
                                  size: 18,
                                  color: AgapColors.businessGreen,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            w.availability,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: w.availabilityHighlight
                                  ? AgapColors.businessGreen
                                  : AgapColors.textMuted,
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
                              size: 18,
                              color: const Color(0xFFEAB308),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              w.rating > 0 ? w.rating.toStringAsFixed(1) : '—',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${w.shiftsCompleted} shifts',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in w.skillTags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          t,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6B21A8),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: AgapColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${w.distanceKm.toStringAsFixed(1)} km',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AgapColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.payments_outlined,
                      size: 16,
                      color: AgapColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      w.rateLabel,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const Spacer(),
                    if (w.hiredByMe)
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: AgapColors.businessGreen,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Hired',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AgapColors.businessGreen,
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
    );
  }
}

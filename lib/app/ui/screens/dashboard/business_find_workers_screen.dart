import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../location/davao_del_sur_scope.dart';
import '../../../location/user_geo_point.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../marketplace/worker_discovery_loader.dart';
import '../../../notifications/notification_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/business_shell_bottom_nav.dart';
import '../../widgets/shell_screen_polish.dart';
import '../marketplace/business_gigs_screen.dart';
import '../messages/message_thread_screen.dart';
import '../ratings/user_ratings_screen.dart';

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
    this.inboxUnreadCount = 0,
  });

  final MarketplaceRepository repo;
  final SessionController session;
  final RatingsRepository ratings;
  final ShiftRepository shiftRepo;
  final NotificationRepository notifications;
  final PaymentsRepository payments;

  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenInbox;
  final int notificationUnreadCount;
  final int inboxUnreadCount;

  @override
  State<BusinessFindWorkersScreen> createState() =>
      _BusinessFindWorkersScreenState();
}

enum _WorkerSort { closest, topRated, mostShifts, lowestRate }

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
  _WorkerSort _workerSort = _WorkerSort.closest;
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

  int? _pesoFromRateLabel(String s) {
    final m = RegExp(r'₱\s*([\d,]+)').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(1)!.replaceAll(',', ''));
  }

  List<DiscoverableWorker> _sortedWorkers(List<DiscoverableWorker> raw) {
    final list = [...raw];
    switch (_workerSort) {
      case _WorkerSort.closest:
        list.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        break;
      case _WorkerSort.topRated:
        list.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case _WorkerSort.mostShifts:
        list.sort((a, b) => b.shiftsCompleted.compareTo(a.shiftsCompleted));
        break;
      case _WorkerSort.lowestRate:
        list.sort((a, b) {
          final pa = _pesoFromRateLabel(a.rateLabel) ?? 1 << 30;
          final pb = _pesoFromRateLabel(b.rateLabel) ?? 1 << 30;
          return pa.compareTo(pb);
        });
        break;
    }
    return list;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final filtered = _sortedWorkers(_filtered);
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
                                  child: Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: AgapColors.businessGreenDeep,
                                    size: 22,
                                  ),
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
              child: SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  children: [
                    _SortChip(
                      label: 'Closest',
                      selected: _workerSort == _WorkerSort.closest,
                      onTap: () =>
                          setState(() => _workerSort = _WorkerSort.closest),
                    ),
                    _SortChip(
                      label: 'Top rated',
                      selected: _workerSort == _WorkerSort.topRated,
                      onTap: () =>
                          setState(() => _workerSort = _WorkerSort.topRated),
                    ),
                    _SortChip(
                      label: 'Most shifts',
                      selected: _workerSort == _WorkerSort.mostShifts,
                      onTap: () =>
                          setState(() => _workerSort = _WorkerSort.mostShifts),
                    ),
                    _SortChip(
                      label: 'Lowest rate',
                      selected: _workerSort == _WorkerSort.lowestRate,
                      onTap: () =>
                          setState(() => _workerSort = _WorkerSort.lowestRate),
                    ),
                  ],
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
                    child: ShellLift(
                      child: _WorkerCard(
                        worker: filtered[i],
                        ratings: widget.ratings,
                        onMessage: () => _openWorkerDirectMessage(
                          hostContext: context,
                          modalContext: context,
                          worker: filtered[i],
                        ),
                      ),
                    ),
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
          peerUserId: worker.workerId,
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

void _showWorkerDetailSheet(
  BuildContext context,
  DiscoverableWorker w, {
  required RatingsRepository ratings,
}) {
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
          ratings: ratings,
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
    required this.ratings,
    required this.navReserve,
    required this.animation,
    required this.hostContext,
  });

  final DiscoverableWorker worker;
  final RatingsRepository ratings;
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
                      ratings: ratings,
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
    required this.ratings,
    required this.ratingLine,
    required this.verifiedBlue,
    required this.hostContext,
    required this.modalContext,
    required this.onClose,
  });

  final DiscoverableWorker worker;
  final RatingsRepository ratings;
  final String ratingLine;
  final Color verifiedBlue;
  final BuildContext hostContext;
  final BuildContext modalContext;
  final VoidCallback onClose;

  Future<Gig?> _pickListingToOffer({
    required BuildContext hostContext,
    required String businessId,
  }) async {
    final scope = MarketplaceScope.tryOf(hostContext);
    if (scope == null) return null;

    final all = await scope.repo.listGigs();
    final now = DateTime.now().toUtc();
    final gigs = all
        .where(
          (g) =>
              g.businessId == businessId &&
              g.status == GigStatus.open &&
              g.endAt.toUtc().isAfter(now),
        )
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    if (!hostContext.mounted) return null;

    if (gigs.isEmpty) {
      await showDialog<void>(
        context: hostContext,
        builder: (ctx) => AlertDialog(
          title: const Text('No open listings'),
          content: const Text(
            'Create or open a job listing first, then you can offer it to a worker.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return null;
    }

    return showModalBottomSheet<Gig>(
      context: hostContext,
      showDragHandle: true,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              12 + MediaQuery.paddingOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Select a listing',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This will send the worker a job offer notification.',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: AgapColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: gigs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final g = gigs[i];
                      final payDay = (g.pay.amount / 100).round();
                      final start = g.startAt.toLocal();
                      final end = g.endAt.toLocal();
                      final dateLine =
                          '${start.month.toString().padLeft(2, '0')}/${start.day.toString().padLeft(2, '0')}/${start.year}'
                          '${(start.year == end.year && start.month == end.month && start.day == end.day) ? '' : ' → ${end.month.toString().padLeft(2, '0')}/${end.day.toString().padLeft(2, '0')}/${end.year}'}';
                      return InkWell(
                        onTap: () => Navigator.of(ctx).pop(g),
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AgapColors.borderSubtle.withValues(alpha: 0.95),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AgapColors.businessMint,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.work_outline_rounded,
                                  color: AgapColors.businessGreenDeep,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      g.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${g.category} · ₱$payDay/day · $dateLine',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        color: AgapColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(modalContext).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) => UserRatingsScreen(
                                          ratings: ratings,
                                          userId: w.workerId,
                                          title: 'Worker reviews',
                                        ),
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: const Size(0, 0),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'View',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w900,
                                      color: verifiedBlue,
                                    ),
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
                            : () async {
                                final scope = MarketplaceScope.tryOf(hostContext);
                                if (scope == null) return;
                                final businessId =
                                    appActorId(scope.session, mockFallback: '');
                                if (businessId.isEmpty) return;

                                final gig = await _pickListingToOffer(
                                  hostContext: hostContext,
                                  businessId: businessId,
                                );
                                if (gig == null) return;

                                if (modalContext.mounted) {
                                  Navigator.of(modalContext).pop();
                                }

                                try {
                                  await scope.notifications.add(
                                    userId: w.workerId,
                                    title: 'Job offer',
                                    body: 'You have a job offer: ${gig.title}',
                                    data: {
                                      'type': 'job_offer',
                                      'gigId': gig.id,
                                      'businessId': businessId,
                                    },
                                  );
                                  if (hostContext.mounted) {
                                    ScaffoldMessenger.of(hostContext).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Offer sent to ${w.displayName}.',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (hostContext.mounted) {
                                    ScaffoldMessenger.of(hostContext).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not send offer: $e',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                }
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

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AgapColors.businessMint : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AgapColors.businessGreen
                  : AgapColors.borderSubtle,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AgapColors.businessGreen.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: selected
                  ? AgapColors.businessGreenDeep
                  : AgapColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _LivePresenceDot extends StatefulWidget {
  @override
  State<_LivePresenceDot> createState() => _LivePresenceDotState();
}

class _LivePresenceDotState extends State<_LivePresenceDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.92, end: 1.12).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: AgapColors.businessGreen,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: AgapColors.businessGreen.withValues(alpha: 0.55),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({
    required this.worker,
    required this.ratings,
    required this.onMessage,
  });

  final DiscoverableWorker worker;
  final RatingsRepository ratings;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final w = worker;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showWorkerDetailSheet(context, w, ratings: ratings),
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
                          child: w.availabilityHighlight
                              ? _LivePresenceDot()
                              : Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: AgapColors.businessGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
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
                          if (w.availabilityHighlight) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Responds quickly · visible to nearby employers',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AgapColors.textMuted.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onMessage,
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          'Message',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AgapColors.businessGreenDeep,
                          side: BorderSide(
                            color: AgapColors.businessGreen.withValues(
                              alpha: 0.45,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => _showWorkerDetailSheet(
                          context,
                          w,
                          ratings: ratings,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AgapColors.businessMint,
                          foregroundColor: AgapColors.businessGreenDeep,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          'View profile',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../notifications/notification_repository.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/success_feedback.dart';
import 'business_gig_manage_screen.dart';

class BusinessGigsScreen extends StatefulWidget {
  const BusinessGigsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.payments,
    required this.ratings,
    required this.session,
    required this.shiftRepo,
    this.embedded = false,
    this.suppressEmbeddedHeader = false,
  });

  final MarketplaceRepository repo;
  final NotificationRepository notifications;
  final PaymentsRepository payments;
  final RatingsRepository ratings;
  final SessionController session;
  final ShiftRepository shiftRepo;
  final bool embedded;
  /// When [embedded] is true, omit the inner "My job posts" title row (e.g. nested under Workers tabs).
  final bool suppressEmbeddedHeader;

  @override
  State<BusinessGigsScreen> createState() => _BusinessGigsScreenState();
}

class _BusinessGigsScreenState extends State<BusinessGigsScreen> {
  bool _loading = false;
  List<Gig> _items = const [];
  List<GigApplication> _applications = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final businessId = appActorId(widget.session, mockFallback: 'business');
      final all = await widget.repo.listGigs();
      final apps = await widget.repo.listApplications();
      final items = all.where((g) => g.businessId == businessId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _items = items;
        _applications = apps;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmCancel(Gig gig) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel this listing?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(
          '“${gig.title}” will be marked as Cancelled and stay in this list. Workers will no longer see it as an open job.',
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.45,
            color: AgapColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Keep listing',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: AgapColors.textMuted,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Cancel listing',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await _cancel(gig);
  }

  Future<void> _cancel(Gig gig) async {
    final businessId = appActorId(widget.session, mockFallback: 'business');
    try {
      await widget.repo.cancelGig(gigId: gig.id, businessId: businessId);
      await widget.notifications.add(
        userId: businessId,
        title: 'Gig cancelled',
        body: 'Gig: ${gig.title}',
        data: {'gigId': gig.id},
      );
      await _load();
      if (!mounted) return;
      showSuccessSnackBar(context, 'Job cancelled');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot cancel: $e')));
    }
  }

  int _applyingCount(String gigId) => _applications
      .where(
        (a) =>
            a.gigId == gigId && a.status == ApplicationStatus.applied,
      )
      .length;

  int _hiredCount(String gigId) => _applications
      .where(
        (a) => a.gigId == gigId && a.status == ApplicationStatus.hired,
      )
      .length;

  Future<void> _openManage(Gig g) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BusinessGigManageScreen(
          gig: g,
          session: widget.session,
          repo: widget.repo,
          notifications: widget.notifications,
          ratings: widget.ratings,
          shiftRepo: widget.shiftRepo,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _loading
        ? const Center(
            child: CircularProgressIndicator(color: AgapColors.businessGreen),
          )
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error: $_error',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(),
                  ),
                ),
              )
            : _items.isEmpty
                ? CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No job posts yet. Tap “Post Job” in the tab bar to create one.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: AgapColors.textMuted,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, i) {
                      final g = _items[i];
                      final applying = _applyingCount(g.id);
                      final hired = _hiredCount(g.id);
                      final payDay = (g.pay.amount / 100).round();
                      final canCancel = g.status != GigStatus.cancelled &&
                          g.status != GigStatus.completed;
                      final expired = g.endAt.isBefore(DateTime.now().toUtc());
                      final listingInactive =
                          expired ||
                          g.status == GigStatus.cancelled ||
                          g.status == GigStatus.completed;

                      return _JobPostCard(
                        gig: g,
                        payDay: payDay,
                        applying: applying,
                        hired: hired,
                        cardIconIndex: i,
                        showCancelAction: canCancel,
                        listingInactive: listingInactive,
                        statusLabel: _statusLabel(g, expired: expired),
                        onOpenDetails: () => _openManage(g),
                        onCancelListing: () => _confirmCancel(g),
                      );
                    },
                  );

    if (widget.embedded) {
      if (widget.suppressEmbeddedHeader) {
        return SafeArea(
          child: RefreshIndicator(
            color: AgapColors.businessGreen,
            onRefresh: _load,
            child: list,
          ),
        );
      }
      return SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'My job posts',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Expanded(child: list),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AgapColors.pageBackground,
      appBar: AppBar(
        title: Text(
          'My job posts',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AgapColors.businessGreen,
          onRefresh: _load,
          child: list,
        ),
      ),
    );
  }

  String _statusLabel(Gig g, {required bool expired}) {
    if (g.status == GigStatus.cancelled) return 'Cancelled';
    if (g.status == GigStatus.completed) return 'Completed';
    if (expired) return 'Expired';
    return switch (g.status) {
      GigStatus.open => 'Open',
      GigStatus.filled => 'Filled',
      GigStatus.ongoing => 'Ongoing',
      GigStatus.completed => 'Completed',
      GigStatus.cancelled => 'Cancelled',
    };
  }
}

class _JobPostCard extends StatelessWidget {
  const _JobPostCard({
    required this.gig,
    required this.payDay,
    required this.applying,
    required this.hired,
    required this.cardIconIndex,
    required this.showCancelAction,
    required this.listingInactive,
    required this.statusLabel,
    required this.onOpenDetails,
    required this.onCancelListing,
  });

  final Gig gig;
  final int payDay;
  final int applying;
  final int hired;
  final int cardIconIndex;
  final bool showCancelAction;
  final bool listingInactive;
  final String statusLabel;
  final VoidCallback onOpenDetails;
  final VoidCallback onCancelListing;

  static const _categoryIcons = [
    Icons.work_outline_rounded,
    Icons.restaurant_outlined,
    Icons.storefront_outlined,
    Icons.event_outlined,
  ];

  static ({Color accent, Color iconBg, Color iconFg, IconData icon})
      _categoryPresentation(String raw, IconData fallback) {
    final v = raw.trim().toLowerCase();
    if (v.contains('food') || v.contains('cook') || v.contains('service')) {
      return (
        accent: const Color(0xFFF59E0B),
        iconBg: const Color(0xFFFFF7ED),
        iconFg: const Color(0xFFC2410C),
        icon: Icons.restaurant_outlined,
      );
    }
    if (v.contains('warehouse') || v.contains('delivery') || v.contains('driver')) {
      return (
        accent: const Color(0xFF2563EB),
        iconBg: const Color(0xFFEFF6FF),
        iconFg: const Color(0xFF1D4ED8),
        icon: Icons.inventory_2_outlined,
      );
    }
    if (v.contains('event')) {
      return (
        accent: const Color(0xFF7C3AED),
        iconBg: const Color(0xFFF5F3FF),
        iconFg: const Color(0xFF6D28D9),
        icon: Icons.event_outlined,
      );
    }
    if (v.contains('retail') || v.contains('store')) {
      return (
        accent: const Color(0xFF10B981),
        iconBg: const Color(0xFFECFDF5),
        iconFg: const Color(0xFF047857),
        icon: Icons.storefront_outlined,
      );
    }
    return (
      accent: AgapColors.businessGreenDeep,
      iconBg: AgapColors.businessMint,
      iconFg: AgapColors.businessGreenDeep,
      icon: fallback,
    );
  }

  String _relativePosted(DateTime createdAt) {
    final local = createdAt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 2) return 'Posted just now';
    if (diff.inMinutes < 60) return 'Posted ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Posted ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Posted yesterday';
    return 'Posted ${diff.inDays}d ago';
  }

  String _startLine(DateTime startAt) {
    final local = startAt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Starts ${months[local.month - 1]} ${local.day}';
  }

  @override
  Widget build(BuildContext context) {
    final fallbackIcon = _categoryIcons[cardIconIndex % _categoryIcons.length];
    final cat = _categoryPresentation(gig.category, fallbackIcon);
    final isOpen = statusLabel == 'Open';
    final urgent = gig.isUrgent && isOpen && !listingInactive;
    final needed = gig.workersNeeded;
    final progressLabel = needed != null && needed > 0
        ? '$hired/$needed hired'
        : (hired > 0 ? '$hired hired' : null);
    final applicantsLabel = applying > 0 ? '$applying applicants' : null;

    final statusDisplay = isOpen
        ? (applying > 0 ? '$applying waiting' : 'Hiring now')
        : statusLabel;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenDetails,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE8EAEF),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: listingInactive ? 0.03 : 0.06),
                blurRadius: listingInactive ? 14 : 22,
                offset: const Offset(0, 8),
              ),
              if (urgent)
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 14,
                bottom: 14,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        cat.accent,
                        cat.accent.withValues(alpha: 0.4),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: cat.iconBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: cat.accent.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Icon(
                            cat.icon,
                            color: cat.iconFg,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                gig.title,
                                style: GoogleFonts.inter(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _TinyTag(
                                    label: gig.category.toUpperCase(),
                                    bg: cat.iconBg,
                                    fg: cat.iconFg,
                                    border: cat.accent.withValues(alpha: 0.18),
                                  ),
                                  Text(
                                    '₱$payDay/day',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF111827),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                children: [
                                  _MetaLine(
                                    icon: Icons.schedule_rounded,
                                    text: _startLine(gig.startAt),
                                  ),
                                  _MetaLine(
                                    icon: Icons.upload_rounded,
                                    text: _relativePosted(gig.createdAt),
                                  ),
                                  if (progressLabel != null)
                                    _MetaLine(
                                      icon: Icons.group_add_outlined,
                                      text: progressLabel,
                                    ),
                                  if (applicantsLabel != null)
                                    _MetaLine(
                                      icon: Icons.person_outline_rounded,
                                      text: applicantsLabel,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (urgent)
                                  _UrgentPill(
                                    label: 'Urgent',
                                    accent: const Color(0xFFF59E0B),
                                  ),
                                if (urgent) const SizedBox(width: 8),
                                _StatusPill(
                                  label: statusDisplay,
                                  kind: isOpen ? _StatusPillKind.open : _StatusPillKind.other,
                                ),
                              ],
                            ),
                            if (showCancelAction) ...[
                              const SizedBox(height: 6),
                              _CardMenu(
                                enabled: !listingInactive,
                                onCancel: onCancelListing,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ActionRow(
                      listingInactive: listingInactive,
                      applying: applying,
                      onView: onOpenDetails,
                      onApplicants: onOpenDetails,
                      onEdit: onOpenDetails,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _StatusPillKind { open, other }

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.kind});

  final String label;
  final _StatusPillKind kind;

  Color get _bg {
    switch (kind) {
      case _StatusPillKind.open:
        return AgapColors.businessMint;
      case _StatusPillKind.other:
        // Derive from label
        switch (label) {
          case 'Filled':
          case 'Ongoing':
            return const Color(0xFFEFF6FF);
          case 'Expired':
            return const Color(0xFFFFFBEB);
          case 'Completed':
            return const Color(0xFFF3F4F6);
          case 'Cancelled':
            return const Color(0xFFFEF2F2);
          default:
            return AgapColors.businessMint;
        }
    }
  }

  Color get _fg {
    switch (kind) {
      case _StatusPillKind.open:
        return AgapColors.businessGreenDeep;
      case _StatusPillKind.other:
        switch (label) {
          case 'Filled':
          case 'Ongoing':
            return const Color(0xFF1D4ED8);
          case 'Expired':
            return const Color(0xFFB45309);
          case 'Completed':
            return AgapColors.textMuted;
          case 'Cancelled':
            return const Color(0xFFB91C1C);
          default:
            return AgapColors.businessGreenDeep;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final glow = kind == _StatusPillKind.open
        ? [
            BoxShadow(
              color: AgapColors.businessGreen.withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ]
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _fg.withValues(alpha: 0.22),
        ),
        boxShadow: glow,
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: _fg,
        ),
      ),
    );
  }
}

class _UrgentPill extends StatelessWidget {
  const _UrgentPill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 14, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              color: const Color(0xFF9A3412),
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyTag extends StatelessWidget {
  const _TinyTag({
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          color: fg,
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: AgapColors.textMuted.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AgapColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.listingInactive,
    required this.applying,
    required this.onView,
    required this.onApplicants,
    required this.onEdit,
  });

  final bool listingInactive;
  final int applying;
  final VoidCallback onView;
  final VoidCallback onApplicants;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final muted = listingInactive;
    final applicantsPrimary = applying > 0 && !muted;

    return Row(
      children: [
        Expanded(
          child: applicantsPrimary
              ? OutlinedButton(
                  onPressed: onView,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF111827),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.white,
                  ),
                  child: Text(
                    'View',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                  ),
                )
              : FilledButton(
            onPressed: onView,
            style: FilledButton.styleFrom(
              backgroundColor:
                  muted ? const Color(0xFFE5E7EB) : AgapColors.businessGreen,
              foregroundColor: muted ? const Color(0xFF374151) : Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'View',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: applicantsPrimary
              ? FilledButton(
                  onPressed: onApplicants,
                  style: FilledButton.styleFrom(
                    backgroundColor: AgapColors.businessGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Applicants',
                            style:
                                GoogleFonts.inter(fontWeight: FontWeight.w900),
                          ),
                          if (applying > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: 0.28),
                                ),
                              ),
                              child: Text(
                                '$applying',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              : OutlinedButton(
            onPressed: onApplicants,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF111827),
              side: BorderSide(
                color: const Color(0xFFE5E7EB),
              ),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Colors.white,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Applicants',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                    if (applying > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AgapColors.businessMint,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AgapColors.businessGreen
                                .withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          '$applying',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            color: AgapColors.businessGreenDeep,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: const Color(0xFFF9FAFB),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Edit',
                style: GoogleFonts.inter(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.enabled, required this.onCancel});

  final bool enabled;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'More',
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'cancel',
          child: Row(
            children: [
              Icon(Icons.cancel_outlined, color: Colors.red.shade700, size: 18),
              const SizedBox(width: 8),
              Text(
                'Cancel listing',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
      onSelected: (v) {
        if (v == 'cancel') onCancel();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.more_horiz_rounded,
          size: 20,
          color: const Color(0xFF374151),
        ),
      ),
    );
  }
}


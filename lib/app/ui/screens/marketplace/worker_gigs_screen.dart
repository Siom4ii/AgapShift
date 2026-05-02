import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../session/session_controller.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import 'worker_gig_details_screen.dart';

class WorkerGigsScreen extends StatefulWidget {
  const WorkerGigsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.session,
  });

  final MarketplaceRepository repo;
  final MockNotificationRepository notifications;
  final SessionController session;

  @override
  State<WorkerGigsScreen> createState() => _WorkerGigsScreenState();
}

class _WorkerGigsScreenState extends State<WorkerGigsScreen> {
  int _radiusM = 5000;
  int _minPay = 0;
  String _category = '';
  String _query = '';

  bool _loading = false;
  List<Gig> _items = const [];
  String? _error;

  GeoPoint get _center => const GeoPoint(lat: 14.5995, lng: 120.9842);

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
      final items = await widget.repo.listNearbyGigs(
        center: _center,
        radiusMeters: _radiusM,
        minPayAmount: _minPay == 0 ? null : _minPay,
        category: _category.isEmpty ? null : _category,
      );
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Gig> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where(
          (g) =>
              g.title.toLowerCase().contains(q) ||
              g.category.toLowerCase().contains(q) ||
              g.addressLabel.toLowerCase().contains(q),
        )
        .toList();
  }

  void _showFiltersSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.paddingOf(ctx).bottom + 20,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Filters', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _radiusM,
                    decoration: const InputDecoration(labelText: 'Radius'),
                    items: const [
                      DropdownMenuItem(value: 1000, child: Text('1 km')),
                      DropdownMenuItem(value: 3000, child: Text('3 km')),
                      DropdownMenuItem(value: 5000, child: Text('5 km')),
                      DropdownMenuItem(value: 10000, child: Text('10 km')),
                    ],
                    onChanged: (v) => setModal(() => _radiusM = v ?? _radiusM),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _minPay,
                    decoration: const InputDecoration(labelText: 'Minimum pay'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Any pay')),
                      DropdownMenuItem(value: 50000, child: Text('≥ ₱500')),
                      DropdownMenuItem(value: 80000, child: Text('≥ ₱800')),
                      DropdownMenuItem(value: 100000, child: Text('≥ ₱1000')),
                    ],
                    onChanged: (v) => setModal(() => _minPay = v ?? _minPay),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _category.isEmpty ? '' : _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Any type')),
                      DropdownMenuItem(
                        value: 'Food Service',
                        child: Text('Food Service'),
                      ),
                      DropdownMenuItem(value: 'Retail', child: Text('Retail')),
                      DropdownMenuItem(
                        value: 'Warehouse',
                        child: Text('Warehouse'),
                      ),
                    ],
                    onChanged: (v) => setModal(() => _category = v ?? ''),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _load();
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: const _FakeMapLayer()),
                  if (_loading)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x33FFFFFF),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  if (_error != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 12,
                      child: Material(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade900),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Column(
                      children: [
                        _MapFab(
                          icon: Icons.my_location_rounded,
                          onPressed: () {},
                        ),
                        const SizedBox(height: 10),
                        _MapFab(
                          icon: Icons.tune_rounded,
                          onPressed: _showFiltersSheet,
                        ),
                      ],
                    ),
                  ),
                  ..._buildPins(context, h),
                ],
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.48,
              minChildSize: 0.22,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return _GigsSheet(
                  scrollController: scrollController,
                  gigs: _filtered,
                  matchCount: _filtered.length,
                  center: _center,
                  onRefresh: _load,
                  onTapGig: (g) async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WorkerGigDetailsScreen(
                          repo: widget.repo,
                          notifications: widget.notifications,
                          session: widget.session,
                          gigId: g.id,
                        ),
                      ),
                    );
                    await _load();
                  },
                  onQueryChanged: (q) => setState(() => _query = q),
                );
              },
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildPins(BuildContext context, double stackHeight) {
    final w = MediaQuery.sizeOf(context).width;
    final mapH = stackHeight * 0.52;
    final items = _filtered.take(6).toList();
    return [
      for (var i = 0; i < items.length; i++)
        Positioned(
          left: _pinDx(items[i].id, w) - 28,
          top: _pinDy(items[i].id, mapH) - 36,
          child: _MapPin(gig: items[i]),
        ),
    ];
  }
}

double _pinDx(String id, double width) {
  final h = id.hashCode.abs();
  return 0.12 * width + (h % 73) / 100.0 * width * 0.62;
}

double _pinDy(String id, double height) {
  final h = id.hashCode.abs();
  return 0.1 * height + ((h ~/ 5) % 71) / 100.0 * height * 0.65;
}

class _FakeMapLayer extends StatelessWidget {
  const _FakeMapLayer();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AgapColors.water, Color(0xFFD4E8F5)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: -40,
            top: 40,
            child: Transform.rotate(
              angle: -0.15,
              child: Container(
                width: 320,
                height: 280,
                decoration: BoxDecoration(
                  color: AgapColors.mintSoft.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(120),
                ),
              ),
            ),
          ),
          Positioned(
            right: -60,
            bottom: 20,
            child: Container(
              width: 260,
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFFC5E6D8).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapFab extends StatelessWidget {
  const _MapFab({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      color: Colors.white,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: AgapColors.primary, size: 22),
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.gig});

  final Gig gig;

  @override
  Widget build(BuildContext context) {
    final hourly = _hourlyPhp(gig);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            '₱${hourly.toStringAsFixed(0)}/hr',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AgapColors.primaryBright,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            color: AgapColors.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _categoryIcon(gig.category),
            color: Colors.white,
            size: 18,
          ),
        ),
      ],
    );
  }
}

class _GigsSheet extends StatelessWidget {
  const _GigsSheet({
    required this.scrollController,
    required this.gigs,
    required this.matchCount,
    required this.center,
    required this.onRefresh,
    required this.onTapGig,
    required this.onQueryChanged,
  });

  final ScrollController scrollController;
  final List<Gig> gigs;
  final int matchCount;
  final GeoPoint center;
  final Future<void> Function() onRefresh;
  final void Function(Gig gig) onTapGig;
  final void Function(String q) onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AgapColors.borderSubtle,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Gigs Near You',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$matchCount matches',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1D4ED8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              onChanged: onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search gigs…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AgapColors.pageBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: gigs.isEmpty
                  ? ListView(
                      controller: scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 48),
                        Center(child: Text('No open gigs nearby yet.')),
                      ],
                    )
                  : ListView.separated(
                      controller: scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      itemCount: gigs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, i) {
                        final g = gigs[i];
                        return ShellStaggerItem(
                          index: i,
                          child: ShellLift(
                            child: _GigCard(
                              gig: g,
                              urgent: i == 0 && g.status == GigStatus.open,
                              distanceMi:
                                  _distanceMeters(center, g.location) / 1609.34,
                              onQuickView: () => onTapGig(g),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GigCard extends StatelessWidget {
  const _GigCard({
    required this.gig,
    required this.urgent,
    required this.distanceMi,
    required this.onQuickView,
  });

  final Gig gig;
  final bool urgent;
  final double distanceMi;
  final VoidCallback onQuickView;

  @override
  Widget build(BuildContext context) {
    final total = gig.pay.amount / 100.0;
    final hourly = _hourlyPhp(gig);
    return Container(
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
            if (urgent)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AgapColors.urgentBadge,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'URGENT FILL',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AgapColors.urgentText,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    gig.title,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                Text(
                  '₱${hourly.toStringAsFixed(0)}/hr',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 16,
                  color: AgapColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  '${distanceMi.toStringAsFixed(1)} mi',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AgapColors.textMuted,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '•',
                    style: TextStyle(color: AgapColors.textMuted),
                  ),
                ),
                Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: AgapColors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  _timeRange(gig),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AgapColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Total ~₱${total.toStringAsFixed(0)} • ${gig.category}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AgapColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onQuickView,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF111827),
                  side: const BorderSide(color: AgapColors.borderSubtle),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Quick View',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int _distanceMeters(GeoPoint a, GeoPoint b) {
  final dx = (a.lat - b.lat) * 111000.0;
  final dy = (a.lng - b.lng) * 111000.0;
  return math.sqrt(dx * dx + dy * dy).round();
}

double _hourlyPhp(Gig g) {
  var hours = g.endAt.difference(g.startAt).inMinutes / 60.0;
  if (hours < 0.25) hours = 8.0;
  return (g.pay.amount / 100.0) / hours;
}

String _timeRange(Gig g) {
  final s = g.startAt.toLocal();
  final e = g.endAt.toLocal();
  String t(DateTime d) {
    final h = d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final am = h >= 12 ? 'PM' : 'AM';
    final hr = h % 12 == 0 ? 12 : h % 12;
    return '$hr:$m $am';
  }

  return '${t(s)} - ${t(e)}';
}

IconData _categoryIcon(String c) {
  final l = c.toLowerCase();
  if (l.contains('warehouse')) return Icons.inventory_2_rounded;
  if (l.contains('food')) return Icons.restaurant_rounded;
  if (l.contains('retail')) return Icons.storefront_rounded;
  return Icons.work_rounded;
}

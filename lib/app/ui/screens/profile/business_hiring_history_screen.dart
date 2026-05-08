import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../profile/worker_display_names.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../theme/agap_colors.dart';

class BusinessHiringHistoryScreen extends StatefulWidget {
  const BusinessHiringHistoryScreen({
    super.key,
    required this.session,
    required this.marketRepo,
    required this.ratings,
  });

  final SessionController session;
  final MarketplaceRepository marketRepo;
  final RatingsRepository ratings;

  @override
  State<BusinessHiringHistoryScreen> createState() =>
      _BusinessHiringHistoryScreenState();
}

class _HireHistoryVm {
  const _HireHistoryVm({
    required this.workerId,
    required this.workerName,
    required this.gigTitle,
    required this.gigCategory,
    required this.whenLabel,
    required this.payLabel,
    required this.stars,
  });

  final String workerId;
  final String workerName;
  final String gigTitle;
  final String gigCategory;
  final String whenLabel;
  final String payLabel;
  final int stars;
}

class _BusinessHiringHistoryScreenState extends State<BusinessHiringHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<_HireHistoryVm> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _formatWhen(DateTime createdAt) {
    final local = createdAt.toLocal();
    final now = DateTime.now();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${local.month}/${local.day}/${local.year}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final businessId = appActorId(widget.session, mockFallback: '');
      final gigs = await widget.marketRepo.listGigs();
      final myGigs = gigs.where((g) => g.businessId == businessId).toList();
      final gigById = {for (final g in myGigs) g.id: g};

      final apps = await widget.marketRepo.listApplications();
      final hiredApps = apps
          .where((a) => gigById.containsKey(a.gigId))
          .where((a) => a.status == ApplicationStatus.hired)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final workerIds = hiredApps.map((a) => a.workerId).toSet();
      final nameById = await fetchWorkerDisplayNamesById(workerIds);

      final vms = <_HireHistoryVm>[];
      for (final a in hiredApps) {
        final g = gigById[a.gigId];
        if (g == null) continue;
        final resolved = nameById[a.workerId]?.trim();
        final displayName = (resolved != null && resolved.isNotEmpty)
            ? resolved
            : applicantDisplayNameFallback(a.workerId);

        final avg = await widget.ratings.averageForUser(a.workerId);
        final stars = avg > 0 ? avg.round().clamp(1, 5) : 0;
        vms.add(
          _HireHistoryVm(
            workerId: a.workerId,
            workerName: displayName,
            gigTitle: g.title,
            gigCategory: g.category,
            whenLabel: _formatWhen(a.createdAt),
            payLabel: '₱${(g.pay.amount / 100).round()}',
            stars: stars,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _items = vms;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgapColors.pageBackground,
      appBar: AppBar(
        title: Text(
          'Hiring history',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _error!,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  if (_error != null) const SizedBox(height: 12),
                  if (_items.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          Icon(Icons.history_rounded,
                              size: 46, color: AgapColors.textMuted),
                          const SizedBox(height: 10),
                          Text(
                            'No hires yet',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Once you hire workers, they will appear here.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AgapColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Text(
                      'Recent hires',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ..._items.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _HireCard(item: e),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _HireCard extends StatelessWidget {
  const _HireCard({required this.item});
  final _HireHistoryVm item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgapColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE2E8F0),
            child: Text(
              applicantInitialsFromName(item.workerName, item.workerId),
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.workerName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.gigTitle} • ${item.gigCategory} • ${item.whenLabel}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AgapColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.payLabel,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              _Stars(stars: item.stars),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.stars});
  final int stars;

  @override
  Widget build(BuildContext context) {
    if (stars <= 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (_) => const Icon(Icons.star_border_rounded, size: 16, color: Color(0xFFCBD5E1)),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < stars ? Icons.star_rounded : Icons.star_border_rounded,
          size: 16,
          color: i < stars ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
        ),
      ),
    );
  }
}


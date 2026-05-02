import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';

class BusinessFindWorkersScreen extends StatefulWidget {
  const BusinessFindWorkersScreen({super.key, this.onOpenNotifications});

  final VoidCallback? onOpenNotifications;

  @override
  State<BusinessFindWorkersScreen> createState() =>
      _BusinessFindWorkersScreenState();
}

class _BusinessFindWorkersScreenState extends State<BusinessFindWorkersScreen> {
  final _search = TextEditingController();
  int _filter = 0;

  static const _categories = [
    'All',
    'Warehouse',
    'Food Service',
    'Retail',
    'Events',
  ];

  static const _workers = [
    _WorkerRow(
      initials: 'JC',
      name: 'Juan dela Cruz',
      verified: true,
      availability: 'Available Now',
      availabilityHighlight: true,
      rating: 4.8,
      shifts: 42,
      tags: ['Warehouse', 'Delivery'],
      distanceKm: 0.5,
      rateLabel: '₱120/hr',
      hired: false,
    ),
    _WorkerRow(
      initials: 'MS',
      name: 'Maria Santos',
      verified: true,
      availability: 'Available Now',
      availabilityHighlight: true,
      rating: 4.9,
      shifts: 31,
      tags: ['Retail', 'Food Service'],
      distanceKm: 1.2,
      rateLabel: '₱110/hr',
      hired: true,
    ),
    _WorkerRow(
      initials: 'JR',
      name: 'Jose Ramos',
      verified: true,
      availability: 'Available Tomorrow',
      availabilityHighlight: false,
      rating: 4.6,
      shifts: 18,
      tags: ['Events', 'Warehouse'],
      distanceKm: 2.0,
      rateLabel: '₱115/hr',
      hired: false,
    ),
    _WorkerRow(
      initials: 'AR',
      name: 'Ana Reyes',
      verified: true,
      availability: 'Available Now',
      availabilityHighlight: true,
      rating: 5.0,
      shifts: 56,
      tags: ['Retail'],
      distanceKm: 0.8,
      rateLabel: '₱125/hr',
      hired: false,
    ),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    return ShellChromeBackground(
      kind: ShellChromeKind.business,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
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
                      if (widget.onOpenNotifications != null)
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: AgapColors.businessMint,
                          ),
                          onPressed: widget.onOpenNotifications,
                          icon: Badge(
                            label: Text(
                              '2',
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 18,
                        color: AgapColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pasay City, Metro Manila',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AgapColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search by name or skill…',
                      hintStyle: GoogleFonts.inter(color: AgapColors.textMuted),
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
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final sel = i == _filter;
                  return FilterChip(
                    label: Text(_categories[i]),
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
                '4 available now',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AgapColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottomSafe),
            sliver: SliverList.separated(
              itemCount: _workers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => ShellStaggerItem(
                index: i,
                child: ShellLift(child: _WorkerCard(row: _workers[i])),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerRow {
  const _WorkerRow({
    required this.initials,
    required this.name,
    required this.verified,
    required this.availability,
    required this.availabilityHighlight,
    required this.rating,
    required this.shifts,
    required this.tags,
    required this.distanceKm,
    required this.rateLabel,
    required this.hired,
  });

  final String initials;
  final String name;
  final bool verified;
  final String availability;
  final bool availabilityHighlight;
  final double rating;
  final int shifts;
  final List<String> tags;
  final double distanceKm;
  final String rateLabel;
  final bool hired;
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({required this.row});

  final _WorkerRow row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                      row.initials,
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
                            row.name,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (row.verified) ...[
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
                      row.availability,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: row.availabilityHighlight
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
                        row.rating.toStringAsFixed(1),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${row.shifts} shifts',
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
              for (final t in row.tags)
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
              Icon(Icons.place_outlined, size: 16, color: AgapColors.textMuted),
              const SizedBox(width: 4),
              Text(
                '${row.distanceKm} km',
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
                row.rateLabel,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
              const Spacer(),
              if (row.hired)
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
    );
  }
}

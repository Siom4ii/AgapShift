import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../profile/worker_display_names.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';

enum _ReviewSort { recent, highest }

class UserRatingsScreen extends StatefulWidget {
  const UserRatingsScreen({
    super.key,
    required this.ratings,
    required this.userId,
    required this.title,
  });

  final RatingsRepository ratings;
  final String userId;
  final String title;

  @override
  State<UserRatingsScreen> createState() => _UserRatingsScreenState();
}

class _UserRatingsScreenState extends State<UserRatingsScreen> {
  bool _loading = true;
  String? _error;
  double _avg = 0;
  List<Rating> _items = const [];
  Map<String, String> _gigTitles = const {};
  Map<String, String> _raterNames = const {};
  bool _employerVerified = false;
  _ReviewSort _sort = _ReviewSort.recent;

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
      final avg = await widget.ratings.averageForUser(widget.userId);
      final items = await widget.ratings.listForUser(widget.userId);

      Map<String, String> gigTitles = {};
      Map<String, String> raterNames = {};
      var verified = false;

      if (items.isNotEmpty) {
        raterNames = await fetchWorkerDisplayNamesById(
          items.map((e) => e.raterUserId).toSet(),
        );
        if (SupabaseConfig.isConfigured) {
          final gigIds = items.map((e) => e.gigId).where((id) => id.isNotEmpty).toSet().toList();
          if (gigIds.isNotEmpty) {
            try {
              final rows = await Supabase.instance.client
                  .from('gigs')
                  .select('id,title')
                  .inFilter('id', gigIds);
              for (final raw in rows as List<dynamic>) {
                final m = Map<String, dynamic>.from(raw as Map);
                final id = m['id'] as String?;
                final t = (m['title'] as String?)?.trim();
                if (id != null && t != null && t.isNotEmpty) {
                  gigTitles[id] = t;
                }
              }
            } catch (_) {}
          }
          try {
            final row = await Supabase.instance.client
                .from('profiles')
                .select('account_status')
                .eq('id', widget.userId)
                .maybeSingle();
            verified =
                (row?['account_status'] as String?) == AccountStatus.verified.name;
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        _avg = avg;
        _items = items;
        _gigTitles = gigTitles;
        _raterNames = raterNames;
        _employerVerified = verified;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Rating> get _displayed {
    final copy = List<Rating>.from(_items);
    switch (_sort) {
      case _ReviewSort.recent:
        copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _ReviewSort.highest:
        copy.sort((a, b) {
          final c = b.stars.compareTo(a.stars);
          if (c != 0) return c;
          return b.createdAt.compareTo(a.createdAt);
        });
    }
    return copy;
  }

  Map<int, int> get _distribution {
    final m = {for (var i = 1; i <= 5; i++) i: 0};
    for (final r in _items) {
      if (r.stars >= 1 && r.stars <= 5) {
        m[r.stars] = (m[r.stars] ?? 0) + 1;
      }
    }
    return m;
  }

  String _sentimentForStars(int stars) {
    return switch (stars) {
      5 => 'Excellent performance',
      4 => 'Strong performance',
      3 => 'Solid performance',
      2 => 'Room to improve',
      _ => 'Needs attention',
    };
  }

  String _sentimentForAverage(double a) {
    if (a <= 0) return 'No ratings yet';
    if (a >= 4.75) return 'Excellent';
    if (a >= 4.0) return 'Very strong';
    if (a >= 3.5) return 'Good';
    if (a >= 3.0) return 'Fair';
    return 'Early reputation';
  }

  List<String> _globalHighlights() {
    if (_items.isEmpty) return const [];
    final hits = <String, int>{
      'Professional': 0,
      'On time': 0,
      'Friendly': 0,
      'Reliable': 0,
      'Great communication': 0,
    };
    for (final r in _items) {
      final f = (r.feedback ?? '').toLowerCase();
      if (r.stars >= 4) hits['Reliable'] = hits['Reliable']! + 1;
      if (f.contains('time') || f.contains('punctual') || f.contains('on time')) {
        hits['On time'] = hits['On time']! + 1;
      }
      if (f.contains('friend') || f.contains('kind') || f.contains('nice')) {
        hits['Friendly'] = hits['Friendly']! + 1;
      }
      if (f.contains('prof') || f.contains('pro ')) {
        hits['Professional'] = hits['Professional']! + 1;
      }
      if (f.contains('communicat') || f.contains('responsive')) {
        hits['Great communication'] = hits['Great communication']! + 1;
      }
    }
    final top = hits.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return top.take(3).map((e) => e.key).toList();
  }

  List<String> _tagsForRating(Rating r) {
    final f = (r.feedback ?? '').toLowerCase();
    final out = <String>[];
    if (r.stars >= 5) out.add('Top rated');
    if (f.contains('good') || f.contains('great') || f.contains('best')) {
      out.add('Positive');
    }
    if (f.contains('sound') || f.contains('equipment')) out.add('Gear / setup');
    if (f.contains('team') || f.contains('crew')) out.add('Team player');
    if (out.length > 3) return out.take(3).toList();
    return out;
  }

  String _formatDate(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final l = t.toLocal();
    return '${months[l.month - 1]} ${l.day}, ${l.year}';
  }

  String _raterLine(Rating r) {
    final n = _raterNames[r.raterUserId]?.trim();
    if (n != null && n.isNotEmpty) return n;
    return applicantDisplayNameFallback(r.raterUserId);
  }

  String _shiftLine(Rating r) {
    final t = _gigTitles[r.gigId]?.trim();
    if (t != null && t.isNotEmpty) return t;
    return 'Completed shift';
  }

  @override
  Widget build(BuildContext context) {
    final dist = _distribution;
    final maxBar = dist.values.fold<int>(0, math.max);
    final highlights = _globalHighlights();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F5F9),
        elevation: 0,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF2563EB),
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade800,
                    ),
                  ),
                )
              else ...[
                _SummaryHeroCard(
                  avg: _avg,
                  count: _items.length,
                  sentiment: _sentimentForAverage(_avg),
                  employerVerified: _employerVerified,
                ),
                if (_items.isEmpty) ...[
                  const SizedBox(height: 10),
                  _EmptyStateCard(),
                ] else ...[
                  if (highlights.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _HighlightsCard(lines: highlights),
                  ],
                  const SizedBox(height: 10),
                  _DistributionCard(distribution: dist, maxCount: maxBar),
                  const SizedBox(height: 8),
                  _SortRow(
                    sort: _sort,
                    onChanged: (s) => setState(() => _sort = s),
                  ),
                  if (_items.length <= 3) ...[
                    const SizedBox(height: 8),
                    _ReputationTipCard(count: _items.length),
                  ],
                  const SizedBox(height: 6),
                  ..._displayed.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ReviewCard(
                          rating: r,
                          gigTitle: _shiftLine(r),
                          raterName: _raterLine(r),
                          raterInitials: applicantInitialsFromName(
                            _raterLine(r),
                            r.raterUserId,
                          ),
                          sentiment: _sentimentForStars(r.stars),
                          tags: _tagsForRating(r),
                          formatDate: _formatDate,
                          employerVerified: _employerVerified,
                        ),
                      )),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryHeroCard extends StatelessWidget {
  const _SummaryHeroCard({
    required this.avg,
    required this.count,
    required this.sentiment,
    required this.employerVerified,
  });

  final double avg;
  final int count;
  final String sentiment;
  final bool employerVerified;

  @override
  Widget build(BuildContext context) {
    final rounded = avg > 0 ? avg.round().clamp(1, 5) : 0;

    return Material(
      elevation: 6,
      shadowColor: const Color(0xFFF59E0B).withValues(alpha: 0.25),
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
                      const Color(0xFFFEF3C7).withValues(alpha: 0.95),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -16,
              top: -20,
              child: Icon(
                Icons.star_rounded,
                size: 100,
                color: const Color(0xFFFFE082).withValues(alpha: 0.35),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFFFBEB),
                              Color(0xFFFDE68A),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFFFCD34D).withValues(alpha: 0.9),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFD97706),
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              avg <= 0 ? '—' : avg.toStringAsFixed(1),
                              style: GoogleFonts.inter(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                                color: const Color(0xFF78350F),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (rounded > 0)
                                  ...List.generate(
                                    5,
                                    (i) => Icon(
                                      Icons.star_rounded,
                                      size: 16,
                                      color: i < rounded
                                          ? const Color(0xFFFBBF24)
                                          : const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                if (rounded > 0) const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    sentiment,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              count == 0
                                  ? 'No reviews yet'
                                  : 'Based on $count review${count == 1 ? '' : 's'} from completed work',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF92400E).withValues(alpha: 0.75),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (employerVerified) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: Color(0xFF047857),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Verified on AgapShift',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF047857),
                            ),
                          ),
                        ],
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
  }
}

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgapColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Workers say you are',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AgapColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final line in lines)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 15,
                      color: Colors.green.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      line,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
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

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({
    required this.distribution,
    required this.maxCount,
  });

  final Map<int, int> distribution;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgapColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rating breakdown',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          for (var star = 5; star >= 1; star--)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      '$star★',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: maxCount > 0
                            ? (distribution[star] ?? 0) / maxCount
                            : 0,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFFBBF24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${distribution[star] ?? 0}',
                      textAlign: TextAlign.end,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF334155),
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

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.sort,
    required this.onChanged,
  });

  final _ReviewSort sort;
  final ValueChanged<_ReviewSort> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _ReviewSort mode) {
      final on = sort == mode;
      return Material(
        color: on ? const Color(0xFFDBEAFE) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () => onChanged(mode),
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: on ? const Color(0xFF1D4ED8) : AgapColors.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Text(
          'Recent feedback',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF334155),
          ),
        ),
        const Spacer(),
        chip('Recent', _ReviewSort.recent),
        const SizedBox(width: 8),
        chip('Highest rated', _ReviewSort.highest),
      ],
    );
  }
}

class _ReputationTipCard extends StatelessWidget {
  const _ReputationTipCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_rounded, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count <= 1
                  ? 'Every completed shift is a chance to earn a standout review. '
                      'Show up on time, communicate clearly, and finish strong — '
                      'your reputation grows with each job.'
                  : 'More completed shifts and consistent five-star moments help you '
                      'rise to the top of search. Keep the streak going.',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: const Color(0xFF1E40AF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgapColors.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(Icons.rate_review_outlined, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            'No feedback yet',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Reviews appear here after shifts wrap up. '
            'Complete jobs, stay professional, and ask happy partners to leave honest notes — '
            'it all compounds into trust.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: AgapColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.rating,
    required this.gigTitle,
    required this.raterName,
    required this.raterInitials,
    required this.sentiment,
    required this.tags,
    required this.formatDate,
    required this.employerVerified,
  });

  final Rating rating;
  final String gigTitle;
  final String raterName;
  final String raterInitials;
  final String sentiment;
  final List<String> tags;
  final String Function(DateTime) formatDate;
  final bool employerVerified;

  @override
  Widget build(BuildContext context) {
    final fb = (rating.feedback ?? '').trim();
    final body = fb.isEmpty ? 'No written feedback for this shift.' : fb;

    return Material(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                  ),
                  child: Text(
                    raterInitials.length > 2
                        ? raterInitials.substring(0, 2)
                        : raterInitials,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        raterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              gigTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ),
                          if (employerVerified) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: Colors.green.shade600,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ...List.generate(
                  5,
                  (i) => Icon(
                    Icons.star_rounded,
                    size: 22,
                    color: i < rating.stars
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sentiment,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final t in tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        t,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '“$body”',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
                fontStyle: fb.isEmpty ? FontStyle.italic : FontStyle.normal,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              formatDate(rating.createdAt),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8).withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

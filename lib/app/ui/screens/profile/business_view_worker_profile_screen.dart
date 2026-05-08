import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/worker_identity.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../shift/shift_repository.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../ratings/user_ratings_screen.dart';

class BusinessViewWorkerProfileScreen extends StatefulWidget {
  const BusinessViewWorkerProfileScreen({
    super.key,
    required this.workerId,
    required this.ratings,
    this.shiftRepo,
  });

  final String workerId;
  final RatingsRepository ratings;
  final ShiftRepository? shiftRepo;

  @override
  State<BusinessViewWorkerProfileScreen> createState() =>
      _BusinessViewWorkerProfileScreenState();
}

class _BusinessViewWorkerProfileScreenState
    extends State<BusinessViewWorkerProfileScreen> {
  bool _loading = true;
  String? _error;
  WorkerIdentityDisplay? _identity;
  bool _verified = false;
  double _avg = 0;
  int _completed = 0;

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
      WorkerIdentityDisplay? identity;
      var verified = false;
      if (SupabaseConfig.isConfigured) {
        final row = await Supabase.instance.client
            .from('profiles')
            .select('identity_snapshot, account_status')
            .eq('id', widget.workerId)
            .maybeSingle();
        if (row != null) {
          identity = workerIdentityFromProfileIdentitySnapshot(
            row['identity_snapshot'],
          );
          verified = (row['account_status'] as String?) ==
              AccountStatus.verified.name;
        }
      }

      final avg = await widget.ratings.averageForUser(widget.workerId);

      var completed = 0;
      final shift = widget.shiftRepo;
      if (shift != null) {
        final sessions = await shift.listShiftSessions();
        completed = sessions
            .where((s) =>
                s.workerId == widget.workerId && s.checkOutAt != null)
            .length;
      }

      if (!mounted) return;
      setState(() {
        _identity = identity;
        _verified = verified;
        _avg = avg;
        _completed = completed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _name {
    final n = _identity?.displayName.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Worker';
  }

  String get _tagline {
    final t = _identity?.tagline?.trim();
    if (t != null && t.isNotEmpty) return t;
    final skills = _identity?.skills ?? const <String>[];
    if (skills.isNotEmpty) return skills.take(3).join(' · ');
    return 'Open to shifts';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7FB),
        elevation: 0,
        title: Text(
          'Applicant profile',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 26),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _InlineError(text: _error!)
              else ...[
                _HeaderCard(
                  name: _name,
                  tagline: _tagline,
                  verified: _verified,
                  rating: _avg,
                  completed: _completed,
                  onViewReviews: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => UserRatingsScreen(
                          ratings: widget.ratings,
                          userId: widget.workerId,
                          title: 'Worker reviews',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'About',
                  child: Text(
                    (_identity?.bio == null ||
                            _identity!.bio!.trim().isEmpty)
                        ? 'No bio yet.'
                        : _identity!.bio!.trim(),
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if ((_identity?.skills ?? const <String>[]).isNotEmpty)
                  _SectionCard(
                    title: 'Skills',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in _identity!.skills)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AgapColors.businessMint,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AgapColors.businessGreenDeep.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                            child: Text(
                              s,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                color: AgapColors.businessGreenDeep,
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
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.name,
    required this.tagline,
    required this.verified,
    required this.rating,
    required this.completed,
    required this.onViewReviews,
  });

  final String name;
  final String tagline;
  final bool verified;
  final double rating;
  final int completed;
  final VoidCallback onViewReviews;

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return 'W';
    if (parts.length == 1) {
      final p = parts[0];
      return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasRating = rating > 0;
    final ratingText = hasRating ? rating.toStringAsFixed(1) : '—';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AgapColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AgapColors.businessGreenDeep,
                  AgapColors.businessGreen,
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(name),
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (verified)
                      const Icon(
                        Icons.verified_rounded,
                        color: Color(0xFF2563EB),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tagline,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: AgapColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$ratingText ($completed shifts)',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF92400E),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: onViewReviews,
                      child: Text(
                        'View reviews',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AgapColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              fontSize: 14.5,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          child,
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


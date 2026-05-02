import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../ratings/mock_ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/mock_shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import '../../widgets/verification_status_card.dart';

class WorkerProfileScreen extends StatefulWidget {
  const WorkerProfileScreen({
    super.key,
    required this.session,
    required this.shiftRepo,
    required this.ratings,
    this.embedded = false,
  });

  final SessionController session;
  final MockShiftRepository shiftRepo;
  final MockRatingsRepository ratings;
  final bool embedded;

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  double _avg = 0;
  int _completed = 0;
  int _reviewCount = 0;
  List<Rating> _reviews = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = appActorId(widget.session, mockFallback: '');
    final avg = await widget.ratings.averageForUser(userId);
    final sessions = await widget.shiftRepo.listShiftSessions();
    final completed = sessions
        .where((s) => s.workerId == userId && s.checkOutAt != null)
        .length;
    final reviews = await widget.ratings.listForUser(userId);
    if (!mounted) return;
    setState(() {
      _avg = avg;
      _completed = completed;
      _reviews = reviews;
      _reviewCount = reviews.length;
    });
  }

  String get _displayName =>
      _nameFromEmail(widget.session.state.email ?? 'worker');

  bool get _verified =>
      widget.session.state.accountStatus == AccountStatus.verified;

  static String _nameFromEmail(String email) {
    if (email.isEmpty) return 'Worker';
    final local = email.split('@').first;
    return local
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map(
          (w) =>
              w[0].toUpperCase() +
              (w.length > 1 ? w.substring(1).toLowerCase() : ''),
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final ratingDisplay = _avg > 0 ? _avg : 4.9;
    final reviewsLabel = _reviewCount > 0 ? _reviewCount : 124;
    final shiftsDisplay = _completed > 0 ? _completed : 87;

    final body = ShellChromeBackground(
      kind: ShellChromeKind.worker,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AgapColors.borderSubtle,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 56,
                      backgroundColor: AgapColors.mintSurface,
                      child: Icon(
                        Icons.person_rounded,
                        size: 64,
                        color: AgapColors.primary,
                      ),
                    ),
                  ),
                  if (_verified)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AgapColors.primary,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'VERIFIED',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _displayName,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Reliable & fast-paced gig worker',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AgapColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      color: AgapColors.accentOrange,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${ratingDisplay.toStringAsFixed(1)} / 5',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF9A3412),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '($reviewsLabel Reviews)',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AgapColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            VerificationStatusCard(session: widget.session),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AgapColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contact (demo)')),
                  );
                },
                icon: const Icon(Icons.mail_outline_rounded),
                label: Text(
                  'Contact ${_displayName.split(' ').first}',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF111827),
                  side: const BorderSide(color: AgapColors.borderSubtle),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Resume download (demo)')),
                  );
                },
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  'Download Resume',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.work_outline_rounded,
                    value: '$shiftsDisplay',
                    label: 'Shifts Completed',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.schedule_rounded,
                    value: '98%',
                    label: 'On-Time Rate',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SectionCard(
              title: 'About Me',
              titleIcon: Icons.menu_book_outlined,
              child: Text(
                'Experienced in physical labor and logistics with a strong focus on punctuality and safety. '
                'Comfortable in fast-paced warehouse and event environments across the metro.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: const Color(0xFF374151),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'Verified Skills',
              titleIcon: Icons.lightbulb_outline_rounded,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _SkillChip(
                    icon: Icons.warehouse_rounded,
                    label: 'Warehouse Operations',
                  ),
                  _SkillChip(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Event Setup',
                  ),
                  _SkillChip(
                    icon: Icons.local_shipping_rounded,
                    label: 'Delivery Driver',
                  ),
                  _SkillChip(
                    icon: Icons.build_rounded,
                    label: 'Basic Assembly',
                  ),
                  _SkillChip(
                    icon: Icons.precision_manufacturing_rounded,
                    label: 'Forklift Certified',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ReviewsSection(reviews: _reviews, onViewAll: () {}),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

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
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AgapColors.primaryBright, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AgapColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.titleIcon,
    required this.child,
  });

  final String title;
  final IconData titleIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgapColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(titleIcon, size: 20, color: AgapColors.primaryBright),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF2563EB)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E40AF),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({required this.reviews, required this.onViewAll});

  final List<Rating> reviews;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final items = reviews.isEmpty ? _demoReviews : reviews.take(2).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgapColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 20,
                color: AgapColors.primaryBright,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recent Business Reviews',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: onViewAll,
                child: Text(
                  'View All',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: AgapColors.primaryBright,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 24),
            _ReviewTile(item: items[i], isDemo: reviews.isEmpty),
          ],
        ],
      ),
    );
  }

  static final List<_DemoReview> _demoReviews = [
    _DemoReview(
      business: 'Logistics Hub West',
      initial: 'L',
      stars: 5.0,
      subtitle: 'Warehouse Shift • Oct 12',
      body: 'Showed up early and worked efficiently. Would hire again.',
    ),
    _DemoReview(
      business: 'Elite Events Co.',
      initial: 'E',
      stars: 5.0,
      subtitle: 'Event Teardown • Sep 28',
      body: 'Great attitude and handled heavy lifting without issue.',
    ),
  ];
}

class _DemoReview {
  const _DemoReview({
    required this.business,
    required this.initial,
    required this.stars,
    required this.subtitle,
    required this.body,
  });

  final String business;
  final String initial;
  final double stars;
  final String subtitle;
  final String body;
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.item, required this.isDemo});

  final Object item;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    if (isDemo) {
      final d = item as _DemoReview;
      return _reviewRow(
        title: d.business,
        initial: d.initial,
        stars: d.stars,
        subtitle: d.subtitle,
        body: d.body,
      );
    }
    final r = item as Rating;
    return _reviewRow(
      title: 'Business ${r.raterUserId}',
      initial: r.raterUserId.isNotEmpty ? r.raterUserId[0].toUpperCase() : '?',
      stars: r.stars.toDouble(),
      subtitle: r.createdAt.toLocal().toString().split(' ').first,
      body: r.feedback ?? 'Great work on this shift.',
    );
  }

  Widget _reviewRow({
    required String title,
    required String initial,
    required double stars,
    required String subtitle,
    required String body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: AgapColors.mintSurface,
          child: Text(
            initial,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: AgapColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: AgapColors.accentOrange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    stars.toStringAsFixed(1),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: AgapColors.accentOrange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AgapColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.4,
                  color: const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

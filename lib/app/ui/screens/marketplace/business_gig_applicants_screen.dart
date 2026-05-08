import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../notifications/notification_repository.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../profile/worker_display_names.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import '../../widgets/success_feedback.dart';
import '../shift/employer_attendance_qr_screen.dart';
import '../profile/business_view_worker_profile_screen.dart';

class BusinessGigApplicantsScreen extends StatefulWidget {
  const BusinessGigApplicantsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.session,
    required this.gig,
    required this.ratings,
    this.shiftRepo,
  });

  final MarketplaceRepository repo;
  final NotificationRepository notifications;
  final SessionController session;
  final Gig gig;
  final RatingsRepository ratings;
  final ShiftRepository? shiftRepo;

  @override
  State<BusinessGigApplicantsScreen> createState() =>
      _BusinessGigApplicantsScreenState();
}

class _BusinessGigApplicantsScreenState extends State<BusinessGigApplicantsScreen> {
  bool _loading = false;
  List<GigApplication> _apps = const [];
  String? _error;
  Map<String, String> _displayNames = const {};
  Map<String, double> _ratingByWorker = const {};

  static final _headerGradient = LinearGradient(
    colors: [
      AgapColors.businessGreenDeep,
      AgapColors.businessGreen,
      AgapColors.businessGreenLight,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

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
      final apps = await widget.repo.listApplicants(widget.gig.id);

      final ids = apps.map((a) => a.workerId).toSet();
      final names = await fetchWorkerDisplayNamesById(ids);
      final ratings = <String, double>{};
      for (final id in ids) {
        ratings[id] = await widget.ratings.averageForUser(id);
      }

      if (!mounted) return;
      setState(() {
        _apps = apps;
        _displayNames = names;
        _ratingByWorker = ratings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _hire(GigApplication a) async {
    final businessId = appActorId(widget.session, mockFallback: 'business');
    try {
      final result = await widget.repo.hireApplicant(
        gigId: widget.gig.id,
        applicationId: a.id,
        businessId: businessId,
      );
      await widget.notifications.add(
        userId: result.selectedWorkerId,
        title: 'You were hired',
        body: 'Gig: ${widget.gig.title}',
        data: {'gigId': widget.gig.id},
      );
      for (final wid in result.rejectedWorkerIds) {
        await widget.notifications.add(
          userId: wid,
          title: 'Application update',
          body: 'Not selected for: ${widget.gig.title}',
          data: {'gigId': widget.gig.id},
        );
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showSuccessSnackBar(context, 'Worker hired successfully');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot hire: $e')),
      );
    }
  }

  String _displayNameFor(String workerId) {
    final n = _displayNames[workerId]?.trim();
    if (n != null && n.isNotEmpty) return n;
    return applicantDisplayNameFallback(workerId);
  }

  String _initialsFor(String workerId) {
    return applicantInitialsFromName(_displayNameFor(workerId), workerId);
  }

  bool get _showShiftQr =>
      widget.shiftRepo != null &&
      (widget.gig.status == GigStatus.open ||
          widget.gig.status == GigStatus.filled ||
          widget.gig.status == GigStatus.ongoing);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellChromeBackground(
        kind: ShellChromeKind.business,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(gradient: _headerGradient),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Material(
                              color: Colors.white.withValues(alpha: 0.22),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: IconButton(
                                onPressed: () => Navigator.of(context).maybePop(),
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Applicants',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.gig.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_showShiftQr)
                              IconButton(
                                tooltip: 'Show attendance QR',
                                onPressed: () {
                                  final r = widget.shiftRepo;
                                  if (r == null) return;
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => EmployerAttendanceQrScreen(
                                        shiftRepo: r,
                                        gig: widget.gig,
                                      ),
                                    ),
                                  );
                                },
                                icon: Icon(
                                  Icons.qr_code_2_rounded,
                                  color: Colors.white.withValues(alpha: 0.95),
                                ),
                              ),
                            IconButton(
                              tooltip: 'Refresh',
                              onPressed: _loading ? null : _load,
                              icon: Icon(
                                Icons.refresh_rounded,
                                color: Colors.white.withValues(alpha: 0.95),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: const _OffAppPayHiringNote(),
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: AgapColors.businessGreen,
                  ),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error: $_error',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: AgapColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
            else if (_apps.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline_rounded,
                        size: 48,
                        color: AgapColors.textMuted.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No applicants yet',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Share your job or check back later.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AgapColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + bottom),
                sliver: SliverList.separated(
                  itemCount: _apps.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final a = _apps[i];
                    final rating = _ratingByWorker[a.workerId] ?? 0;
                    final canHire = widget.gig.status == GigStatus.open &&
                        a.status == ApplicationStatus.applied;
                    return _ApplicantCard(
                      initials: _initialsFor(a.workerId),
                      name: _displayNameFor(a.workerId),
                      statusLabel: _appStatus(a.status),
                      status: a.status,
                      appliedAt: a.createdAt,
                      rating: rating,
                      showHire: canHire,
                      onHire: () => _hire(a),
                      onOpenProfile: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => BusinessViewWorkerProfileScreen(
                              workerId: a.workerId,
                              ratings: widget.ratings,
                              shiftRepo: widget.shiftRepo,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _appStatus(ApplicationStatus s) => switch (s) {
        ApplicationStatus.applied => 'Applied',
        ApplicationStatus.withdrawn => 'Withdrawn',
        ApplicationStatus.rejected => 'Rejected',
        ApplicationStatus.hired => 'Hired',
      };
}

class _OffAppPayHiringNote extends StatelessWidget {
  const _OffAppPayHiringNote();

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
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AgapColors.businessMint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.handshake_outlined,
              color: AgapColors.businessGreenDeep,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pay & hiring',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AgapColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Wages are agreed and paid directly between you and the worker '
                  '(not through Nexora). Use attendance scans to record shift times.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: const Color(0xFF334155),
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

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({
    required this.initials,
    required this.name,
    required this.statusLabel,
    required this.status,
    required this.appliedAt,
    required this.rating,
    required this.showHire,
    required this.onHire,
    required this.onOpenProfile,
  });

  final String initials;
  final String name;
  final String statusLabel;
  final ApplicationStatus status;
  final DateTime appliedAt;
  final double rating;
  final bool showHire;
  final VoidCallback onHire;
  final VoidCallback onOpenProfile;

  Color get _statusAccent => switch (status) {
        ApplicationStatus.applied => const Color(0xFF2563EB),
        ApplicationStatus.hired => AgapColors.businessGreenDeep,
        ApplicationStatus.rejected => const Color(0xFFDC2626),
        ApplicationStatus.withdrawn => AgapColors.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${appliedAt.month}/${appliedAt.day}/${appliedAt.year.toString().substring(2)}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenProfile,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AgapColors.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AgapColors.businessGreenDeep,
            child: Text(
              initials,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
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
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.verified_rounded,
                      size: 18,
                      color: AgapColors.businessGreen,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _statusAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _statusAccent.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _statusAccent,
                        ),
                      ),
                    ),
                    Text(
                      'Applied $dateStr',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AgapColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: const Color(0xFFEAB308),
                  ),
                  Text(
                    rating > 0 ? rating.toStringAsFixed(1) : '—',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              if (showHire) ...[
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AgapColors.businessGreenDeep,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onHire,
                  child: Text(
                    'Hire',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ],
          ),
        ),
      ),
    );
  }
}

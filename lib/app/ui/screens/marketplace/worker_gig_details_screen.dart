import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/business_identity.dart';
import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../location/geo_distance.dart';
import '../../../location/user_geo_point.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../notifications/notification_repository.dart';
import '../../../worker/worker_apply_guard.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/locked_action.dart';
import '../../widgets/success_feedback.dart';
import '../subscriptions/worker_subscription_screen.dart';

const Color _purpleDeep = Color(0xFF5B21B6);
const Color _purple = Color(0xFF7C3AED);
const Color _purpleBright = Color(0xFF8B5CF6);
const Color _pageBg = Color(0xFFF3F4F6);

class _ParsedGigDescription {
  const _ParsedGigDescription({
    required this.about,
    this.requirementsText,
    this.benefitsText,
    this.workersNeeded,
    this.urgent = false,
  });

  final String about;
  final String? requirementsText;
  final String? benefitsText;
  final int? workersNeeded;
  final bool urgent;
}

_ParsedGigDescription _parseGigDescription(String full) {
  var about = '';
  String? req;
  String? ben;
  int? workers;
  var urgent = false;

  final blocks = full
      .split(RegExp(r'\n\n+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  for (final b in blocks) {
    final lower = b.toLowerCase();
    if (lower.startsWith('requirements:')) {
      req = b.substring(b.indexOf(':') + 1).trim();
    } else if (lower.startsWith('benefits:')) {
      ben = b.substring(b.indexOf(':') + 1).trim();
    } else if (lower.startsWith('workers needed:')) {
      final m = RegExp(r'(\d+)').firstMatch(b);
      workers = m != null ? int.tryParse(m.group(1)!) : null;
    } else if (lower.startsWith('marked as urgent')) {
      urgent = true;
      about = about.isEmpty ? b : '$about\n\n$b';
    } else {
      about = about.isEmpty ? b : '$about\n\n$b';
    }
  }

  if (about.isEmpty) about = full.trim();
  return _ParsedGigDescription(
    about: about,
    requirementsText: req,
    benefitsText: ben,
    workersNeeded: workers,
    urgent: urgent,
  );
}

class WorkerGigDetailsScreen extends StatefulWidget {
  const WorkerGigDetailsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.session,
    required this.gigId,
  });

  final MarketplaceRepository repo;
  final NotificationRepository notifications;
  final SessionController session;
  final String gigId;

  @override
  State<WorkerGigDetailsScreen> createState() => _WorkerGigDetailsScreenState();
}

class _WorkerGigDetailsScreenState extends State<WorkerGigDetailsScreen> {
  Gig? _gig;
  GigApplication? _myApplication;
  String? _businessName;
  double? _distanceKmFromUser;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _fetchBusinessName(String businessId) async {
    if (!SupabaseConfig.isConfigured) return null;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('identity_snapshot')
          .eq('id', businessId)
          .maybeSingle();
      if (row == null) return null;
      final biz = businessIdentityFromProfileIdentitySnapshot(
        row['identity_snapshot'],
      );
      if (biz != null && biz.displayName.trim().isNotEmpty) {
        return biz.displayName.trim();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _distanceKmFromUser = null;
      _myApplication = null;
    });
    try {
      final gig = await widget.repo.getGig(widget.gigId);
      String? bizName;
      double? distKm;
      GigApplication? mine;
      if (gig != null) {
        bizName = await _fetchBusinessName(gig.businessId);
        final userPt = await tryGetCurrentUserGeoPoint();
        if (userPt != null) {
          distKm = geoDistanceMetersApprox(userPt, gig.location) / 1000.0;
        }
        final workerId = appActorId(widget.session, mockFallback: 'worker');
        final apps = await widget.repo.listApplications();
        for (final a in apps) {
          if (a.gigId == widget.gigId && a.workerId == workerId) {
            mine = a;
            break;
          }
        }
      }
      if (mounted) {
        setState(() {
          _gig = gig;
          _myApplication = mine;
          _businessName = bizName;
          _distanceKmFromUser = distKm;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    if (!canPerformVerifiedAction(widget.session)) {
      await showLockedFeatureDialog(
        context,
        session: widget.session,
        featureName: 'Applying to jobs',
      );
      return;
    }
    final workerId = appActorId(widget.session, mockFallback: 'worker');
    if (_myApplication != null) return;
    final shift = MarketplaceScope.of(context).shift;
    final block = await WorkerApplyGuard.blockingReason(
      shiftRepo: shift,
      session: widget.session,
    );
    if (!mounted) return;
    if (block != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'Subscription required',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
          content: Text(block, style: GoogleFonts.inter(height: 1.35)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => WorkerSubscriptionScreen(
                      session: widget.session,
                    ),
                  ),
                );
              },
              child: const Text('View plans'),
            ),
          ],
        ),
      );
      return;
    }
    try {
      final submitted = await widget.repo.applyToGig(
        gigId: widget.gigId,
        workerId: workerId,
      );
      final gig = await widget.repo.getGig(widget.gigId);
      if (gig != null) {
        await widget.notifications.add(
          userId: gig.businessId,
          title: 'New applicant',
          body: '$workerId applied to: ${gig.title}',
          data: {'gigId': gig.id},
        );
        await widget.notifications.add(
          userId: workerId,
          title: 'Application sent',
          body: 'You applied to: ${gig.title}',
          data: {'gigId': gig.id},
        );
      }
      if (!mounted) return;
      setState(() => _myApplication = submitted);
      showSuccessSnackBar(context, 'Application sent successfully');
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      if (msg.contains('Already applied')) {
        await _load();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot apply: $e')),
      );
    }
  }

  static String _formatStart(DateTime utc) {
    final local = utc.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(local.year, local.month, local.day);
    final h24 = local.hour;
    final h = h24 > 12 ? h24 - 12 : (h24 == 0 ? 12 : h24);
    final ap = h24 >= 12 ? 'PM' : 'AM';
    final mm = local.minute.toString().padLeft(2, '0');
    final timeStr = '$h:$mm $ap';
    if (d == today) return 'Today, $timeStr';
    if (d == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $timeStr';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}, $timeStr';
  }

  static String _payLabel(Gig gig, double hours) {
    final peso = gig.pay.amount / 100.0;
    if (hours <= 0) return '₱${peso.toStringAsFixed(0)}';
    if (hours <= 10) {
      final perHr = peso / hours;
      return '₱${perHr.toStringAsFixed(0)}/hr';
    }
    return '₱${peso.toStringAsFixed(0)}/day';
  }

  static String _payBottomLabel(Gig gig, double hours) {
    final peso = gig.pay.amount / 100.0;
    if (hours <= 10 && hours > 0) {
      return '₱${(peso / hours).toStringAsFixed(0)}/hr · ₱${peso.toStringAsFixed(0)} total';
    }
    return '₱${peso.toStringAsFixed(0)} for this gig';
  }

  static IconData _categoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('warehouse')) return Icons.inventory_2_rounded;
    if (c.contains('food') || c.contains('service')) return Icons.restaurant_rounded;
    if (c.contains('event')) return Icons.celebration_rounded;
    if (c.contains('clean')) return Icons.cleaning_services_rounded;
    if (c.contains('deliver')) return Icons.local_shipping_rounded;
    return Icons.work_outline_rounded;
  }

  static List<String> _requirementBullets(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    final t = raw.trim();
    final byPeriod = t.split(RegExp(r'\.\s+')).map((s) => s.trim()).where(
          (s) => s.isNotEmpty,
        );
    final list = byPeriod.toList();
    if (list.length > 1) {
      return list.map((s) => s.endsWith('.') ? s : '$s.').toList();
    }
    return [t];
  }

  static List<String> _benefitChips(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    return raw
        .split(RegExp(r'[,•\n]'))
        .map((s) => s.replaceAll(RegExp(r'\.+$'), '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _pageBg,
        body: const Center(child: CircularProgressIndicator(color: _purple)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: _pageBg,
          foregroundColor: _purpleDeep,
        ),
        body: Center(child: Text('Error: $_error')),
      );
    }

    final gig = _gig;
    if (gig == null) {
      return Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: _pageBg,
          foregroundColor: _purpleDeep,
        ),
        body: const Center(child: Text('Gig not found')),
      );
    }

    final parsed = _parseGigDescription(gig.description);
    final business = _businessName ?? 'Business';
    final minutes = gig.endAt.difference(gig.startAt).inMinutes.clamp(1, 24 * 60);
    final hours = minutes / 60.0;
    final durationLabel =
        hours >= 1 ? '${hours.round()} hrs' : '$minutes min';
    final payPrimary = _payLabel(gig, hours);
    final payBottom = _payBottomLabel(gig, hours);
    final slots = gig.workersNeeded ?? parsed.workersNeeded;
    final slotsLabel = slots != null ? '$slots opening${slots == 1 ? '' : 's'}' : 'Open';
    final showUrgentBanner = gig.isUrgent || parsed.urgent;

    return Scaffold(
      backgroundColor: _pageBg,
      body: Stack(
        children: [
          RefreshIndicator(
            color: _purple,
            onRefresh: _load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
              SliverToBoxAdapter(
                child: _GigHeader(
                  title: gig.title,
                  businessName: business,
                  category: gig.category,
                  categoryIcon: _categoryIcon(gig.category),
                  showBoosted: gig.isBoostedActive,
                  onBack: () => Navigator.of(context).maybePop(),
                  onBookmark: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Saved to bookmarks (demo)')),
                    );
                  },
                  onShare: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Share (demo)')),
                    );
                  },
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.payments_rounded,
                            iconColor: const Color(0xFFE65100),
                            iconBg: const Color(0xFFFFF3E0),
                            label: 'Pay',
                            value: payPrimary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.schedule_rounded,
                            iconColor: _purple,
                            iconBg: const Color(0xFFEDE9FE),
                            label: 'Duration',
                            value: durationLabel,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.calendar_today_rounded,
                            iconColor: const Color(0xFF1565C0),
                            iconBg: const Color(0xFFE3F2FD),
                            label: 'Start Time',
                            value: _formatStart(gig.startAt),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.groups_rounded,
                            iconColor: _purpleDeep,
                            iconBg: const Color(0xFFF3E8FF),
                            label: 'Slots',
                            value: slotsLabel,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _LocationCard(
                      address: gig.addressLabel,
                      lat: gig.location.lat,
                      lng: gig.location.lng,
                      distanceKmFromUser: _distanceKmFromUser,
                    ),
                    const SizedBox(height: 16),
                    if (parsed.about.isNotEmpty)
                      _SectionCard(
                        title: 'About This Job',
                        child: Text(
                          parsed.about,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            height: 1.55,
                            color: const Color(0xFF374151),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (showUrgentBanner) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFFDBA74),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Urgent — applicants may be prioritized.',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: const Color(0xFF9A3412),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_requirementBullets(parsed.requirementsText).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Requirements',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final line
                                in _requirementBullets(parsed.requirementsText))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 20,
                                      color: _purple,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        line,
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          height: 1.45,
                                          color: const Color(0xFF374151),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (_benefitChips(parsed.benefitsText).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Benefits',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final b in _benefitChips(parsed.benefitsText))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0xFF6EE7B7),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: Colors.green.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      b,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF047857),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ApplyBottomBar(
              payLine: payBottom,
              onApply: _apply,
              myApplication: _myApplication,
              gigStatus: gig.status,
            ),
          ),
        ],
      ),
    );
  }
}

class _GigHeader extends StatelessWidget {
  const _GigHeader({
    required this.title,
    required this.businessName,
    required this.category,
    required this.categoryIcon,
    this.showBoosted = false,
    required this.onBack,
    required this.onBookmark,
    required this.onShare,
  });

  final String title;
  final String businessName;
  final String category;
  final IconData categoryIcon;
  final bool showBoosted;
  final VoidCallback onBack;
  final VoidCallback onBookmark;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_purpleDeep, _purple, _purpleBright],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, top + 4, 8, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onBookmark,
                  icon: const Icon(Icons.bookmark_border_rounded, color: Colors.white),
                ),
                IconButton(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined, color: Colors.white),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(
                      categoryIcon,
                      color: const Color(0xFF78350F),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          businessName,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFFFFE082),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    category,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (showBoosted)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFDE68A),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.rocket_launch_rounded,
                                      color: Color(0xFF78350F),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Boosted',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF78350F),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AgapColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
              height: 1.2,
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
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.address,
    required this.lat,
    required this.lng,
    this.distanceKmFromUser,
  });

  final String address;
  final double lat;
  final double lng;
  final double? distanceKmFromUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place_rounded, color: _purple, size: 22),
              const SizedBox(width: 8),
              Text(
                'Location',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            address,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
              height: 1.4,
            ),
          ),
          if (distanceKmFromUser != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.near_me_outlined,
                  size: 18,
                  color: AgapColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'About ${distanceKmFromUser!.toStringAsFixed(1)} km from your location',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AgapColors.textMuted,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 16, color: _purple),
              const SizedBox(width: 4),
              Text(
                '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _purple.withValues(alpha: 0.15),
                    _pageBg,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.map_rounded, size: 48, color: _purple.withValues(alpha: 0.35)),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(Icons.location_pin, color: _purple, size: 32),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplyBottomBar extends StatelessWidget {
  const _ApplyBottomBar({
    required this.payLine,
    required this.onApply,
    required this.myApplication,
    required this.gigStatus,
  });

  final String payLine;
  final VoidCallback onApply;
  final GigApplication? myApplication;
  final GigStatus gigStatus;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final gigOpen = gigStatus == GigStatus.open;
    final app = myApplication;

    Widget action;
    if (app != null) {
      switch (app.status) {
        case ApplicationStatus.applied:
          action = _StatusApplyButton(
            icon: Icons.hourglass_top_rounded,
            title: 'Application pending',
            subtitle: 'Waiting for the employer',
            foreground: _purple,
            background: const Color(0xFFEDE9FE),
            borderColor: _purple.withValues(alpha: 0.35),
            onPressed: null,
          );
        case ApplicationStatus.hired:
          action = _StatusApplyButton(
            icon: Icons.celebration_rounded,
            title: "You're hired",
            subtitle: 'Check your shifts for next steps',
            foreground: const Color(0xFF047857),
            background: const Color(0xFFD1FAE5),
            borderColor: const Color(0xFF6EE7B7),
            onPressed: null,
          );
        case ApplicationStatus.rejected:
          action = _StatusApplyButton(
            icon: Icons.info_outline_rounded,
            title: 'Not selected',
            subtitle: 'This employer chose another applicant',
            foreground: AgapColors.textMuted,
            background: const Color(0xFFF3F4F6),
            borderColor: const Color(0xFFE5E7EB),
            onPressed: null,
          );
        case ApplicationStatus.withdrawn:
          action = FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            onPressed: gigOpen ? onApply : null,
            child: Text(
              'Apply Now',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          );
      }
    } else if (!gigOpen) {
      action = _StatusApplyButton(
        icon: Icons.lock_outline_rounded,
        title: gigStatus == GigStatus.filled
            ? 'Position filled'
            : 'No longer hiring',
        subtitle: 'This listing is not accepting applications',
        foreground: AgapColors.textMuted,
        background: const Color(0xFFF3F4F6),
        borderColor: const Color(0xFFE5E7EB),
        onPressed: null,
      );
    } else {
      action = FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        onPressed: onApply,
        child: Text(
          'Apply Now',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      );
    }

    return Material(
      elevation: 12,
      shadowColor: Colors.black26,
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pay',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AgapColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    payLine,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _purple,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              fit: FlexFit.loose,
              child: action,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusApplyButton extends StatelessWidget {
  const _StatusApplyButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.foreground,
    required this.background,
    required this.borderColor,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color foreground;
  final Color background;
  final Color borderColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          constraints: const BoxConstraints(maxWidth: 220),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: foreground,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.25,
                        color: foreground.withValues(alpha: 0.85),
                      ),
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

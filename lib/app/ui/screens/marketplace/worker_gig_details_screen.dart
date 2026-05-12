import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../domain/business_identity.dart';
import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../../domain/worker_identity.dart';
import '../../../location/geo_distance.dart';
import '../../../location/user_geo_point.dart';
import '../onboarding/davao_del_sur_locations.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../notifications/notification_repository.dart';
import '../../../worker/worker_apply_guard.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../supabase/supabase_config.dart';
import '../../../profile/worker_display_names.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/locked_action.dart';
import '../subscriptions/worker_subscription_screen.dart';

const Color _purpleDeep = Color(0xFF5B21B6);
const Color _purple = Color(0xFF7C3AED);
const Color _purpleBright = Color(0xFF8B5CF6);
const Color _pageBg = Color(0xFFF3F4F6);

/// Replace with your live URLs when available.
const String _kPrivacyPolicyUrl = 'https://agapshift.app/privacy';
const String _kTermsUrl = 'https://agapshift.app/terms';

enum WorkerApplyDialogResult { cancelled, completedStay, completedBrowseJobs }

const Color _linkPurple = Color(0xFF9B87F0);
const Color _linkPurplePressed = Color(0xFF7C3AED);

Color _hairlineDivider([double opacity = 0.11]) =>
    const Color(0xFF0F172A).withValues(alpha: opacity);

class WorkerApplyJobSnapshot {
  const WorkerApplyJobSnapshot({
    required this.title,
    required this.businessName,
    required this.payLine,
    required this.durationLine,
    required this.scheduleLine,
    required this.locationLine,
    this.employerVerified = false,
  });

  final String title;
  final String businessName;
  final String payLine;
  final String durationLine;
  final String scheduleLine;
  final String locationLine;
  final bool employerVerified;
}

String _formatApplyScheduleLine(Gig g) {
  final sl = g.startAt.toLocal();
  final el = g.endAt.toLocal();
  String t(DateTime d) {
    final h24 = d.hour;
    final h = h24 > 12 ? h24 - 12 : (h24 == 0 ? 12 : h24);
    final ap = h24 >= 12 ? 'PM' : 'AM';
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m $ap';
  }

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final sameDay =
      sl.year == el.year && sl.month == el.month && sl.day == el.day;
  if (sameDay) {
    return '${months[sl.month - 1]} ${sl.day} · ${t(sl)} – ${t(el)}';
  }
  return '${months[sl.month - 1]} ${sl.day} ${t(sl)} → ${months[el.month - 1]} ${el.day} ${t(el)}';
}

Future<void> _openPolicyUrl(BuildContext context, Uri uri) async {
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open link: $uri')),
    );
  }
}

void _showFullLegalSheet(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final h = MediaQuery.sizeOf(context).height * 0.72;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: SizedBox(
          height: h,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              16 + MediaQuery.paddingOf(ctx).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      body,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

const String _kFullPrivacyBody =
    'Republic Act No. 10173 (Data Privacy Act of 2012)\n\n'
    'AgapShift collects and processes personal information you provide '
    '(such as your name, contact details, profile information, and work-related '
    'documents) to operate the platform, verify accounts, match you with '
    'employers, and communicate about applications and shifts.\n\n'
    'We use your data only for legitimate purposes, strive to keep it accurate '
    'and secure, and retain it only as long as needed for those purposes or as '
    'required by law. Depending on applicable law, you may have rights to access, '
    'correct, or object to certain processing.\n\n'
    'By submitting an application, you confirm that the information you provide '
    'is truthful to the best of your knowledge.';

const String _kFullTermsBody =
    '• Your application does not guarantee employment; the employer decides who to hire.\n'
    '• You agree to communicate honestly and to attend as agreed if hired, or withdraw in good time if you cannot.\n'
    '• Pay, schedule, and duties follow the listing and any agreement with the employer; AgapShift is not a party to your employment contract.\n'
    '• You must not misuse the platform (including fraud, harassment, or false documents).\n'
    '• AgapShift may update policies and notices; continued use may constitute acceptance where permitted by law.';

Future<WorkerApplyDialogResult> showWorkerApplyConfirmationDialog(
  BuildContext context, {
  required WorkerApplyJobSnapshot snapshot,
  required Future<void> Function() onSubmit,
}) async {
  final r = await showGeneralDialog<WorkerApplyDialogResult>(
    context: context,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.89,
            child: _ApplyJobDialog(snapshot: snapshot, onSubmit: onSubmit),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: curved,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color: Colors.black.withValues(alpha: 0.4),
              ),
            ),
          ),
          FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
              child: child,
            ),
          ),
        ],
      );
    },
  );
  return r ?? WorkerApplyDialogResult.cancelled;
}

class _ScaleOnPress extends StatefulWidget {
  const _ScaleOnPress({required this.child});

  final Widget child;

  @override
  State<_ScaleOnPress> createState() => _ScaleOnPressState();
}

class _ScaleOnPressState extends State<_ScaleOnPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _SoftPolicyLink extends StatefulWidget {
  const _SoftPolicyLink({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_SoftPolicyLink> createState() => _SoftPolicyLinkState();
}

class _SoftPolicyLinkState extends State<_SoftPolicyLink> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: widget.onTap,
      onHighlightChanged: (v) => setState(() => _pressed = v),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              widget.icon,
              size: 15,
              color: _pressed ? _linkPurplePressed : _linkPurple,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.35,
                  color: _pressed ? _linkPurplePressed : _linkPurple,
                  decoration:
                      _pressed ? TextDecoration.underline : TextDecoration.none,
                  decorationColor: _linkPurplePressed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplyJobDialog extends StatefulWidget {
  const _ApplyJobDialog({
    required this.snapshot,
    required this.onSubmit,
  });

  final WorkerApplyJobSnapshot snapshot;
  final Future<void> Function() onSubmit;

  @override
  State<_ApplyJobDialog> createState() => _ApplyJobDialogState();
}

class _ApplyJobDialogState extends State<_ApplyJobDialog>
    with TickerProviderStateMixin {
  bool _agreed = false;
  bool _submitting = false;
  bool _success = false;
  String? _error;
  bool _legalExpanded = false;
  late final AnimationController _intro;
  late final AnimationController _successReveal;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _successReveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _intro.forward();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _successReveal.dispose();
    super.dispose();
  }

  Widget _applyModalChrome({required Widget child}) {
    return Material(
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFF1F2F5),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: child,
        ),
      ),
    );
  }

  Animation<double> _badgeEntrance(int index) => CurvedAnimation(
        parent: _intro,
        curve: Interval(
          0.18 + index * 0.1,
          0.92,
          curve: Curves.easeOutCubic,
        ),
      );

  Widget _animatedBadge(int index, Widget child) {
    final a = _badgeEntrance(index);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).animate(a),
        child: child,
      ),
    );
  }

  Widget _hairline() => Divider(
        height: 1,
        thickness: 1,
        color: _hairlineDivider(),
      );

  Future<void> _runSubmit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit();
      if (mounted) {
        setState(() => _success = true);
        _successReveal.forward(from: 0);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    if (_success) {
      final okCurved = CurvedAnimation(
        parent: _successReveal,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: okCurved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(okCurved),
          child: _applyModalChrome(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 3.5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF6EE7B7)),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF047857),
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Application sent',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your application was submitted to the employer. They will review it and may contact you.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _ScaleOnPress(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context)
                            .pop(WorkerApplyDialogResult.completedBrowseJobs),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF6D28D9),
                                Color(0xFF7C3AED),
                                Color(0xFFA78BFA),
                              ],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: Text(
                                'View applications',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ScaleOnPress(
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .pop(WorkerApplyDialogResult.completedStay),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF374151),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Done',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final curved = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    final fade = Tween<double>(begin: 0, end: 1).animate(curved);
    final slide =
        Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(curved);

    return _applyModalChrome(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 3.5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Apply to this job?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
              child: FadeTransition(
                opacity: fade,
                child: SlideTransition(
                  position: slide,
                  child: Stack(
                    children: [
                      Scrollbar(
                        thickness: 3,
                        radius: const Radius.circular(8),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 22, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F2F5),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFFE1E4EA),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.055),
                                      blurRadius: 28,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.title,
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            s.businessName,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF6B7280),
                                            ),
                                          ),
                                        ),
                                        if (s.employerVerified) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD1FAE5),
                                              borderRadius: BorderRadius.circular(999),
                                              border: Border.all(
                                                color: const Color(0xFF6EE7B7),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF059669)
                                                      .withValues(alpha: 0.12),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.verified_rounded,
                                                  size: 16,
                                                  color: Color(0xFF059669),
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  'Verified employer',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w900,
                                                    color: Color(0xFF047857),
                                                    letterSpacing: 0.15,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    _snapRow(Icons.payments_outlined, s.payLine),
                                    const SizedBox(height: 6),
                                    _snapRow(Icons.schedule, s.durationLine),
                                    const SizedBox(height: 6),
                                    _snapRow(Icons.event_note_outlined, s.scheduleLine),
                                    const SizedBox(height: 6),
                                    _snapRow(Icons.place_outlined, s.locationLine),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              _hairline(),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _animatedBadge(
                                    0,
                                    const _TrustChip(
                                      icon: Icons.lock_rounded,
                                      label: 'Secure application',
                                    ),
                                  ),
                                  _animatedBadge(
                                    1,
                                    const _TrustChip(
                                      icon: Icons.verified_user_outlined,
                                      label: 'Data protected',
                                    ),
                                  ),
                                  _animatedBadge(
                                    2,
                                    const _TrustChip(
                                      icon: Icons.handshake_outlined,
                                      label: 'Fair hiring',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _hairline(),
                              const SizedBox(height: 8),
                              Text(
                                'By applying, your profile is shared with this employer.',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.45,
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _ScaleOnPress(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE4E8EF),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFC5CDD8),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.07),
                                        blurRadius: 14,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Theme(
                                      data: Theme.of(context).copyWith(
                                        dividerColor: Colors.transparent,
                                        splashColor: _purple.withValues(alpha: 0.12),
                                        highlightColor:
                                            _purple.withValues(alpha: 0.06),
                                      ),
                                      child: ExpansionTile(
                                        shape: const Border(),
                                        collapsedShape: const Border(),
                                        controlAffinity:
                                            ListTileControlAffinity.trailing,
                                        tilePadding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 2,
                                        ),
                                        childrenPadding: const EdgeInsets.fromLTRB(
                                          14,
                                          0,
                                          14,
                                          12,
                                        ),
                                        iconColor: _purple,
                                        collapsedIconColor: _purple,
                                        onExpansionChanged: (open) {
                                          setState(() => _legalExpanded = open);
                                        },
                                        trailing: AnimatedRotation(
                                          duration: const Duration(milliseconds: 200),
                                          curve: Curves.easeOutCubic,
                                          turns: _legalExpanded ? 0.5 : 0,
                                          child: Icon(
                                            Icons.expand_more_rounded,
                                            color: _purple,
                                            size: 26,
                                          ),
                                        ),
                                        title: Text(
                                          'Privacy & terms',
                                          style: GoogleFonts.inter(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFF111827),
                                          ),
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Optional — expand for highlights & full documents',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF64748B),
                                            ),
                                          ),
                                        ),
                                        children: [
                                    Text(
                                      'AgapShift collects and processes your data to verify accounts and connect you with employers.',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        height: 1.5,
                                        color: const Color(0xFF6B7280),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    _SoftPolicyLink(
                                      label: 'View full privacy policy (web)',
                                      icon: Icons.open_in_new_rounded,
                                      onTap: () => _openPolicyUrl(
                                        context,
                                        Uri.parse(_kPrivacyPolicyUrl),
                                      ),
                                    ),
                                    _SoftPolicyLink(
                                      label: 'Read privacy policy in app',
                                      icon: Icons.article_outlined,
                                      onTap: () => _showFullLegalSheet(
                                        context,
                                        title: 'Privacy policy (full text)',
                                        body: _kFullPrivacyBody,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Terms highlights',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF111827),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _bullet('Honest communication with the employer.'),
                                    _bullet('Attendance responsibility if you are hired.'),
                                    _bullet('Employment is not guaranteed by applying.'),
                                    const SizedBox(height: 8),
                                    _SoftPolicyLink(
                                      label: 'View terms & conditions (web)',
                                      icon: Icons.open_in_new_rounded,
                                      onTap: () => _openPolicyUrl(
                                        context,
                                        Uri.parse(_kTermsUrl),
                                      ),
                                    ),
                                    _SoftPolicyLink(
                                      label: 'Read terms in app',
                                      icon: Icons.article_outlined,
                                      onTap: () => _showFullLegalSheet(
                                        context,
                                        title: 'Terms & conditions (full text)',
                                        body: _kFullTermsBody,
                                      ),
                                    ),
                                  ],
                                ),
                                      ),
                                    ),
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFFECACA)),
                                  ),
                                  child: Text(
                                    _error!,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFB91C1C),
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 8,
                        top: 0,
                        height: 20,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.98),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 8,
                        bottom: 0,
                        height: 22,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.96),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.white,
              elevation: 10,
              shadowColor: Colors.black12,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  10 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _hairline(),
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _agreed
                              ? _purple.withValues(alpha: 0.45)
                              : const Color(0xFFE5E7EB),
                          width: _agreed ? 1.5 : 1,
                        ),
                        boxShadow: _agreed
                            ? [
                                BoxShadow(
                                  color: _purple.withValues(alpha: 0.22),
                                  blurRadius: 14,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : const [],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Align(
                            alignment: const Alignment(0, -0.08),
                            child: Transform.scale(
                              scale: _agreed ? 1.04 : 1.0,
                              child: Checkbox(
                                value: _agreed,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                fillColor:
                                    WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.selected)) {
                                    return _purple;
                                  }
                                  return null;
                                }),
                                checkColor: Colors.white,
                                side: BorderSide(
                                  color: _agreed
                                      ? _purple.withValues(alpha: 0.55)
                                      : const Color(0xFF9CA3AF),
                                  width: 1.5,
                                ),
                                onChanged: _submitting
                                    ? null
                                    : (v) =>
                                        setState(() => _agreed = v ?? false),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: GestureDetector(
                              onTap: _submitting
                                  ? null
                                  : () => setState(() => _agreed = !_agreed),
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                'I agree to the Privacy Policy and Terms.',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                  color: const Color(0xFF374151),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _ScaleOnPress(
                            child: Material(
                              color: Colors.white,
                              elevation: 0,
                              borderRadius: BorderRadius.circular(14),
                              child: OutlinedButton(
                                onPressed: _submitting
                                    ? null
                                    : () => Navigator.of(context).pop(
                                          WorkerApplyDialogResult.cancelled,
                                        ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF6B7280),
                                  side: const BorderSide(
                                    color: Color(0xFFE5E7EB),
                                  ),
                                  backgroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: _ScaleOnPress(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF6D28D9),
                                    Color(0xFF7C3AED),
                                    Color(0xFFA78BFA),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _purple.withValues(alpha: 0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                elevation: (_agreed && !_submitting) ? 2 : 0,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: (!_agreed || _submitting)
                                      ? null
                                      : _runSubmit,
                                  child: Opacity(
                                    opacity: (_agreed && !_submitting)
                                        ? 1.0
                                        : 0.62,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      child: Center(
                                        child: _submitting
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    'Applying…',
                                                    style: GoogleFonts.inter(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Text(
                                                'Apply',
                                                style: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15,
                                                  color: Colors.white,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Your profile is shared with the employer. You can withdraw while pending.',
                          textAlign: TextAlign.start,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _snapRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: const Color(0xFF374151),
            ),
          ),
        ),
      ],
    );
  }

  static Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF9CA3AF),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.45,
                color: const Color(0xFF6B7280),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE8EAED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF6B7280)),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF4B5563),
            ),
          ),
        ],
      ),
    );
  }
}

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
  bool _employerVerified = false;
  /// Full sentence for the Location card (profile municipality preferred over GPS).
  String? _locationDistanceLine;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _fetchWorkerMunicipality(String workerId) async {
    if (!SupabaseConfig.isConfigured || workerId.isEmpty) return null;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('identity_snapshot')
          .eq('id', workerId)
          .maybeSingle();
      return workerMunicipalityFromIdentitySnapshot(row?['identity_snapshot']);
    } catch (_) {
      return null;
    }
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

  Future<bool> _fetchEmployerVerified(String businessId) async {
    if (!SupabaseConfig.isConfigured || businessId.isEmpty) return false;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('account_status')
          .eq('id', businessId)
          .maybeSingle();
      return (row?['account_status'] as String?) == AccountStatus.verified.name;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _locationDistanceLine = null;
      _myApplication = null;
    });
    try {
      final gig = await widget.repo.getGig(widget.gigId);
      String? bizName;
      String? distanceLine;
      GigApplication? mine;
      var employerVerified = false;
      if (gig != null) {
        bizName = await _fetchBusinessName(gig.businessId);
        employerVerified = await _fetchEmployerVerified(gig.businessId);
        final workerId = appActorId(widget.session, mockFallback: 'worker');
        final muni = await _fetchWorkerMunicipality(workerId);
        final homePt = DavaoDelSur.approxCenterForMunicipality(muni);
        if (homePt != null && muni != null) {
          final km = geoDistanceMeters(homePt, gig.location) / 1000.0;
          distanceLine =
              'About ${km.toStringAsFixed(1)} km from $muni (your profile area)';
        } else {
          final userPt = await tryGetCurrentUserGeoPoint();
          if (userPt != null) {
            final km = geoDistanceMeters(userPt, gig.location) / 1000.0;
            distanceLine =
                'About ${km.toStringAsFixed(1)} km from your current location';
          }
        }
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
          _employerVerified = gig != null ? employerVerified : false;
          _locationDistanceLine = distanceLine;
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
      applyingToGigId: widget.gigId,
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
    final gig = _gig;
    if (gig == null) return;

    final business = (_businessName ?? 'Business').trim();
    final minutes = gig.endAt.difference(gig.startAt).inMinutes.clamp(1, 24 * 60);
    final hours = minutes / 60.0;
    final durationLabel =
        hours >= 1 ? '${hours.round()} hrs' : '$minutes min';
    final payPrimary = _payLabel(gig, hours);
    final loc = gig.addressLabel.trim();
    final snapshot = WorkerApplyJobSnapshot(
      title: gig.title,
      businessName: business.isNotEmpty ? business : 'Business',
      payLine: payPrimary,
      durationLine: durationLabel,
      scheduleLine: _formatApplyScheduleLine(gig),
      locationLine: loc.isNotEmpty ? loc : 'Work site on map',
      employerVerified: _employerVerified,
    );

    final result = await showWorkerApplyConfirmationDialog(
      context,
      snapshot: snapshot,
      onSubmit: () async {
        try {
          final submitted = await widget.repo.applyToGig(
            gigId: widget.gigId,
            workerId: workerId,
          );
          final g2 = await widget.repo.getGig(widget.gigId);
          if (g2 != null) {
            final resolved =
                (await fetchWorkerDisplayNamesById({workerId}))[workerId]?.trim();
            final workerName = (resolved != null && resolved.isNotEmpty)
                ? resolved
                : applicantDisplayNameFallback(workerId);
            await widget.notifications.add(
              userId: g2.businessId,
              title: 'New applicant',
              body: '$workerName applied to: ${g2.title}',
              data: {'gigId': g2.id},
            );
            await widget.notifications.add(
              userId: workerId,
              title: 'Application sent',
              body: 'You applied to: ${g2.title}',
              data: {'gigId': g2.id},
            );
          }
          if (!mounted) return;
          setState(() => _myApplication = submitted);
        } catch (e) {
          final msg = '$e';
          if (msg.contains('Already applied') && mounted) {
            await _load();
          }
          rethrow;
        }
      },
    );
    if (!mounted) return;
    if (result == WorkerApplyDialogResult.completedBrowseJobs) {
      Navigator.of(context).pop();
      return;
    }
    if (result == WorkerApplyDialogResult.cancelled) {
      return;
    }
    // completedStay: stay on screen; success already shown in dialog.
    return;
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
                      distanceLine: _locationDistanceLine,
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
    this.distanceLine,
  });

  final String address;
  final double lat;
  final double lng;
  final String? distanceLine;

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
          if (distanceLine != null) ...[
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
                    distanceLine!,
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
            child: SizedBox(
              height: 168,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(lat, lng),
                      initialZoom: 15.5,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'dev.agapshift.nexora',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(lat, lng),
                            width: 44,
                            height: 44,
                            alignment: Alignment.bottomCenter,
                            child: Icon(
                              Icons.location_on_rounded,
                              color: _purple,
                              size: 44,
                              shadows: const [
                                Shadow(
                                  color: Color(0x59000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text(
                          '© OpenStreetMap',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ),
                    ),
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
    final mq = MediaQuery.paddingOf(context);
    final bottom = mq.bottom;
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
        padding: EdgeInsets.fromLTRB(16, 12, 6 + mq.right, 12 + bottom),
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
            const SizedBox(width: 8),
            action,
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

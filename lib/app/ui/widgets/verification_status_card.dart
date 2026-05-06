import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../domain/enums.dart';
import '../../session/session_controller.dart';
import '../screens/status/verification_status_screen.dart';
import '../theme/agap_colors.dart';

/// Profile card that surfaces the user's verification state at a glance.
///
/// • Verified → green check pill with "Account Verified".
/// • Pending → yellow timeline (Created ✓ → Submitted ✓ → Review ⏳ → Verified ⬜)
///   no action required (admin review).
/// • Rejected → red copy + "Resubmit Documents" CTA.
class VerificationStatusCard extends StatelessWidget {
  const VerificationStatusCard({
    super.key,
    required this.session,
    this.profileCompletion = 0.8,
  });

  final SessionController session;
  final double profileCompletion;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final status = session.state.accountStatus ?? AccountStatus.pendingVerification;
        if (status == AccountStatus.verified) {
          return _VerifiedCard();
        }
        if (status == AccountStatus.suspended) {
          return _RejectedCard(
            session: session,
            title: 'Account suspended',
            body:
                'Your account is currently suspended. Contact support if you believe this is a mistake.',
            ctaLabel: 'Contact Support',
            status: status,
          );
        }
        if (status == AccountStatus.rejected) {
          return _RejectedCard(
            session: session,
            title: 'Verification rejected',
            body:
                'We found an issue with the documents you submitted. Please review and resubmit them.',
            ctaLabel: 'Resubmit Documents',
            status: status,
          );
        }
        return _PendingCard(session: session, profileCompletion: profileCompletion);
      },
    );
  }
}

class _VerifiedCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF10B981);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: green.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.verified_rounded, color: green, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Verified',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF065F46)),
                ),
                const SizedBox(height: 2),
                Text(
                  'You have full access to AgapShift features.',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF047857)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.session, required this.profileCompletion});

  final SessionController session;
  final double profileCompletion;

  @override
  Widget build(BuildContext context) {
    final accent = AgapColors.brandBoltYellow;
    final pct = (profileCompletion.clamp(0, 1) * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.30), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.access_time_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account Under Review',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'We typically review accounts within 24–48 hours.',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Mini progress meter.
          Row(
            children: [
              Text(
                'Profile completion',
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF334155)),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w900, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: profileCompletion.clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 14),
          // Vertical timeline.
          const _TimelineItem(label: 'Account Created', state: _Step.done),
          const _TimelineItem(label: 'Documents Submitted', state: _Step.done),
          const _TimelineItem(label: 'Admin Review', state: _Step.inProgress),
          const _TimelineItem(label: 'Account Verified', state: _Step.pending, isLast: true),
        ],
      ),
    );
  }
}

class _RejectedCard extends StatelessWidget {
  const _RejectedCard({
    required this.session,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.status,
  });

  final SessionController session;
  final String title;
  final String body;
  final String ctaLabel;
  final AccountStatus status;

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: red.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.error_outline_rounded, color: red, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF7F1D1D)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF991B1B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VerificationStatusScreen(
                      status: status,
                      onReset: session.resetAll,
                    ),
                  ),
                );
              },
              child: Text(ctaLabel, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Step { done, inProgress, pending }

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.label, required this.state, this.isLast = false});

  final String label;
  final _Step state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _Step.done => const Color(0xFF10B981),
      _Step.inProgress => AgapColors.brandBoltYellow,
      _Step.pending => const Color(0xFFCBD5E1),
    };
    final iconWidget = switch (state) {
      _Step.done => const Icon(Icons.check_rounded, color: Colors.white, size: 14),
      _Step.inProgress => const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 13),
      _Step.pending => const SizedBox.shrink(),
    };
    final labelColor = switch (state) {
      _Step.done => const Color(0xFF065F46),
      _Step.inProgress => const Color(0xFF92400E),
      _Step.pending => const Color(0xFF94A3B8),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Center(child: iconWidget),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: const Color(0xFFE2E8F0),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Padding(
            padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: state == _Step.pending ? FontWeight.w700 : FontWeight.w900,
                    color: labelColor,
                  ),
                ),
                if (state == _Step.inProgress)
                  Text(
                    'In progress',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AgapColors.brandBoltYellow),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

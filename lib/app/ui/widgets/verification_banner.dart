import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../domain/enums.dart';
import '../../session/session_controller.dart';
import '../screens/status/verification_status_screen.dart';
import '../theme/agap_colors.dart';

/// Shows a one-shot review/verification dialog the first time the dashboard
/// mounts for an unverified user. Returns immediately without showing
/// anything if the account is already verified or suspended.
///
/// The dialog has a close button so the user can dismiss it; it won't
/// re-appear until the dashboard is rebuilt from scratch (callers gate this
/// with their own `_shown` flag in state).
Future<void> showVerificationReviewDialog(
  BuildContext context, {
  required SessionController session,
  double profileCompletion = 0.8,
}) async {
  final status = session.state.accountStatus;
  if (status == null || status == AccountStatus.verified || status == AccountStatus.suspended) {
    return;
  }

  final isRejected = status == AccountStatus.rejected;
  final accent = isRejected ? const Color(0xFFEF4444) : AgapColors.brandBoltYellow;
  final tint = isRejected ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7);
  final iconBg = isRejected
      ? const Color(0xFFFCA5A5).withValues(alpha: 0.55)
      : AgapColors.brandBoltYellow.withValues(alpha: 0.30);
  final icon = isRejected ? Icons.error_outline_rounded : Icons.access_time_rounded;
  final title = isRejected ? 'Verification needs your attention' : 'Your account is under review';
  final body = isRejected
      ? 'We found an issue with your documents. Please update them and resubmit.'
      : 'Your submission is being reviewed by our admin team. You’ll be notified once approved.';
  final pct = (profileCompletion.clamp(0, 1) * 100).round();

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Profile completion',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF334155),
                  ),
                ),
                const Spacer(),
                Text(
                  '$pct%',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
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
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.06),
                      foregroundColor: const Color(0xFF475569),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Close',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                if (isRejected) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => VerificationStatusScreen(
                              status: status,
                              onReset: session.resetAll,
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'Resubmit Documents',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900),
                      ),
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

Future<void> showVerifiedCongratsDialog(
  BuildContext context, {
  required SessionController session,
}) async {
  final status = session.state.accountStatus;
  if (status != AccountStatus.verified) return;
  if (await session.hasShownVerifiedCongrats()) return;
  await session.markVerifiedCongratsShown();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    color: AgapColors.brandWordmarkBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Congratulations!',
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your account is now verified. You have full access to AgapShift.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Verified privileges',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E3A8A),
              ),
            ),
            const SizedBox(height: 8),
            _VerifiedPrivilegeRow(
              icon: Icons.work_outline_rounded,
              text: 'Apply for jobs and get hired faster with a verified badge.',
            ),
            const SizedBox(height: 8),
            _VerifiedPrivilegeRow(
              icon: Icons.qr_code_2_rounded,
              text: 'Clock in/out with QR attendance tracking (visible to you and employers).',
            ),
            const SizedBox(height: 8),
            _VerifiedPrivilegeRow(
              icon: Icons.workspace_premium_outlined,
              text: 'Access subscription options for multiple or continuous shifts.',
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AgapColors.brandWordmarkBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Continue',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _VerifiedPrivilegeRow extends StatelessWidget {
  const _VerifiedPrivilegeRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AgapColors.brandWordmarkBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: const Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }
}

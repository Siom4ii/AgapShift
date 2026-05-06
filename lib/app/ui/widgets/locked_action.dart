import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../domain/enums.dart';
import '../../session/session_controller.dart';
import '../screens/status/verification_status_screen.dart';
import '../theme/agap_colors.dart';

/// Returns true when the active session is allowed to perform write/critical
/// actions (i.e. fully verified). Use this from buttons to decide whether to
/// gate a tap with [showLockedFeatureDialog].
bool canPerformVerifiedAction(SessionController session) {
  return session.state.accountStatus == AccountStatus.verified;
}

/// Surface a friendly dialog when an unverified user taps a restricted
/// feature. Directs users to wait for admin review.
Future<void> showLockedFeatureDialog(
  BuildContext context, {
  required SessionController session,
  String? featureName,
}) {
  final status = session.state.accountStatus ?? AccountStatus.pendingVerification;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AgapColors.brandBoltYellow.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.lock_outline_rounded,
                color: AgapColors.brandBoltYellow.withValues(alpha: 0.95), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              featureName == null ? 'Verification required' : '$featureName locked',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Text(
        'This feature is available after account verification. Your documents are reviewed by our admin team.',
        style: GoogleFonts.inter(
          fontSize: 13.5,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF475569),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Got it',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: const Color(0xFF64748B)),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AgapColors.brandWordmarkBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
            'View status',
            style: GoogleFonts.inter(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );
}

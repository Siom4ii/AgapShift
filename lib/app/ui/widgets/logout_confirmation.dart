import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/agap_colors.dart';

/// Shows a confirmation dialog. Returns `true` if the user confirms logout.
Future<bool> confirmLogout(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Log out?',
        style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: Text(
        'You will need to sign in again to use AgapShift.',
        style: GoogleFonts.inter(
          fontSize: 14,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF475569),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Cancel',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: AgapColors.textMuted,
            ),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB91C1C),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Log out',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

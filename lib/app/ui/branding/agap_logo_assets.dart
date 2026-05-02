import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/agap_colors.dart';

abstract final class AgapLogoAssets {
  // User-provided logos in `branding/`.
  static const String lockup = 'branding/logo1.png'; // full lockup
  static const String wordmark = 'branding/logo2.png'; // "AgapShift" wordmark
  static const String mark = 'branding/logo3.png'; // icon-only mark
}

/// Wordmark as vector text (matches brand colors). No [ClipRRect] — avoids a
/// visible “rounded” clip on italic glyphs.
class AgapLogoWordmarkChip extends StatelessWidget {
  const AgapLogoWordmarkChip({super.key, this.height = 22});

  final double height;

  @override
  Widget build(BuildContext context) {
    final fs = height * 0.92;
    return Text.rich(
      TextSpan(
        style: GoogleFonts.inter(
          fontSize: fs,
          fontWeight: FontWeight.w800,
          fontStyle: FontStyle.italic,
          letterSpacing: -0.35,
          height: 1.05,
        ),
        children: const [
          TextSpan(
            text: 'Agap',
            style: TextStyle(color: AgapColors.brandWordmarkBlue),
          ),
          TextSpan(
            text: 'Shift',
            style: TextStyle(color: AgapColors.brandWordmarkGreen),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Official logo mark (from [AgapLogoAssets.lockup]).
class AgapLogoMarkTile extends StatelessWidget {
  const AgapLogoMarkTile({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      // `logo3.png` includes large transparent padding. We crop that padding in
      // layout (no new asset needed), so the mark renders visually larger.
      child: ClipRect(
        child: Align(
          alignment: Alignment.center,
          widthFactor: 0.62,
          heightFactor: 0.62,
          child: Image.asset(
            AgapLogoAssets.mark,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

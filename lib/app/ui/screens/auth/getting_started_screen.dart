import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../branding/agap_logo_assets.dart';
import '../../theme/agap_colors.dart';

class GettingStartedScreen extends StatelessWidget {
  const GettingStartedScreen({super.key, required this.onGetStarted});

  final Future<void> Function() onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _BrandGradientBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                children: [
                  const Spacer(),
                  Center(child: AgapLogoMarkTile(size: 240))
                      .animate()
                      .fadeIn(duration: 420.ms)
                      .scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1), curve: Curves.easeOutBack),
                  const SizedBox(height: 1),
                  Text(
                    'AgapShift',
                    style: GoogleFonts.inter(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.1,
                      height: 1.05,
                      color: Colors.white,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 100.ms, duration: 420.ms)
                      .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
                  const SizedBox(height: 8),
                  Text(
                    'Your trusted gig work marketplace',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ).animate().fadeIn(delay: 160.ms, duration: 420.ms),
                  const SizedBox(height: 24),
                  const _FeaturePill(
                    icon: Icons.bolt_rounded,
                    label: 'Instant hiring & job matching',
                    iconColor: AgapColors.brandBoltYellow,
                  ).animate().fadeIn(delay: 220.ms, duration: 380.ms).slideY(begin: 0.08, end: 0),
                  const SizedBox(height: 12),
                  const _FeaturePill(
                    icon: Icons.place_rounded,
                    label: 'Location-based nearby gigs',
                    iconColor: Color(0xFF93C5FD),
                  ).animate().fadeIn(delay: 280.ms, duration: 380.ms).slideY(begin: 0.08, end: 0),
                  const SizedBox(height: 12),
                  const _FeaturePill(
                    icon: Icons.verified_user_rounded,
                    label: 'Verified workers & businesses',
                    iconColor: Color(0xFF86EFAC),
                  ).animate().fadeIn(delay: 340.ms, duration: 380.ms).slideY(begin: 0.08, end: 0),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AgapColors.brandWordmarkBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      onPressed: () async => onGetStarted(),
                      child: Text(
                        'Get Started',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ).animate().fadeIn(delay: 420.ms, duration: 420.ms).slideY(begin: 0.12, end: 0),
                  const SizedBox(height: 12),
                  Text.rich(
                    TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                      children: const [
                        TextSpan(text: 'By continuing, you agree to our '),
                        TextSpan(text: 'Terms', style: TextStyle(decoration: TextDecoration.underline)),
                        TextSpan(text: ' & '),
                        TextSpan(text: 'Privacy Policy', style: TextStyle(decoration: TextDecoration.underline)),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 520.ms, duration: 350.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandGradientBackground extends StatelessWidget {
  const _BrandGradientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AgapColors.brandWordmarkBlue,
                Color.lerp(AgapColors.brandWordmarkBlue, AgapColors.primaryBright, 0.55)!,
                AgapColors.primaryBright,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -70,
          child: _orb(240, Colors.white.withValues(alpha: 0.10)),
        ),
        Positioned(
          top: 140,
          right: -20,
          child: _orb(200, Colors.white.withValues(alpha: 0.08)),
        ),
        Positioned(
          bottom: 120,
          left: -90,
          child: _orb(260, AgapColors.brandWordmarkGreen.withValues(alpha: 0.12)),
        ),
        Positioned(
          bottom: -90,
          right: -70,
          child: _orb(240, Colors.white.withValues(alpha: 0.07)),
        ),
      ],
    );
  }

  static Widget _orb(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.95),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

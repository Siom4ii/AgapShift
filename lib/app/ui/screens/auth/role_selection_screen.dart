import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../theme/agap_colors.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({
    super.key,
    required this.onSelectRole,
    required this.onBack,
  });

  final Future<void> Function(UserRole role) onSelectRole;

  /// Invoked when the user taps the in-header back button (or triggers the
  /// Android system back gesture). The screen is mounted directly by
  /// `SessionGate`, so simply calling `Navigator.maybePop` here would be a
  /// silent no-op — the parent must transition the auth stage instead.
  final Future<void> Function() onBack;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  UserRole? _selected;
  bool _submitting = false;

  static const _workerAccent = AgapColors.brandWordmarkBlue;
  static const _businessAccent = AgapColors.brandWordmarkGreen;

  Color get _accent =>
      _selected == UserRole.business ? _businessAccent : _workerAccent;

  Future<void> _continue() async {
    final role = _selected;
    if (role == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSelectRole(role);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _submitting) return;
        widget.onBack();
      },
      child: Scaffold(
        backgroundColor: AgapColors.pageBackground,
        body: Column(
          children: [
            _Header(onBack: () => widget.onBack()),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  children: [
                    _RoleCard(
                          selected: _selected == UserRole.worker,
                          accent: _workerAccent,
                          title: 'I Want to Work',
                          subtitle:
                              'Find flexible gig work near you. Earn\nmoney by completing shifts for nearby\nbusinesses.',
                          icon: Icons.engineering_rounded,
                          chips: const [
                            'Find nearby jobs',
                            'Flexible schedule',
                            'Get paid fast',
                          ],
                          onTap: () =>
                              setState(() => _selected = UserRole.worker),
                        )
                        .animate()
                        .fadeIn(duration: 220.ms)
                        .slideY(begin: 0.04, end: 0),
                    const SizedBox(height: 14),
                    _RoleCard(
                          selected: _selected == UserRole.business,
                          accent: _businessAccent,
                          title: 'I Want to Hire',
                          subtitle:
                              'Post job requests and hire verified\nworkers instantly for your business\nneeds.',
                          icon: Icons.apartment_rounded,
                          chips: const [
                            'Post jobs instantly',
                            'Verified workers',
                            'Pay securely',
                          ],
                          onTap: () =>
                              setState(() => _selected = UserRole.business),
                        )
                        .animate()
                        .fadeIn(delay: 80.ms, duration: 220.ms)
                        .slideY(begin: 0.04, end: 0),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _selected == null
                              ? const Color(0xFFCBD5E1)
                              : _accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: _selected == null ? 0 : 10,
                          shadowColor: _accent.withValues(alpha: 0.28),
                        ),
                        onPressed: _selected == null ? null : _continue,
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Continue',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AgapColors.brandWordmarkBlue,
            Color.lerp(
              AgapColors.brandWordmarkBlue,
              AgapColors.primaryBright,
              0.55,
            )!,
            AgapColors.primaryBright,
          ],
          stops: const [0.0, 0.58, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Material(
              color: Colors.white.withValues(alpha: 0.18),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Choose Your Role',
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: -0.6,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'How would you like to use AgapShift?',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.86),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.selected,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.chips,
    required this.onTap,
  });

  final bool selected;
  final Color accent;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> chips;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected ? accent : const Color(0xFFE5E7EB);
    final bg = selected ? accent.withValues(alpha: 0.06) : Colors.white;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border, width: selected ? 1.6 : 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: 0.10)
                        : const Color(0xFFF2F4F7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: accent, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 13.2,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final c in chips)
                            _Chip(label: c, accent: accent, selected: selected),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? accent.withValues(alpha: 0.10)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected ? accent : const Color(0xFFCBD5E1),
                      width: 1.4,
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check_rounded, size: 18, color: accent)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.accent,
    required this.selected,
  });

  final String label;
  final Color accent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? accent.withValues(alpha: 0.10)
        : const Color(0xFFF1F5F9);
    final fg = selected ? accent : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_rounded,
            size: 14,
            color: selected ? AgapColors.brandBoltYellow : fg,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

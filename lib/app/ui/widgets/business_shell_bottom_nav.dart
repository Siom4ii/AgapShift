import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/agap_colors.dart';

/// Bottom navigation for the business dashboard: Home, Workers, center Post Job,
/// Wallet, Profile. [contentIndex] is 0–3 (FAB does not change selection).
class BusinessShellBottomNav extends StatelessWidget {
  const BusinessShellBottomNav({
    super.key,
    required this.contentIndex,
    required this.onContentIndex,
    required this.onPostJob,
  });

  /// 0 Home, 1 Workers, 2 Wallet, 3 Profile
  final int contentIndex;
  final ValueChanged<int> onContentIndex;
  final VoidCallback onPostJob;

  static const double _fabSize = 52;

  /// Tall enough for icon+label row plus FAB column without RenderFlex overflow.
  /// Use with [MediaQuery.padding.bottom] to inset overlays (e.g. modals) above this bar.
  static const double barHeight = 88;

  void _onTap(int slot) {
    if (slot == 2) {
      onPostJob();
      return;
    }
    final idx = slot < 2 ? slot : slot - 1;
    onContentIndex(idx);
  }

  bool _selected(int slot) {
    if (slot == 2) return false;
    final mapped =
        contentIndex < 2 ? contentIndex : contentIndex + 1;
    return mapped == slot;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _NavCell(
                        selected: _selected(0),
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        label: 'Home',
                        onTap: () => _onTap(0),
                      ),
                    ),
                    Expanded(
                      child: _NavCell(
                        selected: _selected(1),
                        icon: Icons.people_outline_rounded,
                        selectedIcon: Icons.people_rounded,
                        label: 'Workers',
                        onTap: () => _onTap(1),
                      ),
                    ),
                    SizedBox(width: _fabSize + 6),
                    Expanded(
                      child: _NavCell(
                        selected: _selected(3),
                        icon: Icons.account_balance_wallet_outlined,
                        selectedIcon: Icons.account_balance_wallet_rounded,
                        label: 'Wallet',
                        onTap: () => _onTap(3),
                      ),
                    ),
                    Expanded(
                      child: _NavCell(
                        selected: _selected(4),
                        icon: Icons.business_outlined,
                        selectedIcon: Icons.business_rounded,
                        label: 'Profile',
                        onTap: () => _onTap(4),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CenterPostJobFab(
                        size: _fabSize,
                        onTap: onPostJob,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Post Job',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          color: AgapColors.businessGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterPostJobFab extends StatefulWidget {
  const _CenterPostJobFab({
    required this.size,
    required this.onTap,
  });

  final double size;
  final VoidCallback onTap;

  @override
  State<_CenterPostJobFab> createState() => _CenterPostJobFabState();
}

class _CenterPostJobFabState extends State<_CenterPostJobFab> {
  bool _pressed = false;
  bool _hover = false;

  double get _scale {
    if (_pressed) return 0.92;
    if (_hover) return 1.06;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Material(
            color: AgapColors.businessGreen,
            elevation: 4,
            shadowColor: AgapColors.businessGreenDeep.withValues(alpha: 0.35),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              splashColor: Colors.white.withValues(alpha: 0.28),
              highlightColor: Colors.white.withValues(alpha: 0.14),
              hoverColor: Colors.white.withValues(alpha: 0.1),
              onTap: widget.onTap,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  static const Duration _anim = Duration(milliseconds: 320);

  @override
  Widget build(BuildContext context) {
    final accent = AgapColors.businessGreen;
    final color = selected ? accent : AgapColors.textMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: accent.withValues(alpha: 0.16),
        highlightColor: accent.withValues(alpha: 0.09),
        hoverColor: accent.withValues(alpha: 0.07),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: _anim,
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? AgapColors.businessMint : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: AnimatedScale(
                  scale: selected ? 1.06 : 1.0,
                  duration: _anim,
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.92, end: 1).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: Icon(
                      key: ValueKey<bool>(selected),
                      selected ? selectedIcon : icon,
                      size: 22,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: _anim,
                curve: Curves.easeOutCubic,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  height: 1.05,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

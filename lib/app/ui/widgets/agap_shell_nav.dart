import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/agap_colors.dart';

class AgapShellDestination {
  const AgapShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

enum AgapShellNavVariant {
  /// Rounded pill behind icon + brand green accent (default).
  standard,

  /// Circular light-blue highlight + blue icon/label (worker dashboard mock).
  worker,
}

class AgapShellNavBar extends StatelessWidget {
  const AgapShellNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.destinations,
    this.variant = AgapShellNavVariant.standard,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<AgapShellDestination> destinations;
  final AgapShellNavVariant variant;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _NavCell(
                    selected: i == selectedIndex,
                    icon: destinations[i].icon,
                    selectedIcon: destinations[i].selectedIcon,
                    label: destinations[i].label,
                    variant: variant,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
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
    required this.variant,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final AgapShellNavVariant variant;
  final VoidCallback onTap;

  static const Duration _anim = Duration(milliseconds: 320);

  @override
  Widget build(BuildContext context) {
    final worker = variant == AgapShellNavVariant.worker;
    final accent =
        worker ? const Color(0xFF2563EB) : AgapColors.primaryBright;
    final color = selected ? accent : AgapColors.textMuted;
    final selectedBg =
        worker ? const Color(0xFFDBEAFE) : AgapColors.mintSurface;

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
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: _anim,
                curve: Curves.easeOutCubic,
                width: worker ? 48 : null,
                height: worker ? 48 : null,
                padding: worker
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? selectedBg : Colors.transparent,
                  shape: worker ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: worker ? null : BorderRadius.circular(14),
                ),
                child: AnimatedScale(
                  scale: selected ? 1.04 : 1.0,
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
                      size: worker ? 24 : 22,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: _anim,
                curve: Curves.easeOutCubic,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

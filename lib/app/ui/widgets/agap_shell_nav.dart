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

class _NavCell extends StatefulWidget {
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

  @override
  State<_NavCell> createState() => _NavCellState();
}

class _NavCellState extends State<_NavCell> with SingleTickerProviderStateMixin {
  static const Duration _anim = Duration(milliseconds: 320);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.selected) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _NavCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      _pulse
        ..reset()
        ..repeat(reverse: true);
    } else if (!widget.selected && oldWidget.selected) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final worker = widget.variant == AgapShellNavVariant.worker;
    final accent =
        worker ? const Color(0xFF2563EB) : AgapColors.primaryBright;
    final color = widget.selected ? accent : AgapColors.textMuted;
    final selectedBg =
        worker ? const Color(0xFFDBEAFE) : AgapColors.mintSurface;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final wPulse = widget.selected && worker ? _pulse.value : 0.0;
        final blurBoost = 10 + 10 * wPulse;
        final spreadBoost = 1.5 * wPulse;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
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
                      color: widget.selected ? selectedBg : Colors.transparent,
                      shape: worker ? BoxShape.circle : BoxShape.rectangle,
                      borderRadius: worker ? null : BorderRadius.circular(14),
                      boxShadow: worker && widget.selected
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.32 + 0.12 * wPulse),
                                blurRadius: blurBoost,
                                spreadRadius: spreadBoost,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: accent.withValues(alpha: 0.1 + 0.06 * wPulse),
                                blurRadius: 24,
                                spreadRadius: 1,
                                offset: Offset.zero,
                              ),
                            ]
                          : null,
                    ),
                    child: AnimatedScale(
                      scale: widget.selected ? 1.04 + 0.03 * wPulse : 1.0,
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
                          key: ValueKey<bool>(widget.selected),
                          widget.selected ? widget.selectedIcon : widget.icon,
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
                    child: Text(widget.label),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

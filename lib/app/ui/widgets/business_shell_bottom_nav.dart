import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/agap_colors.dart';

/// Bottom navigation for the business dashboard: Home, Workers, Profile.
class BusinessShellBottomNav extends StatelessWidget {
  const BusinessShellBottomNav({
    super.key,
    required this.contentIndex,
    required this.onContentIndex,
    required this.onPostJob,
  });

  /// 0 Home, 1 Listings, 2 Workers, 3 Profile
  final int contentIndex;
  final ValueChanged<int> onContentIndex;
  final VoidCallback onPostJob;

  /// Tall enough for icon+label row plus FAB column without RenderFlex overflow.
  /// Use with [MediaQuery.padding.bottom] to inset overlays (e.g. modals) above this bar.
  static const double barHeight = 74;

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _NavCell(
                    selected: contentIndex == 0,
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    label: 'Home',
                    onTap: () => onContentIndex(0),
                  ),
                ),
                Expanded(
                  child: _NavCell(
                    selected: contentIndex == 1,
                    icon: Icons.work_outline_rounded,
                    selectedIcon: Icons.work_rounded,
                    label: 'Listings',
                    onTap: () => onContentIndex(1),
                  ),
                ),
                Expanded(
                  child: _CenterPostJobButton(
                    onTap: onPostJob,
                  ),
                ),
                Expanded(
                  child: _NavCell(
                    selected: contentIndex == 2,
                    icon: Icons.people_outline_rounded,
                    selectedIcon: Icons.people_rounded,
                    label: 'Workers',
                    onTap: () => onContentIndex(2),
                  ),
                ),
                Expanded(
                  child: _NavCell(
                    selected: contentIndex == 3,
                    icon: Icons.business_outlined,
                    selectedIcon: Icons.business_rounded,
                    label: 'Profile',
                    onTap: () => onContentIndex(3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterPostJobButton extends StatelessWidget {
  const _CenterPostJobButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: SizedBox(
          width: 56,
          height: 56,
          child: FloatingActionButton(
            heroTag: 'business_post_job_fab',
            onPressed: onTap,
            backgroundColor: AgapColors.businessGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            child: const Icon(Icons.add_rounded, size: 30),
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

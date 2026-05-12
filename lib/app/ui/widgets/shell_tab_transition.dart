import 'package:flutter/material.dart';

/// Wraps shell tab bodies with a soft fade + slight slide when switching tabs.
class ShellTabTransition extends StatelessWidget {
  const ShellTabTransition({
    super.key,
    required this.tabIndex,
    required this.child,
  });

  final int tabIndex;
  final Widget child;

  static const Duration _duration = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.018),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(tabIndex),
        child: child,
      ),
    );
  }
}

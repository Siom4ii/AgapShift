import 'package:flutter/material.dart';

import '../theme/agap_colors.dart';

/// Subtle tinted gradient behind tab screens so flat grey fills feel less plain.
enum ShellChromeKind { business, worker }

class ShellChromeBackground extends StatelessWidget {
  const ShellChromeBackground({
    super.key,
    required this.kind,
    required this.child,
  });

  final ShellChromeKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = kind == ShellChromeKind.business
        ? [const Color(0xFFF2FBF6), AgapColors.pageBackground, Colors.white]
        : [
            const Color(0xFFEFF8F5),
            Color.lerp(
              AgapColors.mintSurface,
              AgapColors.pageBackground,
              0.35,
            )!,
            AgapColors.pageBackground,
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// One-shot fade + slide-up when the widget mounts (e.g. after a tab switch).
class ShellStaggerItem extends StatefulWidget {
  const ShellStaggerItem({
    super.key,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 400),
    this.staggerMs = 40,
    this.slidePx = 12,
  });

  final int index;
  final Widget child;
  final Duration duration;
  final int staggerMs;
  final double slidePx;

  @override
  State<ShellStaggerItem> createState() => _ShellStaggerItemState();
}

class _ShellStaggerItemState extends State<ShellStaggerItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _t = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    final delayMs = widget.index.clamp(0, 14) * widget.staggerMs;
    Future<void>.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        return Opacity(
          opacity: _t.value,
          child: Transform.translate(
            offset: Offset(0, widget.slidePx * (1 - _t.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Slight scale on pointer hover (desktop / web) for static cards and lists.
class ShellLift extends StatefulWidget {
  const ShellLift({
    super.key,
    required this.child,
    this.hoverScale = 1.012,
    this.duration = const Duration(milliseconds: 220),
  });

  final Widget child;
  final double hoverScale;
  final Duration duration;

  @override
  State<ShellLift> createState() => _ShellLiftState();
}

class _ShellLiftState extends State<ShellLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? widget.hoverScale : 1,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

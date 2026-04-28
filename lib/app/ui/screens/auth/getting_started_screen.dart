import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class GettingStartedScreen extends StatelessWidget {
  const GettingStartedScreen({super.key, required this.onGetStarted});

  final Future<void> Function() onGetStarted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.18),
                    theme.colorScheme.tertiary.withValues(alpha: 0.10),
                    theme.colorScheme.surface,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _BrandMark(color: theme.colorScheme.primary).animate().fadeIn(duration: 450.ms).scale(
                        begin: const Offset(0.96, 0.96),
                        end: const Offset(1, 1),
                        duration: 450.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: 16),
                  Text('AgapShift', style: theme.textTheme.displaySmall)
                      .animate()
                      .fadeIn(delay: 120.ms, duration: 450.ms)
                      .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
                  const SizedBox(height: 10),
                  Text(
                    'Instant, location-based gigs with verified users and secure payouts.',
                    style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ).animate().fadeIn(delay: 220.ms, duration: 450.ms).slideY(begin: 0.12, end: 0),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _Pill(icon: Icons.flash_on_rounded, text: 'Instant hiring'),
                      _Pill(icon: Icons.verified_rounded, text: 'Verified users'),
                      _Pill(icon: Icons.pin_drop_rounded, text: 'Nearby matching'),
                      _Pill(icon: Icons.lock_rounded, text: 'Secure transactions'),
                    ],
                  ).animate().fadeIn(delay: 320.ms, duration: 450.ms),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async => onGetStarted(),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Get Started'),
                    ).animate().fadeIn(delay: 420.ms, duration: 450.ms).slideY(begin: 0.25, end: 0),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'By continuing you agree to safe marketplace rules.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
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

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.7)],
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 30,
            spreadRadius: 2,
            offset: const Offset(0, 10),
            color: color.withValues(alpha: 0.25),
          ),
        ],
      ),
      child: const Icon(Icons.handshake_rounded, color: Colors.white, size: 30),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(text, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}


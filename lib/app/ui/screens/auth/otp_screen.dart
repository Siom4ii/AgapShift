import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/agap_colors.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.email,
    required this.onVerify,
    required this.onBack,
    required this.onResend,
  });

  final String email;
  final Future<bool> Function(String code) onVerify;
  final Future<void> Function() onBack;
  final Future<void> Function() onResend;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _code = '';
  bool _verifying = false;
  String? _error;

  static const _cooldownSec = 45;
  int _secondsLeft = _cooldownSec;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _cooldownSec);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  void _onDigit(String d) {
    if (_code.length >= 6) return;
    setState(() {
      _error = null;
      _code += d;
    });
  }

  void _onBackspace() {
    if (_code.isEmpty) return;
    setState(() {
      _error = null;
      _code = _code.substring(0, _code.length - 1);
    });
  }

  Future<void> _verify() async {
    if (_code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _error = null;
      _verifying = true;
    });
    final ok = await widget.onVerify(_code);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _verifying = false;
        _error = 'Invalid code. Try again.';
        _code = '';
      });
      return;
    }
    setState(() => _verifying = false);
  }

  String get _contactBold {
    final e = widget.email.trim();
    if (e.isEmpty) return 'your contact';
    if (e.contains('@')) return e;
    return _formatAsPhone(e);
  }

  String _formatAsPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      return '+${digits.substring(0, 1)} (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7)}';
    }
    return raw;
  }

  String get _timerLabel {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () async => widget.onBack(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F4FC),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AgapColors.primary.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.verified_user_rounded,
                        size: 44,
                        color: AgapColors.primary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Secure Verification',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text.rich(
                      TextSpan(
                        style: GoogleFonts.inter(fontSize: 15, height: 1.45, color: AgapColors.textMuted),
                        children: [
                          const TextSpan(text: 'Enter the 6-digit access code sent to '),
                          TextSpan(
                            text: _contactBold,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: GoogleFonts.inter(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (i) {
                        final char = i < _code.length ? _code[i] : '';
                        final active = i == _code.length && _code.length < 6;
                        return Padding(
                          padding: EdgeInsets.only(right: i < 5 ? 8 : 0),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 46,
                            height: 54,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: active ? AgapColors.primaryBright : AgapColors.borderSubtle,
                                width: active ? 2 : 1.2,
                              ),
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                        color: AgapColors.primary.withValues(alpha: 0.12),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: active && char.isEmpty
                                ? _BlinkCaret(color: AgapColors.primaryBright)
                                : Text(
                                    char,
                                    style: GoogleFonts.inter(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    Material(
                      color: const Color(0xFFE8F4FC),
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _secondsLeft == 0
                            ? () async {
                                await widget.onResend();
                                if (!mounted) return;
                                _startTimer();
                                setState(() => _code = '');
                              }
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 20,
                                color: _secondsLeft == 0 ? AgapColors.primaryBright : const Color(0xFF3B82F6),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _secondsLeft == 0
                                    ? 'Resend code'
                                    : 'Resend code in $_timerLabel',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: _secondsLeft == 0 ? AgapColors.primaryBright : const Color(0xFF1E40AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AgapColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _verifying ? null : _verify,
                        child: _verifying
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                'Verify Connection',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _NumericKeypad(
                onDigit: _onDigit,
                onBackspace: _onBackspace,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlinkCaret extends StatefulWidget {
  const _BlinkCaret({required this.color});

  final Color color;

  @override
  State<_BlinkCaret> createState() => _BlinkCaretState();
}

class _BlinkCaretState extends State<_BlinkCaret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 530))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return Opacity(
          opacity: _c.value > 0.5 ? 1 : 0.2,
          child: Container(
            width: 2,
            height: 22,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({
    required this.onDigit,
    required this.onBackspace,
  });

  final void Function(String) onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget digitKey(String d) {
      return Expanded(
        child: Material(
          color: AgapColors.pageBackground,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onDigit(d),
            child: SizedBox(
              height: 52,
              child: Center(
                child: Text(
                  d,
                  style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  digitKey(row[i]),
                ],
              ],
            ),
          ),
        Row(
          children: [
            const Expanded(child: SizedBox()),
            const SizedBox(width: 10),
            digitKey('0'),
            const SizedBox(width: 10),
            Expanded(
              child: Material(
                color: AgapColors.pageBackground,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onBackspace,
                  child: const SizedBox(
                    height: 52,
                    child: Center(
                      child: Icon(Icons.backspace_outlined, size: 22, color: Color(0xFF475569)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../session/session_models.dart';
import '../../theme/agap_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onTapSignUp,
  });

  /// Returns whether the email is registered. Caller persists state on
  /// success; on `notFound`, this screen surfaces an alert offering the user
  /// to continue to sign up.
  final Future<LoginResult> Function({required String email, required String password}) onLogin;

  /// Called when the user explicitly chooses "Sign Up" — either from the link
  /// at the bottom or via the no-account alert.
  final Future<void> Function() onTapSignUp;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _passwordVisible = false;
  bool _submitting = false;
  String? _emailError;
  String? _passwordError;

  late AnimationController _intro;
  late Animation<double> _heroFade;
  late Animation<double> _heroScale;
  late Animation<double> _copyFade;
  late Animation<double> _formFade;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _heroFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
    );
    _heroScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );
    _copyFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.12, 0.55, curve: Curves.easeOut),
    );
    _formFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.22, 1.0, curve: Curves.easeOutCubic),
    );
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final email = _email.text.trim();
    final password = _password.text;

    setState(() {
      _emailError = null;
      _passwordError = null;
    });

    if (!email.contains('@') || email.length < 4) {
      setState(() => _emailError = 'Enter a valid email or username.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _passwordError = 'Enter your password.');
      return;
    }

    setState(() => _submitting = true);
    final result = await widget.onLogin(email: email, password: password);
    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result) {
      case LoginResult.success:
        break;
      case LoginResult.staffUseWebAdmin:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            content: Text(
              'This is a staff admin account. Sign in on the Nexora admin website, not in this app.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        );
      case LoginResult.notFound:
        await _showNoAccountAlert();
      case LoginResult.invalidCredentials:
        if (!mounted) return;
        setState(() {
          _passwordError = 'Incorrect password. Check and try again.';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _passwordFocus.requestFocus();
        });
      case LoginResult.unexpectedError:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            content: Text(
              'Something went wrong. Try again in a moment.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        );
    }
  }

  Future<void> _showNoAccountAlert() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
                boxShadow: [
                  BoxShadow(
                    color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AgapColors.loginHeroSky,
                              AgapColors.brandWordmarkBlue.withValues(alpha: 0.35),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.22),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.person_add_rounded,
                          color: AgapColors.brandWordmarkBlue,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'No account found',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: AgapColors.brandNavySuit,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "We couldn't find an AgapShift profile for that email. "
                    'Create an account to get started.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Try again',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: _GradientCta(
                            label: 'Sign up',
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await widget.onTapSignUp();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AgapColors.loginBackdropTop,
                  Color.lerp(
                        AgapColors.loginHeroSkyLight,
                        AgapColors.businessMint,
                        0.35,
                      ) ??
                      AgapColors.loginBackdropTop,
                  AgapColors.loginBackdropBottom,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LoginMarketplacePatternPainter(),
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: _GlowOrb(
              diameter: 200,
              color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            top: 120,
            left: -30,
            child: _GlowOrb(
              diameter: 140,
              color: AgapColors.urgentBadge.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -50,
            child: _GlowOrb(
              diameter: 240,
              color: AgapColors.loginHeroSky.withValues(alpha: 0.42),
            ),
          ),
          Positioned(
            bottom: 200,
            right: -20,
            child: _GlowOrb(
              diameter: 120,
              color: AgapColors.businessGreen.withValues(alpha: 0.07),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 28 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  FadeTransition(
                    opacity: _heroFade,
                    child: ScaleTransition(
                      scale: _heroScale,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 280,
                            maxHeight: 120,
                          ),
                          child: Image.asset(
                            'branding/main.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            semanticLabel: 'AgapShift logo',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _copyFade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Welcome to AgapShift',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AgapColors.brandNavySuit,
                            letterSpacing: -0.6,
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Find shifts. Hire faster. Work smarter.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.82),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'For workers & employers · Trusted marketplace',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _TrustStrip(),
                        const SizedBox(height: 14),
                        _BenefitChipsRow(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  FadeTransition(
                    opacity: _formFade,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: AgapColors.brandWordmarkBlue
                                    .withValues(alpha: 0.1),
                                blurRadius: 40,
                                offset: const Offset(0, 18),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: AgapColors.businessGreen
                                    .withValues(alpha: 0.04),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                            ],
                            border: Border.all(
                              color: AgapColors.loginHeroSkyLight
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Label('Email or Username'),
                              _AuthField(
                                controller: _email,
                                hint: 'you@example.com',
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [
                                  AutofillHints.email,
                                  AutofillHints.username,
                                ],
                                errorText: _emailError,
                                onChanged: (_) => setState(() {
                                  _emailError = null;
                                  _passwordError = null;
                                }),
                              ),
                              const SizedBox(height: 18),
                              _Label('Password'),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _AuthField(
                                    controller: _password,
                                    focusNode: _passwordFocus,
                                    hint: 'Enter your password',
                                    obscureText: !_passwordVisible,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    errorText: _passwordError,
                                    suffix: IconButton(
                                      style: IconButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF94A3B8),
                                      ),
                                      icon: Icon(
                                        _passwordVisible
                                            ? Icons.visibility_rounded
                                            : Icons.visibility_off_rounded,
                                        size: 22,
                                      ),
                                      onPressed: () => setState(
                                        () => _passwordVisible =
                                            !_passwordVisible,
                                      ),
                                    ),
                                    onChanged: (_) => setState(
                                      () => _passwordError = null,
                                    ),
                                    onSubmitted: (_) => _onSubmit(),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.only(
                                          top: 2,
                                          bottom: 0,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            behavior:
                                                SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            content: Text(
                                              'Password recovery coming soon.',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        'Forgot password?',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AgapColors.brandWordmarkBlue,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: _GradientCta(
                                  label: 'Sign In',
                                  busy: _submitting,
                                  onPressed:
                                      _submitting ? null : _onSubmit,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: AgapColors.brandWordmarkBlue
                                    .withValues(alpha: 0.18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AgapColors.brandWordmarkBlue
                                      .withValues(alpha: 0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "Don't have an account?",
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _submitting
                                        ? null
                                        : () => widget.onTapSignUp(),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            AgapColors.loginHeroSky,
                                            Color.lerp(
                                                  AgapColors.loginHeroSky,
                                                  AgapColors.businessMint,
                                                  0.5,
                                                ) ??
                                                AgapColors.loginHeroSky,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: AgapColors.brandWordmarkBlue
                                              .withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 10,
                                        ),
                                        child: Text(
                                          'Create account',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color:
                                                AgapColors.brandWordmarkBlue,
                                          ),
                                        ),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 20,
            color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Secure hiring · Verified accounts · Built for real shifts',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitChipsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget chip(String text) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 15,
            color: AgapColors.businessGreenDeep,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF475569),
            ),
          ),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        chip('Flexible shifts'),
        chip('Fast hiring'),
        chip('Fair pay tools'),
      ],
    );
  }
}

class _LoginMarketplacePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AgapColors.brandWordmarkBlue.withValues(alpha: 0.045)
      ..strokeWidth = 1;

    const step = 36.0;
    for (double x = 0; x < size.width + step; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height * 0.35, size.height), grid);
    }
    for (double y = 0; y < size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - size.width * 0.12), grid);
    }

    final dot = Paint()
      ..color = AgapColors.businessGreen.withValues(alpha: 0.06);
    for (var i = 0; i < 28; i++) {
      final cx = (i * 67.0 + 12) % (size.width + 40) - 20;
      final cy = (i * 53.0 + 31) % (size.height + 40) - 20;
      canvas.drawCircle(Offset(cx, cy), 2.2 + (i % 3) * 0.8, dot);
    }

    final arc = Paint()
      ..color = AgapColors.urgentText.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawArc(
      Rect.fromLTWH(size.width * 0.55, -40, size.width * 0.5, 120),
      math.pi * 0.1,
      math.pi * 0.9,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _GradientCta extends StatelessWidget {
  const _GradientCta({
    required this.label,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: disabled
              ? [
                  AgapColors.brandWordmarkBlue.withValues(alpha: 0.45),
                  AgapColors.brandWordmarkBlue.withValues(alpha: 0.35),
                ]
              : [
                  const Color(0xFF2A6BC7),
                  AgapColors.brandWordmarkBlue,
                  const Color(0xFF163D7A),
                ],
        ),
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.38),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AgapColors.brandNavySuit.withValues(alpha: 0.88),
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    this.suffix,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final Widget? suffix;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  late FocusNode _focus;
  var _ownFocus = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focus = widget.focusNode!;
    } else {
      _focus = FocusNode();
      _ownFocus = true;
    }
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    if (_ownFocus) {
      _focus.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasErr = widget.errorText != null;
    final focused = _focus.hasFocus;
    final glow = focused && !hasErr;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.22),
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: AgapColors.businessGreen.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        autofillHints: widget.autofillHints,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AgapColors.brandNavySuit,
        ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF94A3B8),
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: hasErr
              ? const Color(0xFFFEF2F2)
              : AgapColors.loginFieldFill,
          suffixIcon: widget.suffix,
          errorText: widget.errorText,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: const Color(0xFFD8E4F0),
              width: focused ? 1.4 : 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: AgapColors.brandWordmarkBlue,
              width: focused ? 2.2 : 1.8,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.8),
          ),
        ),
      ),
    );
  }
}

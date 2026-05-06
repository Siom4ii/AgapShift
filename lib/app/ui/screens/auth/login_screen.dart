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

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _passwordVisible = false;
  bool _submitting = false;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AgapColors.loginBackdropTop,
                  AgapColors.loginBackdropBottom,
                ],
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -40,
            child: _GlowOrb(
              diameter: 200,
              color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.09),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -50,
            child: _GlowOrb(
              diameter: 240,
              color: AgapColors.loginHeroSky.withValues(alpha: 0.45),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 28 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(child: _LogoLockBadge()),
                  const SizedBox(height: 28),
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AgapColors.brandNavySuit,
                      letterSpacing: -0.8,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sign in to continue with AgapShift',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.72),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.08),
                          blurRadius: 32,
                          offset: const Offset(0, 14),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: AgapColors.loginHeroSkyLight.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Label('Email or Username'),
                        _Field(
                          controller: _email,
                          hint: 'you@example.com',
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email, AutofillHints.username],
                          errorText: _emailError,
                          onChanged: (_) => setState(() {
                            _emailError = null;
                            _passwordError = null;
                          }),
                        ),
                        const SizedBox(height: 18),
                        _Label('Password'),
                        _Field(
                          controller: _password,
                          focusNode: _passwordFocus,
                          hint: 'Enter your password',
                          obscureText: !_passwordVisible,
                          autofillHints: const [AutofillHints.password],
                          errorText: _passwordError,
                          suffix: IconButton(
                            style: IconButton.styleFrom(
                              foregroundColor: const Color(0xFF94A3B8),
                            ),
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              size: 22,
                            ),
                            onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                          ),
                          onChanged: (_) => setState(() => _passwordError = null),
                          onSubmitted: (_) => _onSubmit(),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  content: Text(
                                    'Password recovery coming soon.',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              );
                            },
                            child: Text(
                              'Forgot password?',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AgapColors.brandWordmarkBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: _GradientCta(
                            label: 'Sign In',
                            busy: _submitting,
                            onPressed: _submitting ? null : _onSubmit,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account?",
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      TextButton(
                        onPressed: _submitting ? null : () => widget.onTapSignUp(),
                        child: Text(
                          'Sign Up',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AgapColors.brandWordmarkBlue,
                          ),
                        ),
                      ),
                    ],
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

class _LogoLockBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AgapColors.loginHeroSkyLight,
            AgapColors.loginHeroSky,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.85),
            blurRadius: 0,
            spreadRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.lock_rounded,
        color: AgapColors.brandWordmarkBlue,
        size: 42,
      ),
    );
  }
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

class _Field extends StatelessWidget {
  const _Field({
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
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autofillHints: autofillHints,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AgapColors.brandNavySuit,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: const Color(0xFF94A3B8),
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: errorText != null
            ? const Color(0xFFFEF2F2)
            : AgapColors.loginFieldFill,
        suffixIcon: suffix,
        errorText: errorText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD8E4F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AgapColors.brandWordmarkBlue, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.6),
        ),
      ),
    );
  }
}

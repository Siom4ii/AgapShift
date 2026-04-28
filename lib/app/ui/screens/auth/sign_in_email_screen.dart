import 'package:flutter/material.dart';

import '../../../../domain/enums.dart';

class SignInEmailScreen extends StatefulWidget {
  const SignInEmailScreen({
    super.key,
    required this.role,
    required this.onSubmit,
  });

  final UserRole? role;
  final Future<void> Function(String email) onSubmit;

  @override
  State<SignInEmailScreen> createState() => _SignInEmailScreenState();
}

class _SignInEmailScreenState extends State<SignInEmailScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _controller.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await widget.onSubmit(email);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not send OTP. Try again.');
    } finally {
      if (!mounted) return;
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (widget.role) {
      UserRole.worker => 'Worker',
      UserRole.business => 'Business',
      _ => 'User',
    };

    return Scaffold(
      appBar: AppBar(title: Text('Sign in ($roleLabel)')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your email to receive a 6-digit code.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: 'Email',
                  errorText: _error,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


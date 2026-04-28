import 'dart:async';

import 'package:flutter/material.dart';

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
  final _controller = TextEditingController();
  bool _verifying = false;
  String? _error;

  static const _cooldown = 30;
  int _secondsLeft = _cooldown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _cooldown);
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

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _error = null;
      _verifying = true;
    });
    final ok = await widget.onVerify(code);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _verifying = false;
        _error = 'Invalid code. Try again.';
      });
      return;
    }
    setState(() => _verifying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify code'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async => widget.onBack(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('We sent a code to ${widget.email}.'),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: '6-digit code',
                  errorText: _error,
                  counterText: '',
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _verifying ? null : _verify,
                  child: _verifying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _secondsLeft == 0
                        ? () async {
                            await widget.onResend();
                            if (!mounted) return;
                            _startTimer();
                          }
                        : null,
                    child: const Text('Resend code'),
                  ),
                  const Spacer(),
                  if (_secondsLeft > 0)
                    Text(
                      '$_secondsLeft s',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


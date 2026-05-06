import 'package:flutter/material.dart';

import '../../../../domain/enums.dart';

class VerificationStatusScreen extends StatelessWidget {
  const VerificationStatusScreen({
    super.key,
    required this.status,
    required this.onReset,
  });

  final AccountStatus status;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    final (title, body, icon) = switch (status) {
      AccountStatus.pendingVerification => (
          'Pending verification',
          'Your account is under review. You’ll be notified once approved.',
          Icons.hourglass_bottom,
        ),
      AccountStatus.rejected => (
          'Verification rejected',
          'Your submission was rejected. Please resubmit your details.',
          Icons.error_outline,
        ),
      AccountStatus.suspended => (
          'Account suspended',
          'Your account is suspended. Contact support.',
          Icons.block,
        ),
      AccountStatus.verified => (
          'Verified',
          'You’re verified and can use all features.',
          Icons.verified,
        ),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Account status')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Icon(icon, size: 56),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              const Spacer(),
              if (status != AccountStatus.verified)
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async => onReset(),
                        child: const Text('Reset and resubmit'),
                      ),
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


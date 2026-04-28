import 'package:flutter/material.dart';

class BusinessOnboardingScreen extends StatefulWidget {
  const BusinessOnboardingScreen({super.key, required this.onSubmit});

  final Future<void> Function() onSubmit;

  @override
  State<BusinessOnboardingScreen> createState() => _BusinessOnboardingScreenState();
}

class _BusinessOnboardingScreenState extends State<BusinessOnboardingScreen> {
  int _step = 0;

  final _businessName = TextEditingController();
  String? _businessType;

  bool _hasDocs = false;
  bool _hasLocation = false;
  bool _hasPayment = false;

  @override
  void dispose() {
    _businessName.dispose();
    super.dispose();
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _businessName.text.trim().isNotEmpty && _businessType != null;
      case 1:
        return _hasDocs;
      case 2:
        return _hasLocation;
      case 3:
        return _hasPayment;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Business onboarding')),
      body: SafeArea(
        child: Stepper(
          currentStep: _step,
          onStepContinue: _canContinue
              ? () async {
                  if (_step < 3) {
                    setState(() => _step += 1);
                    return;
                  }
                  await widget.onSubmit();
                }
              : null,
          onStepCancel: _step == 0 ? null : () => setState(() => _step -= 1),
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  FilledButton(
                    onPressed: details.onStepContinue,
                    child: Text(_step < 3 ? 'Continue' : 'Submit for review'),
                  ),
                  const SizedBox(width: 12),
                  if (_step > 0)
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Back'),
                    ),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Business details'),
              isActive: _step >= 0,
              content: Column(
                children: [
                  TextField(
                    controller: _businessName,
                    decoration: const InputDecoration(labelText: 'Business name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _businessType,
                    decoration: const InputDecoration(labelText: 'Business type'),
                    items: const [
                      DropdownMenuItem(value: 'sole', child: Text('Sole Proprietorship')),
                      DropdownMenuItem(value: 'partnership', child: Text('Partnership')),
                      DropdownMenuItem(value: 'corporation', child: Text('Corporation')),
                    ],
                    onChanged: (v) => setState(() => _businessType = v),
                  ),
                ],
              ),
            ),
            Step(
              title: const Text('Verification docs'),
              isActive: _step >= 1,
              content: SwitchListTile(
                value: _hasDocs,
                onChanged: (v) => setState(() => _hasDocs = v),
                title: const Text('Uploaded permits/certificates/IDs (placeholder)'),
              ),
            ),
            Step(
              title: const Text('Location setup'),
              isActive: _step >= 2,
              content: SwitchListTile(
                value: _hasLocation,
                onChanged: (v) => setState(() => _hasLocation = v),
                title: const Text('Pinned business location (placeholder)'),
                subtitle: const Text('Map picker will be added later.'),
              ),
            ),
            Step(
              title: const Text('Payment setup'),
              isActive: _step >= 3,
              content: SwitchListTile(
                value: _hasPayment,
                onChanged: (v) => setState(() => _hasPayment = v),
                title: const Text('Linked bank/e-wallet (placeholder)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';

class WorkerOnboardingScreen extends StatefulWidget {
  const WorkerOnboardingScreen({super.key, required this.onSubmit});

  final Future<void> Function() onSubmit;

  @override
  State<WorkerOnboardingScreen> createState() => _WorkerOnboardingScreenState();
}

class _WorkerOnboardingScreenState extends State<WorkerOnboardingScreen> {
  int _step = 0;

  final _fullName = TextEditingController();
  final _address = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _bio = TextEditingController();

  bool _hasIdUpload = false;
  bool _hasSelfie = false;
  bool _hasPayout = false;

  @override
  void dispose() {
    _fullName.dispose();
    _address.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return _fullName.text.trim().isNotEmpty && _address.text.trim().isNotEmpty;
      case 1:
        return _bio.text.trim().isNotEmpty;
      case 2:
        return _hasPayout;
      case 3:
        return _hasIdUpload && _hasSelfie;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Worker onboarding')),
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
              title: const Text('Personal info'),
              isActive: _step >= 0,
              content: Column(
                children: [
                  TextField(
                    controller: _fullName,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _address,
                    decoration: const InputDecoration(labelText: 'Address'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emergencyName,
                    decoration: const InputDecoration(labelText: 'Emergency contact name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emergencyPhone,
                    decoration: const InputDecoration(labelText: 'Emergency contact phone'),
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ),
            ),
            Step(
              title: const Text('Profile'),
              isActive: _step >= 1,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add a short bio and select skills later (MVP placeholder).'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bio,
                    decoration: const InputDecoration(labelText: 'Short bio'),
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            Step(
              title: const Text('Payout setup'),
              isActive: _step >= 2,
              content: Column(
                children: [
                  SwitchListTile(
                    value: _hasPayout,
                    onChanged: (v) => setState(() => _hasPayout = v),
                    title: const Text('I linked GCash/Maya/Bank (placeholder)'),
                    subtitle: const Text('We’ll integrate providers later.'),
                  ),
                ],
              ),
            ),
            Step(
              title: const Text('Identity verification'),
              isActive: _step >= 3,
              content: Column(
                children: [
                  SwitchListTile(
                    value: _hasIdUpload,
                    onChanged: (v) => setState(() => _hasIdUpload = v),
                    title: const Text('Uploaded government ID (placeholder)'),
                  ),
                  SwitchListTile(
                    value: _hasSelfie,
                    onChanged: (v) => setState(() => _hasSelfie = v),
                    title: const Text('Completed selfie liveness (placeholder)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


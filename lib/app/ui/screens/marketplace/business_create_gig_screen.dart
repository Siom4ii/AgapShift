import 'package:flutter/material.dart';

import '../../../../domain/models.dart';
import '../../../marketplace/mock_marketplace_repository.dart';
import '../../../session/session_controller.dart';

class BusinessCreateGigScreen extends StatefulWidget {
  const BusinessCreateGigScreen({
    super.key,
    required this.repo,
    required this.session,
    required this.onCreated,
  });

  final MockMarketplaceRepository repo;
  final SessionController session;
  final Future<void> Function() onCreated;

  @override
  State<BusinessCreateGigScreen> createState() => _BusinessCreateGigScreenState();
}

class _BusinessCreateGigScreenState extends State<BusinessCreateGigScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _address = TextEditingController(text: 'Manila, NCR');

  String _category = 'Food Service';
  int _payAmount = 80000; // centavos
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final businessId = widget.session.state.email ?? 'business';
      final now = DateTime.now();
      await widget.repo.createGig(
        businessId: businessId,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        location: const GeoPoint(lat: 14.5995, lng: 120.9842),
        addressLabel: _address.text.trim(),
        startAt: now.add(const Duration(days: 1)),
        endAt: now.add(const Duration(days: 1, hours: 8)),
        pay: Money(amount: _payAmount),
        category: _category,
      );
      if (!mounted) return;
      await widget.onCreated();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gig posted')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post a gig')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: 'Title',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: const [
                DropdownMenuItem(value: 'Food Service', child: Text('Food Service')),
                DropdownMenuItem(value: 'Retail', child: Text('Retail')),
                DropdownMenuItem(value: 'Warehouse', child: Text('Warehouse')),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _payAmount,
              decoration: const InputDecoration(labelText: 'Pay (total)'),
              items: const [
                DropdownMenuItem(value: 50000, child: Text('₱500')),
                DropdownMenuItem(value: 80000, child: Text('₱800')),
                DropdownMenuItem(value: 100000, child: Text('₱1000')),
              ],
              onChanged: (v) => setState(() => _payAmount = v ?? _payAmount),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address label'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 4,
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
                    : const Text('Post gig'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


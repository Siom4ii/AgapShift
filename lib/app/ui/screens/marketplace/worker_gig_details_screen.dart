import 'package:flutter/material.dart';

import '../../../../domain/models.dart';
import '../../../marketplace/mock_marketplace_repository.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../session/session_controller.dart';

class WorkerGigDetailsScreen extends StatefulWidget {
  const WorkerGigDetailsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.session,
    required this.gigId,
  });

  final MockMarketplaceRepository repo;
  final MockNotificationRepository notifications;
  final SessionController session;
  final String gigId;

  @override
  State<WorkerGigDetailsScreen> createState() => _WorkerGigDetailsScreenState();
}

class _WorkerGigDetailsScreenState extends State<WorkerGigDetailsScreen> {
  Gig? _gig;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gig = await widget.repo.getGig(widget.gigId);
      if (!mounted) return;
      setState(() => _gig = gig);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final workerId = widget.session.state.email ?? 'worker';
    try {
      await widget.repo.applyToGig(gigId: widget.gigId, workerId: workerId);
      final gig = await widget.repo.getGig(widget.gigId);
      if (gig != null) {
        await widget.notifications.add(
          userId: gig.businessId,
          title: 'New applicant',
          body: '$workerId applied to: ${gig.title}',
          data: {'gigId': gig.id},
        );
        await widget.notifications.add(
          userId: workerId,
          title: 'Application sent',
          body: 'You applied to: ${gig.title}',
          data: {'gigId': gig.id},
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Applied')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot apply: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gig = _gig;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gig details'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Error: $_error'))
                : gig == null
                    ? const Center(child: Text('Gig not found'))
                    : Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(gig.title, style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            Text('${gig.category} • ${gig.addressLabel}'),
                            const SizedBox(height: 8),
                            Text('Pay: ₱${(gig.pay.amount / 100).toStringAsFixed(2)}'),
                            const SizedBox(height: 8),
                            Text('Starts: ${gig.startAt.toLocal()}'),
                            Text('Ends: ${gig.endAt.toLocal()}'),
                            const SizedBox(height: 12),
                            Text(gig.description),
                            const Spacer(),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _apply,
                                child: const Text('Apply'),
                              ),
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }
}


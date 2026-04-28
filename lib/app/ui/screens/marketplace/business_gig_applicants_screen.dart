import 'package:flutter/material.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../marketplace/mock_marketplace_repository.dart';
import '../../../payments/mock_payments_repository.dart';
import '../../../session/session_controller.dart';

class BusinessGigApplicantsScreen extends StatefulWidget {
  const BusinessGigApplicantsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.payments,
    required this.session,
    required this.gig,
  });

  final MockMarketplaceRepository repo;
  final MockNotificationRepository notifications;
  final MockPaymentsRepository payments;
  final SessionController session;
  final Gig gig;

  @override
  State<BusinessGigApplicantsScreen> createState() => _BusinessGigApplicantsScreenState();
}

class _BusinessGigApplicantsScreenState extends State<BusinessGigApplicantsScreen> {
  bool _loading = false;
  List<GigApplication> _apps = const [];
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
      final apps = await widget.repo.listApplicants(widget.gig.id);
      if (!mounted) return;
      setState(() => _apps = apps);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _hire(GigApplication a) async {
    final businessId = widget.session.state.email ?? 'business';
    try {
      final escrowFunded = await widget.payments.isEscrowFunded(widget.gig.id);
      if (!escrowFunded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fund escrow before hiring.')),
        );
        return;
      }
      await widget.payments.holdEscrow(gigId: widget.gig.id);
      final result = await widget.repo.hireApplicant(
        gigId: widget.gig.id,
        applicationId: a.id,
        businessId: businessId,
      );
      await widget.notifications.add(
        userId: result.selectedWorkerId,
        title: 'You were hired',
        body: 'Gig: ${widget.gig.title}',
        data: {'gigId': widget.gig.id},
      );
      for (final wid in result.rejectedWorkerIds) {
        await widget.notifications.add(
          userId: wid,
          title: 'Application update',
          body: 'Not selected for: ${widget.gig.title}',
          data: {'gigId': widget.gig.id},
        );
      }
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hired ${a.workerId}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot hire: $e')),
      );
    }
  }

  Future<void> _fundEscrow() async {
    final businessId = widget.session.state.email ?? 'business';
    try {
      await widget.payments.fundEscrow(
        gigId: widget.gig.id,
        businessId: businessId,
        amount: widget.gig.pay,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escrow funded')));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot fund escrow: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final escrowFuture = widget.payments.getEscrowForGig(widget.gig.id);
    return Scaffold(
      appBar: AppBar(
        title: Text('Applicants • ${widget.gig.title}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder(
          future: escrowFuture,
          builder: (context, escrowSnap) {
            final escrow = escrowSnap.data;
            final funded = escrow != null &&
                (escrow.status == EscrowStatus.funded || escrow.status == EscrowStatus.held);
            return Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            funded ? 'Escrow: Funded' : 'Escrow: Not funded',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (!funded)
                          FilledButton(
                            onPressed: _fundEscrow,
                            child: const Text('Fund escrow'),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text('Error: $_error'))
                          : _apps.isEmpty
                              ? const Center(child: Text('No applicants yet.'))
                              : ListView.separated(
                                  itemCount: _apps.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, i) {
                                    final a = _apps[i];
                                    return ListTile(
                                      title: Text(a.workerId),
                                      subtitle: Text(_appStatus(a.status)),
                                      trailing: widget.gig.status == GigStatus.open &&
                                              a.status == ApplicationStatus.applied
                                          ? FilledButton(
                                              onPressed: () => _hire(a),
                                              child: const Text('Hire'),
                                            )
                                          : null,
                                    );
                                  },
                                ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _appStatus(ApplicationStatus s) => switch (s) {
        ApplicationStatus.applied => 'Applied',
        ApplicationStatus.withdrawn => 'Withdrawn',
        ApplicationStatus.rejected => 'Rejected',
        ApplicationStatus.hired => 'Hired',
      };
}


import 'package:flutter/material.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../payments/mock_payments_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/mock_shift_repository.dart';
import 'business_gig_applicants_screen.dart';
import '../shift/business_qr_screen.dart';

class BusinessGigsScreen extends StatefulWidget {
  const BusinessGigsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.payments,
    required this.shiftRepo,
    required this.session,
    this.embedded = false,
  });

  final MarketplaceRepository repo;
  final MockNotificationRepository notifications;
  final MockPaymentsRepository payments;
  final MockShiftRepository shiftRepo;
  final SessionController session;
  final bool embedded;

  @override
  State<BusinessGigsScreen> createState() => _BusinessGigsScreenState();
}

class _BusinessGigsScreenState extends State<BusinessGigsScreen> {
  bool _loading = false;
  List<Gig> _items = const [];
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
      final businessId = appActorId(widget.session, mockFallback: 'business');
      final all = await widget.repo.listGigs();
      final items = all.where((g) => g.businessId == businessId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _cancel(Gig gig) async {
    final businessId = appActorId(widget.session, mockFallback: 'business');
    try {
      await widget.repo.cancelGig(gigId: gig.id, businessId: businessId);
      await widget.notifications.add(
        userId: businessId,
        title: 'Gig cancelled',
        body: 'Gig: ${gig.title}',
        data: {'gigId': gig.id},
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot cancel: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text('Error: $_error'))
            : _items.isEmpty
                ? const Center(child: Text('No gigs yet. Tap “Post a Job” on Home to create one.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final g = _items[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                title: Text(g.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text('${g.category} • ${_statusLabel(g.status)}'),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                                child: Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => BusinessGigApplicantsScreen(
                                              repo: widget.repo,
                                              notifications: widget.notifications,
                                              payments: widget.payments,
                                              session: widget.session,
                                              gig: g,
                                            ),
                                          ),
                                        );
                                        await _load();
                                      },
                                      icon: const Icon(Icons.people_alt_outlined),
                                      label: const Text('Applicants'),
                                    ),
                                    if (g.status == GigStatus.filled ||
                                        g.status == GigStatus.ongoing ||
                                        g.status == GigStatus.open)
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => BusinessQrScreen(
                                                shiftRepo: widget.shiftRepo,
                                                gig: g,
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.qr_code_2),
                                        label: const Text('QR'),
                                      ),
                                    if (g.status != GigStatus.cancelled && g.status != GigStatus.completed)
                                      TextButton.icon(
                                        onPressed: () => _cancel(g),
                                        icon: const Icon(Icons.cancel_outlined),
                                        label: const Text('Cancel'),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );

    if (widget.embedded) {
      return SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'My gigs',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Expanded(child: list),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My gigs'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: list),
    );
  }

  String _statusLabel(GigStatus s) => switch (s) {
        GigStatus.open => 'Open',
        GigStatus.filled => 'Filled',
        GigStatus.ongoing => 'Ongoing',
        GigStatus.completed => 'Completed',
        GigStatus.cancelled => 'Cancelled',
      };
}


import 'package:flutter/material.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../marketplace/mock_marketplace_repository.dart';
import '../../../payments/mock_payments_repository.dart';
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
  });

  final MockMarketplaceRepository repo;
  final MockNotificationRepository notifications;
  final MockPaymentsRepository payments;
  final MockShiftRepository shiftRepo;
  final SessionController session;

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
      final businessId = widget.session.state.email ?? 'business';
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
    final businessId = widget.session.state.email ?? 'business';
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
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Error: $_error'))
                : _items.isEmpty
                    ? const Center(child: Text('No gigs yet. Use “Post” to create one.'))
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final g = _items[i];
                          return ListTile(
                            title: Text(g.title),
                            subtitle: Text('${g.category} • ${_statusLabel(g.status)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Applicants',
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
                                ),
                                if (g.status == GigStatus.filled ||
                                    g.status == GigStatus.ongoing ||
                                    g.status == GigStatus.open)
                                  IconButton(
                                    tooltip: 'QR',
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
                                  ),
                                if (g.status != GigStatus.cancelled && g.status != GigStatus.completed)
                                  IconButton(
                                    tooltip: 'Cancel',
                                    onPressed: () => _cancel(g),
                                    icon: const Icon(Icons.cancel_outlined),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
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


import 'package:flutter/material.dart';

import '../../../../domain/models.dart';
import '../../../marketplace/mock_marketplace_repository.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../session/session_controller.dart';
import 'worker_gig_details_screen.dart';

class WorkerGigsScreen extends StatefulWidget {
  const WorkerGigsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.session,
  });

  final MockMarketplaceRepository repo;
  final MockNotificationRepository notifications;
  final SessionController session;

  @override
  State<WorkerGigsScreen> createState() => _WorkerGigsScreenState();
}

class _WorkerGigsScreenState extends State<WorkerGigsScreen> {
  int _radiusM = 5000;
  int _minPay = 0;
  String _category = '';

  bool _loading = false;
  List<Gig> _items = const [];
  String? _error;

  GeoPoint get _center => const GeoPoint(lat: 14.5995, lng: 120.9842); // Manila default

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
      final items = await widget.repo.listNearbyGigs(
        center: _center,
        radiusMeters: _radiusM,
        minPayAmount: _minPay == 0 ? null : _minPay,
        category: _category.isEmpty ? null : _category,
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby gigs'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _Filters(
              radiusM: _radiusM,
              minPay: _minPay,
              category: _category,
              onChanged: (radiusM, minPay, category) {
                setState(() {
                  _radiusM = radiusM;
                  _minPay = minPay;
                  _category = category;
                });
                _load();
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text('Error: $_error'))
                      : _items.isEmpty
                          ? const Center(child: Text('No open gigs nearby yet.'))
                          : ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final g = _items[i];
                                return ListTile(
                                  title: Text(g.title),
                                  subtitle: Text('${g.category} • ₱${(g.pay.amount / 100).toStringAsFixed(2)}'),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => WorkerGigDetailsScreen(
                                          repo: widget.repo,
                                          notifications: widget.notifications,
                                          session: widget.session,
                                          gigId: g.id,
                                        ),
                                      ),
                                    );
                                    await _load();
                                  },
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.radiusM,
    required this.minPay,
    required this.category,
    required this.onChanged,
  });

  final int radiusM;
  final int minPay;
  final String category;
  final void Function(int radiusM, int minPay, String category) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<int>(
            value: radiusM,
            items: const [
              DropdownMenuItem(value: 1000, child: Text('1 km')),
              DropdownMenuItem(value: 3000, child: Text('3 km')),
              DropdownMenuItem(value: 5000, child: Text('5 km')),
              DropdownMenuItem(value: 10000, child: Text('10 km')),
            ],
            onChanged: (v) => onChanged(v ?? radiusM, minPay, category),
          ),
          DropdownButton<int>(
            value: minPay,
            items: const [
              DropdownMenuItem(value: 0, child: Text('Any pay')),
              DropdownMenuItem(value: 50000, child: Text('≥ ₱500')),
              DropdownMenuItem(value: 80000, child: Text('≥ ₱800')),
              DropdownMenuItem(value: 100000, child: Text('≥ ₱1000')),
            ],
            onChanged: (v) => onChanged(radiusM, v ?? minPay, category),
          ),
          DropdownButton<String>(
            value: category,
            items: const [
              DropdownMenuItem(value: '', child: Text('Any type')),
              DropdownMenuItem(value: 'Food Service', child: Text('Food Service')),
              DropdownMenuItem(value: 'Retail', child: Text('Retail')),
              DropdownMenuItem(value: 'Warehouse', child: Text('Warehouse')),
            ],
            onChanged: (v) => onChanged(radiusM, minPay, v ?? category),
          ),
        ],
      ),
    );
  }
}


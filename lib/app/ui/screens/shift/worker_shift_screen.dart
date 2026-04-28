import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/enums.dart';
import '../../../marketplace/mock_marketplace_repository.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../payments/mock_payments_repository.dart';
import '../../../session/session_controller.dart';
import '../../../shift/mock_shift_repository.dart';
import '../ratings/rate_user_screen.dart';

class WorkerShiftScreen extends StatefulWidget {
  const WorkerShiftScreen({
    super.key,
    required this.marketRepo,
    required this.shiftRepo,
    required this.payments,
    required this.session,
  });

  final MockMarketplaceRepository marketRepo;
  final MockShiftRepository shiftRepo;
  final MockPaymentsRepository payments;
  final SessionController session;

  @override
  State<WorkerShiftScreen> createState() => _WorkerShiftScreenState();
}

class _WorkerShiftScreenState extends State<WorkerShiftScreen> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  String _gigId = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _scan(AttendanceScanType type) async {
    final token = await _promptToken(context);
    if (token == null || token.trim().isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final workerId = widget.session.state.email ?? 'worker';
      // In our mock, gig stores businessId; reuse that as the validator.
      final gig = await widget.marketRepo.getGig(_gigId);
      if (gig == null) throw StateError('Select a gig first');
      await widget.shiftRepo.scanQr(
        qrToken: token.trim(),
        gigId: _gigId,
        workerId: workerId,
        businessId: gig.businessId,
        type: type,
      );

      if (type == AttendanceScanType.checkOut) {
        final hiredWorker = await widget.marketRepo.getHiredWorkerId(_gigId);
        if (hiredWorker == workerId) {
          final funded = await widget.payments.isEscrowFunded(_gigId);
          if (funded) {
            await widget.payments.releaseEscrowToWorker(gigId: _gigId, workerId: workerId);
          }
        }

        // Prompt worker to rate the business after successful checkout.
        final gigAfter = await widget.marketRepo.getGig(_gigId);
        if (gigAfter != null) {
          final ratings = MarketplaceScope.of(context).ratings;
          final existing = await ratings.getForShift(
            gigId: _gigId,
            raterUserId: workerId,
            ratedUserId: gigAfter.businessId,
          );
          if (existing == null && mounted) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RateUserScreen(
                  ratings: ratings,
                  gigId: _gigId,
                  raterUserId: workerId,
                  ratedUserId: gigAfter.businessId,
                  title: 'Rate the business for "${gigAfter.title}"',
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Active shift')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('MVP: choose a gig id then paste/scan a QR token.'),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Gig ID (from business gig list)',
                ),
                onChanged: (v) => setState(() => _gigId = v.trim()),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _loading || _gigId.isEmpty ? null : () => _scan(AttendanceScanType.checkIn),
                      child: const Text('Check-in'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _loading || _gigId.isEmpty ? null : () => _scan(AttendanceScanType.checkOut),
                      child: const Text('Check-out'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Now: ${_now.toLocal()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _gigId.isEmpty
                    ? const Center(child: Text('Enter a Gig ID to view attendance.'))
                    : FutureBuilder(
                        future: widget.shiftRepo.listAttendanceForGig(_gigId),
                        builder: (context, snap) {
                          final items = snap.data ?? const [];
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (items.isEmpty) {
                            return const Center(child: Text('No attendance records yet.'));
                          }
                          return ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final a = items[i];
                              return ListTile(
                                title: Text(a.type == AttendanceScanType.checkIn ? 'Check-in' : 'Check-out'),
                                subtitle: Text(a.scannedAt.toLocal().toString()),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> _promptToken(BuildContext context) async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Enter QR token'),
      content: TextField(
        controller: controller,
        maxLines: 3,
        decoration: const InputDecoration(hintText: 'Paste token here'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Submit')),
      ],
    ),
  );
}


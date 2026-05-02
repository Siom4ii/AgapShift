import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../payments/mock_payments_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/mock_shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import '../ratings/rate_user_screen.dart';

class WorkerShiftScreen extends StatefulWidget {
  const WorkerShiftScreen({
    super.key,
    required this.marketRepo,
    required this.shiftRepo,
    required this.payments,
    required this.session,
    this.showAppBar = true,
  });

  final MarketplaceRepository marketRepo;
  final MockShiftRepository shiftRepo;
  final MockPaymentsRepository payments;
  final SessionController session;
  final bool showAppBar;

  @override
  State<WorkerShiftScreen> createState() => _WorkerShiftScreenState();
}

class _WorkerShiftScreenState extends State<WorkerShiftScreen> {
  bool _loading = false;
  String? _error;
  Gig? _gig;
  List<AttendanceRecord> _attendance = const [];

  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final workerId = appActorId(widget.session, mockFallback: '');
      final gigs = await widget.marketRepo.listGigs();
      Gig? selected;

      if (workerId.isNotEmpty) {
        // Find the most relevant gig hired to this worker.
        final candidates = <Gig>[];
        for (final g in gigs) {
          final hired = await widget.marketRepo.getHiredWorkerId(g.id);
          if (hired == workerId) candidates.add(g);
        }
        candidates.sort((a, b) => a.startAt.compareTo(b.startAt));
        selected = candidates.isEmpty ? null : candidates.first;
      }

      // Demo fallback if there is no hired gig.
      selected ??= gigs.isEmpty
          ? null
          : (gigs..sort((a, b) => a.startAt.compareTo(b.startAt))).first;

      final attendance = selected == null
          ? <AttendanceRecord>[]
          : await widget.shiftRepo.listAttendanceForGig(selected.id);
      if (!mounted) return;
      setState(() {
        _gig = selected;
        _attendance = attendance;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime? get _checkInAt {
    final workerId = appActorId(widget.session, mockFallback: '');
    final a = _attendance
        .where(
          (r) => r.workerId == workerId && r.type == AttendanceScanType.checkIn,
        )
        .toList();
    if (a.isEmpty) return null;
    a.sort((x, y) => x.scannedAt.compareTo(y.scannedAt));
    return a.first.scannedAt.toLocal();
  }

  DateTime? get _checkOutAt {
    final workerId = appActorId(widget.session, mockFallback: '');
    final a = _attendance
        .where(
          (r) =>
              r.workerId == workerId && r.type == AttendanceScanType.checkOut,
        )
        .toList();
    if (a.isEmpty) return null;
    a.sort((x, y) => x.scannedAt.compareTo(y.scannedAt));
    return a.first.scannedAt.toLocal();
  }

  Future<void> _scan(AttendanceScanType type) async {
    final token = await _promptToken(context);
    if (token == null || token.trim().isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final workerId = appActorId(widget.session, mockFallback: 'worker');
      // In our mock, gig stores businessId; reuse that as the validator.
      final gig = _gig;
      if (gig == null) throw StateError('No active shift yet');
      await widget.shiftRepo.scanQr(
        qrToken: token.trim(),
        gigId: gig.id,
        workerId: workerId,
        businessId: gig.businessId,
        type: type,
      );

      if (type == AttendanceScanType.checkOut) {
        final hiredWorker = await widget.marketRepo.getHiredWorkerId(gig.id);
        if (hiredWorker == workerId) {
          final funded = await widget.payments.isEscrowFunded(gig.id);
          if (funded) {
            await widget.payments.releaseEscrowToWorker(
              gigId: gig.id,
              workerId: workerId,
            );
          }
        }

        // Prompt worker to rate the business after successful checkout.
        final gigAfter = await widget.marketRepo.getGig(gig.id);
        if (gigAfter != null) {
          if (!mounted) return;
          final nav = Navigator.of(context);
          final ratings = MarketplaceScope.of(context).ratings;
          final existing = await ratings.getForShift(
            gigId: gig.id,
            raterUserId: workerId,
            ratedUserId: gigAfter.businessId,
          );
          if (!mounted) return;
          if (existing == null) {
            await nav.push(
              MaterialPageRoute(
                builder: (_) => RateUserScreen(
                  ratings: ratings,
                  gigId: gig.id,
                  raterUserId: workerId,
                  ratedUserId: gigAfter.businessId,
                  title: 'Rate the business for "${gigAfter.title}"',
                ),
              ),
            );
          }
        }
      }
      final refreshed = await widget.shiftRepo.listAttendanceForGig(gig.id);
      if (mounted) setState(() => _attendance = refreshed);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gig = _gig;
    final checkIn = _checkInAt;
    final checkOut = _checkOutAt;
    final status = checkOut != null
        ? 'Completed'
        : checkIn != null
        ? 'In progress'
        : 'Upcoming';

    final payPhp = gig == null ? 0 : (gig.pay.amount / 100.0).round();
    final distanceKm = gig == null
        ? 0.0
        : _distanceKm(
            const GeoPoint(lat: 14.5995, lng: 120.9842),
            gig.location,
          );

    final canCheckIn = gig != null && checkIn == null;
    final canCheckOut = gig != null && checkIn != null && checkOut == null;
    final action = canCheckOut
        ? AttendanceScanType.checkOut
        : AttendanceScanType.checkIn;

    final body = SafeArea(
      child: ShellChromeBackground(
        kind: ShellChromeKind.worker,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            children: [
              Row(
                children: [
                  if (widget.showAppBar)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        borderRadius: BorderRadius.circular(999),
                        child: Ink(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AgapColors.borderSubtle.withValues(
                                alpha: 0.9,
                              ),
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Shift',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: status == 'Upcoming'
                                    ? const Color(0xFFF59E0B)
                                    : status == 'In progress'
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFF6B7280),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              status,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AgapColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _InlineError(message: _error!, onRetry: _load),
                ),
              if (gig == null)
                _EmptyShiftCard(now: _now)
              else
                _ShiftSummaryCard(
                  title: gig.title,
                  company: _companyFromBusinessId(gig.businessId),
                  payPhp: payPhp,
                  checkIn: checkIn,
                  checkOut: checkOut,
                ),
              const SizedBox(height: 14),
              if (gig != null)
                _LocationCard(
                  address: gig.addressLabel,
                  distanceKm: distanceKm,
                ),
              const SizedBox(height: 14),
              _ScanButton(
                enabled: !_loading && (canCheckIn || canCheckOut),
                label: canCheckOut
                    ? 'Scan QR — Check Out'
                    : 'Scan QR — Check In',
                onTap: () => _scan(action),
              ),
              const SizedBox(height: 12),
              _SecurityNote(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!widget.showAppBar) {
      return body;
    }
    return Scaffold(backgroundColor: AgapColors.pageBackground, body: body);
  }
}

class _ShiftSummaryCard extends StatelessWidget {
  const _ShiftSummaryCard({
    required this.title,
    required this.company,
    required this.payPhp,
    required this.checkIn,
    required this.checkOut,
  });

  final String title;
  final String company;
  final int payPhp;
  final DateTime? checkIn;
  final DateTime? checkOut;

  @override
  Widget build(BuildContext context) {
    String t(DateTime? d) {
      if (d == null) return 'Pending';
      final h = d.hour;
      final am = h >= 12 ? 'PM' : 'AM';
      final hr = h % 12 == 0 ? 12 : h % 12;
      final m = d.minute.toString().padLeft(2, '0');
      return '$hr:$m $am';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Shift',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      company,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Pay',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱$payPhp',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.schedule_rounded,
                  label: 'Check-in',
                  value: t(checkIn),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: Icons.schedule_rounded,
                  label: 'Check-out',
                  value: t(checkOut),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.95)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.address, required this.distanceKm});
  final String address;
  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AgapColors.borderSubtle.withValues(alpha: 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.place_rounded, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job Location',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  address,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${distanceKm.toStringAsFixed(1)} km from your location',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({
    required this.enabled,
    required this.label,
    required this.onTap,
  });
  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: enabled
              ? const Color(0xFF6D28D9)
              : AgapColors.textMuted.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: enabled ? onTap : null,
        icon: const Icon(Icons.qr_code_2_rounded),
        label: Text(
          label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'QR-based check-in/out prevents time fraud and ensures accurate payment processing.',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: Colors.red.shade800,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyShiftCard extends StatelessWidget {
  const _EmptyShiftCard({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AgapColors.borderSubtle.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No active shift yet',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Once you\'re hired for a gig, your shift details will appear here.',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AgapColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Now: ${now.toLocal()}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AgapColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

double _distanceKm(GeoPoint a, GeoPoint b) {
  final dx = (a.lat - b.lat) * 111000.0;
  final dy = (a.lng - b.lng) * 111000.0;
  return (math.sqrt(dx * dx + dy * dy)) / 1000.0;
}

String _companyFromBusinessId(String id) {
  if (id.isEmpty) return 'Verified Business';
  final local = id.split('@').first;
  final words = local
      .split(RegExp(r'[._-]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'Verified Business';
  final titled = words
      .map((w) => '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1) : ''}')
      .join(' ');
  return '$titled Logistics';
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Submit'),
        ),
      ],
    ),
  );
}

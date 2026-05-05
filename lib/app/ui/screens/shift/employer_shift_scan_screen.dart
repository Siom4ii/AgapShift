import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/success_feedback.dart';

/// Employer scans the **worker's** attendance QR to clock them in or out.
class EmployerShiftScanScreen extends StatefulWidget {
  const EmployerShiftScanScreen({
    super.key,
    required this.shiftRepo,
    required this.gig,
    required this.session,
    required this.payments,
    required this.repo,
  });

  final ShiftRepository shiftRepo;
  final Gig gig;
  final SessionController session;
  final PaymentsRepository payments;
  final MarketplaceRepository repo;

  @override
  State<EmployerShiftScanScreen> createState() =>
      _EmployerShiftScanScreenState();
}

class _EmployerShiftScanScreenState extends State<EmployerShiftScanScreen> {
  final MobileScannerController _scanner = MobileScannerController();
  bool _busy = false;
  bool _done = false;

  static const double _windowRadius = 22;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _handleRaw(String? raw) async {
    final code = raw?.trim();
    if (code == null || code.isEmpty || _busy || _done) return;

    setState(() => _busy = true);
    try {
      final businessId = appActorId(widget.session, mockFallback: 'business');
      final result = await widget.shiftRepo.scanWorkerAttendanceQr(
        qrToken: code,
        businessId: businessId,
      );

      if (result.scanType == AttendanceScanType.checkOut) {
        final workerId = await widget.repo.getHiredWorkerId(widget.gig.id);
        if (workerId != null) {
          final funded = await widget.payments.isEscrowFunded(widget.gig.id);
          if (funded) {
            await widget.payments.releaseEscrowToWorker(
              gigId: widget.gig.id,
              workerId: workerId,
            );
          }
        }
      }

      if (!mounted) return;
      setState(() => _done = true);
      await _scanner.stop();
      if (!mounted) return;
      final label = result.scanType == AttendanceScanType.checkIn
          ? 'Check-in saved'
          : 'Check-out saved';
      showSuccessSnackBar(context, label);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: const Color(0xFF991B1B),
          content: Text(
            '$e',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      );
      setState(() => _busy = false);
    }
  }

  Rect _scanWindowRect(Size box) {
    final side = math.min(box.width, box.height) * 0.72;
    return Rect.fromCenter(
      center: box.center(Offset.zero),
      width: side,
      height: side,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AgapColors.pageBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 12),
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: AgapColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attendance',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Scan the code on the worker’s phone',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AgapColors.textMuted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    AgapColors.businessMint.withValues(alpha: 0.85),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AgapColors.borderSubtle.withValues(alpha: 0.85),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AgapColors.businessGreen.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AgapColors.businessGreen.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      color: AgapColors.businessGreenDeep,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.gig.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _InfoChip(
                              icon: Icons.login_rounded,
                              label: 'Start shift',
                              muted: false,
                            ),
                            const SizedBox(width: 8),
                            _InfoChip(
                              icon: Icons.logout_rounded,
                              label: 'End shift',
                              muted: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final box = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final window = _scanWindowRect(box);

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _scanner,
                          fit: BoxFit.cover,
                          scanWindow: window,
                          placeholderBuilder: (ctx) => Container(
                            color: const Color(0xFF1E293B),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: AgapColors.businessGreenLight
                                          .withValues(alpha: 0.9),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Starting camera…',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          errorBuilder: (ctx, err) => Container(
                            color: const Color(0xFF1E293B),
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.videocam_off_outlined,
                                    size: 44,
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    err.errorCode.message,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          overlayBuilder: (ctx, cons) {
                            return CustomPaint(
                              size: cons.biggest,
                              painter: _ScanOverlayPainter(
                                window: window,
                                layerSize: cons.biggest,
                                cornerRadius: _windowRadius,
                              ),
                            );
                          },
                          onDetect: (capture) {
                            final codes = capture.barcodes;
                            if (codes.isEmpty) return;
                            _handleRaw(codes.first.rawValue);
                          },
                        ),
                        if (_busy)
                          Container(
                            color: Colors.black.withValues(alpha: 0.45),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 22,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 24,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: AgapColors.businessGreen,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Saving attendance…',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 16,
                          bottom: 20,
                          child: ListenableBuilder(
                            listenable: _scanner,
                            builder: (context, _) {
                              final torch = _scanner.value.torchState;
                              final on = torch == TorchState.on;
                              final unavailable =
                                  torch == TorchState.unavailable;
                              if (unavailable) return const SizedBox.shrink();
                              return Material(
                                color: Colors.white.withValues(alpha: 0.94),
                                elevation: 4,
                                shadowColor: Colors.black26,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: InkWell(
                                  onTap: () => _scanner.toggleTorch(),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Icon(
                                      on
                                          ? Icons.flashlight_on_rounded
                                          : Icons.flashlight_off_outlined,
                                      color: on
                                          ? AgapColors.accentOrange
                                          : const Color(0xFF475569),
                                      size: 24,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + bottomInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: AgapColors.primary.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Align the QR inside the frame. Scan once when the shift starts and again when it ends.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AgapColors.textMuted,
                      height: 1.45,
                    ),
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.muted,
  });

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: muted
            ? Colors.white.withValues(alpha: 0.65)
            : AgapColors.businessGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: muted
              ? AgapColors.borderSubtle.withValues(alpha: 0.7)
              : AgapColors.businessGreen.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: muted
                ? AgapColors.textMuted
                : AgapColors.businessGreenDeep,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: muted
                  ? AgapColors.textMuted
                  : AgapColors.businessGreenDeep,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({
    required this.window,
    required this.layerSize,
    required this.cornerRadius,
  });

  final Rect window;
  final Size layerSize;
  final double cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()
      ..addRect(Rect.fromLTWH(0, 0, layerSize.width, layerSize.height));
    final hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          window,
          Radius.circular(cornerRadius),
        ),
      );
    final dim = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(
      dim,
      Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.58),
    );

    final stroke = Paint()
      ..color = AgapColors.businessGreenLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    const inset = 2.0;
    final left = window.left + inset;
    final top = window.top + inset;
    final right = window.right - inset;
    final bottom = window.bottom - inset;
    const arm = 26.0;

    void cornerL(Offset o, {required bool top, required bool left}) {
      final dx = left ? 1.0 : -1.0;
      final dy = top ? 1.0 : -1.0;
      final p = Path()
        ..moveTo(o.dx, o.dy + dy * arm)
        ..lineTo(o.dx, o.dy)
        ..lineTo(o.dx + dx * arm, o.dy);
      canvas.drawPath(p, stroke);
    }

    cornerL(Offset(left, top), top: true, left: true);
    cornerL(Offset(right, top), top: true, left: false);
    cornerL(Offset(left, bottom), top: false, left: true);
    cornerL(Offset(right, bottom), top: false, left: false);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) {
    return oldDelegate.window != window ||
        oldDelegate.layerSize != layerSize ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}

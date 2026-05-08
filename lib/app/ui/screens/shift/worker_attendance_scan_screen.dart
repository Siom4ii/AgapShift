import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../shift/shift_repository.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/success_feedback.dart';

class WorkerAttendanceScanScreen extends StatefulWidget {
  const WorkerAttendanceScanScreen({
    super.key,
    required this.shiftRepo,
    required this.gig,
    required this.workerId,
  });

  final ShiftRepository shiftRepo;
  final Gig gig;
  final String workerId;

  @override
  State<WorkerAttendanceScanScreen> createState() => _WorkerAttendanceScanScreenState();
}

class _WorkerAttendanceScanScreenState extends State<WorkerAttendanceScanScreen> {
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
      final result = await widget.shiftRepo.scanEmployerAttendanceQr(
        qrToken: code,
        workerId: widget.workerId,
      );

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
                          'Scan the employer’s QR code',
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
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFFFFF), Color(0xFFEFF6FF)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AgapColors.borderSubtle.withValues(alpha: 0.85),
                ),
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
                        color: const Color(0xFF2563EB).withValues(alpha: 0.22),
                      ),
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Color(0xFF2563EB),
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
                        Text(
                          widget.gig.addressLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scanRect = _scanWindowRect(constraints.biggest);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _scanner,
                      onDetect: (capture) {
                        final raw = capture.barcodes.isEmpty
                            ? null
                            : capture.barcodes.first.rawValue;
                        _handleRaw(raw);
                      },
                    ),
                    CustomPaint(
                      painter: _ScanWindowPainter(scanRect, _windowRadius),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 14 + bottomInset),
            child: Text(
              'Align the QR inside the box. If it fails, tap back and try again.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AgapColors.textMuted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanWindowPainter extends CustomPainter {
  const _ScanWindowPainter(this.window, this.radius);

  final Rect window;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    // On some Android GPUs, BlendMode.clear doesn't work unless we draw into a layer.
    final layerBounds = Offset.zero & size;
    canvas.saveLayer(layerBounds, Paint());

    final overlay = Paint()
      ..color = const Color(0xFF0B1220).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawRect(layerBounds, overlay);

    final rrect = RRect.fromRectAndRadius(window, Radius.circular(radius));
    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, clear);

    canvas.restore();

    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(rrect, border);
  }

  @override
  bool shouldRepaint(covariant _ScanWindowPainter oldDelegate) {
    return oldDelegate.window != window || oldDelegate.radius != radius;
  }
}


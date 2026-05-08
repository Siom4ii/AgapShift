import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../shift/shift_repository.dart';
import '../../theme/agap_colors.dart';

class EmployerAttendanceQrScreen extends StatefulWidget {
  const EmployerAttendanceQrScreen({
    super.key,
    required this.shiftRepo,
    required this.gig,
    this.initialType,
    this.initialWorkDay,
  });

  final ShiftRepository shiftRepo;
  final Gig gig;
  final AttendanceScanType? initialType;
  final DateTime? initialWorkDay;

  @override
  State<EmployerAttendanceQrScreen> createState() => _EmployerAttendanceQrScreenState();
}

class _EmployerAttendanceQrScreenState extends State<EmployerAttendanceQrScreen> {
  late AttendanceScanType _type;
  late DateTime _workDayLocal;
  String _payload = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? AttendanceScanType.checkIn;
    // Important: The work day is encoded into the QR and controls which day
    // will be marked as checked-in/out. Default to a day that belongs to the gig.
    final days = _gigDays();
    final preferred = widget.initialWorkDay ?? _todayLocal();
    final prefDay = _normalizeLocalDay(preferred);
    final hasPref = days.any((d) => _normalizeLocalDay(d) == prefDay);
    _workDayLocal = hasPref
        ? prefDay
        : (days.isNotEmpty ? _normalizeLocalDay(days.first) : prefDay);
    _regen();
    _refreshTimer = Timer.periodic(const Duration(minutes: 9), (_) {
      if (!mounted) return;
      _regen();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  static DateTime _todayLocal() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _normalizeLocalDay(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  List<DateTime> _gigDays() {
    final s = widget.gig.startAt.toLocal();
    final e = widget.gig.endAt.toLocal();
    var cur = DateTime(s.year, s.month, s.day);
    final end = DateTime(e.year, e.month, e.day);
    final out = <DateTime>[];
    while (!cur.isAfter(end)) {
      out.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return out;
  }

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final l = d.toLocal();
    return '${months[l.month - 1]} ${l.day}';
  }

  void _regen() {
    final token = widget.shiftRepo.createEmployerAttendanceQr(
      gigId: widget.gig.id,
      type: _type,
      workDay: _workDayLocal,
    );
    setState(() => _payload = token);
  }

  @override
  Widget build(BuildContext context) {
    final title = _type == AttendanceScanType.checkIn ? 'Check-in QR' : 'Check-out QR';
    final subtitle = _type == AttendanceScanType.checkIn
        ? 'Workers scan this to clock in'
        : 'Workers scan this to clock out';
    final days = _gigDays();

    return Scaffold(
      backgroundColor: AgapColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AgapColors.pageBackground,
        elevation: 0,
        title: Text(
          'Attendance QR',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AgapColors.businessGreenDeep.withValues(alpha: 0.9),
                      AgapColors.businessGreen.withValues(alpha: 0.75),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AgapColors.businessGreenDeep.withValues(alpha: 0.18),
                      blurRadius: 26,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.gig.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _TypeChip(
                      selected: _type == AttendanceScanType.checkIn,
                      label: 'Check-in',
                      onTap: () {
                        setState(() => _type = AttendanceScanType.checkIn);
                        _regen();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TypeChip(
                      selected: _type == AttendanceScanType.checkOut,
                      label: 'Check-out',
                      onTap: () {
                        setState(() => _type = AttendanceScanType.checkOut);
                        _regen();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (days.length > 1) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AgapColors.borderSubtle),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in days)
                        ChoiceChip(
                          label: Text(_shortDate(d)),
                          selected: _normalizeLocalDay(d) == _normalizeLocalDay(_workDayLocal),
                          onSelected: (_) {
                            setState(() => _workDayLocal = _normalizeLocalDay(d));
                            _regen();
                          },
                          selectedColor: AgapColors.mintSoft,
                          backgroundColor: const Color(0xFFF1F5F9),
                          labelStyle: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: (_normalizeLocalDay(d) == _normalizeLocalDay(_workDayLocal))
                                ? AgapColors.businessGreenDeep
                                : AgapColors.textMuted,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: (_normalizeLocalDay(d) == _normalizeLocalDay(_workDayLocal))
                                  ? AgapColors.businessGreen
                                  : AgapColors.borderSubtle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AgapColors.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: QrImageView(
                              data: _payload,
                              backgroundColor: Colors.white,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _regen,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          'Regenerate',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tip: keep this screen open while workers scan. QR auto-refreshes about every 10 minutes.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AgapColors.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AgapColors.businessGreenDeep : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AgapColors.businessGreenDeep.withValues(alpha: 0.9)
                : AgapColors.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }
}


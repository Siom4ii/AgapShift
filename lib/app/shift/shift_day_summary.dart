import '../../domain/enums.dart';
import '../../domain/models.dart';

/// Groups [AttendanceRecord]s into per-calendar-day check-in / check-out times.
List<ShiftDaySummary> summarizeShiftDays(
  List<AttendanceRecord> rows,
  String workerId,
) {
  final mine = rows.where((a) => a.workerId == workerId).toList();
  final byDay = <String, List<AttendanceRecord>>{};
  for (final a in mine) {
    final d = a.workDay ??
        DateTime(a.scannedAt.year, a.scannedAt.month, a.scannedAt.day);
    final key = _ymd(d);
    byDay.putIfAbsent(key, () => []).add(a);
  }
  final keys = byDay.keys.toList()..sort();
  final out = <ShiftDaySummary>[];
  for (final k in keys) {
    final list = byDay[k]!;
    DateTime? ci;
    DateTime? co;
    for (final a in list) {
      if (a.type == AttendanceScanType.checkIn) {
        if (ci == null || a.scannedAt.isBefore(ci)) ci = a.scannedAt;
      } else {
        if (co == null || a.scannedAt.isAfter(co)) co = a.scannedAt;
      }
    }
    out.add(
      ShiftDaySummary(
        workDay: DateTime.parse('${k}T12:00:00.000Z'),
        checkIn: ci,
        checkOut: co,
      ),
    );
  }
  return out;
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

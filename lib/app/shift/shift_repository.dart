import '../../domain/enums.dart';
import '../../domain/models.dart';

/// Result of the employer scanning a worker attendance QR.
typedef ShiftAttendanceScanResult = ({
  ShiftSession session,
  AttendanceScanType scanType,
});

/// Check-in / check-out and shift session persistence (mock KV or Supabase).
///
/// Employers show a QR; the **worker** scans it to record attendance.
abstract class ShiftRepository {
  /// Signed token for the employer to display (scan type + [workDay]).
  String createEmployerAttendanceQr({
    required String gigId,
    required AttendanceScanType type,
    required DateTime workDay,
  });

  /// Worker scans employer QR, server verifies hired worker + gig status, then records attendance.
  Future<ShiftAttendanceScanResult> scanEmployerAttendanceQr({
    required String qrToken,
    required String workerId,
    DateTime? now,
  });

  /// Signed token for the worker to display (includes [workerId], scan type, [workDay]).
  ///
  /// Deprecated legacy flow (employer scans worker QR). Kept for backward compatibility.
  String createWorkerAttendanceQr({
    required String gigId,
    required String workerId,
    required AttendanceScanType type,
    required DateTime workDay,
  });

  Future<ShiftSession?> getSessionForGig(String gigId);

  Future<List<ShiftSession>> listShiftSessions();

  Future<List<AttendanceRecord>> listAttendanceForGig(String gigId);

  /// Per-day attendance for the hired worker (clock-in / clock-out per calendar day).
  Future<List<ShiftDaySummary>> listWorkDaySummaries({
    required String gigId,
    required String workerId,
  });

  /// Parse [qrToken], verify the gig belongs to [businessId], then record attendance.
  ///
  /// Deprecated legacy flow (employer scans worker QR). Kept for backward compatibility.
  Future<ShiftAttendanceScanResult> scanWorkerAttendanceQr({
    required String qrToken,
    required String businessId,
    DateTime? now,
  });
}

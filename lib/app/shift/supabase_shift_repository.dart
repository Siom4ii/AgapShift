import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import 'qr_tokens.dart';
import 'shift_repository.dart';

/// Postgres-backed shift sessions ([supabase/migrations/012_shift_lifecycle.sql]).
///
/// Inserts [shift_attendance] before upserting [shift_sessions] so RLS still
/// sees the gig as `ongoing` when recording check-out.
///
/// Employers record scans via [scanWorkerAttendanceQr] ([017_shift_attendance_business_scan.sql]).
class SupabaseShiftRepository implements ShiftRepository {
  SupabaseShiftRepository({SupabaseClient? client, QrTokenCodec? codec})
      : _client = client ?? Supabase.instance.client,
        _codec = codec ?? QrTokenCodec(secret: 'dev-secret-change-me');

  final SupabaseClient _client;
  final QrTokenCodec _codec;

  @override
  String createWorkerAttendanceQr({
    required String gigId,
    required String workerId,
    required AttendanceScanType type,
  }) {
    return _codec.createToken(
      gigId: gigId,
      workerId: workerId,
      type: type,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<ShiftSession?> getSessionForGig(String gigId) async {
    final row = await _client
        .from('shift_sessions')
        .select()
        .eq('gig_id', gigId)
        .maybeSingle();
    if (row == null) return null;
    return _sessionFromRow(Map<String, dynamic>.from(row));
  }

  @override
  Future<List<ShiftSession>> listShiftSessions() async {
    final rows = await _client.from('shift_sessions').select();
    final list = rows as List<dynamic>;
    return list
        .map((e) => _sessionFromRow(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<AttendanceRecord>> listAttendanceForGig(String gigId) async {
    final rows = await _client
        .from('shift_attendance')
        .select()
        .eq('gig_id', gigId)
        .order('scanned_at');
    final list = rows as List<dynamic>;
    return list
        .map((e) => _attendanceFromRow(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<ShiftAttendanceScanResult> scanWorkerAttendanceQr({
    required String qrToken,
    required String businessId,
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now().toUtc();
    final parsed = _codec.parseWorkerAttendance(token: qrToken, now: n);
    if (!parsed.ok) throw StateError(parsed.reason!);

    final gigId = parsed.gigId!;
    final workerId = parsed.workerId!;
    final type = parsed.type!;

    final gigRow = await _client
        .from('gigs')
        .select('business_id, hired_worker_id, status')
        .eq('id', gigId)
        .maybeSingle();
    if (gigRow == null) throw StateError('Gig not found');
    if (gigRow['business_id'] != businessId) {
      throw StateError('This QR is not for your job post');
    }
    if (gigRow['hired_worker_id'] != workerId) {
      throw StateError('This worker is not hired on this gig');
    }
    final status = gigRow['status'] as String?;
    if (status != 'filled' && status != 'ongoing') {
      throw StateError('Shift is not active for this gig');
    }

    final attendance = await listAttendanceForGig(gigId);
    final already = attendance.any((a) => a.workerId == workerId && a.type == type);
    if (already) throw StateError('Already scanned ${type.name}');

    final existingBefore = await _client
        .from('shift_sessions')
        .select()
        .eq('gig_id', gigId)
        .eq('worker_id', workerId)
        .maybeSingle();
    if (type == AttendanceScanType.checkOut) {
      final ci = existingBefore == null ? null : existingBefore['check_in_at'];
      if (ci == null) {
        throw StateError('Check in required before check out');
      }
    }

    await _client.from('shift_attendance').insert({
      'gig_id': gigId,
      'worker_id': workerId,
      'scan_type': type.name,
      'scanned_at': n.toUtc().toIso8601String(),
    });

    ShiftSession? existing;
    if (existingBefore != null) {
      existing = _sessionFromRow(Map<String, dynamic>.from(existingBefore));
    }

    final merged = ShiftSession(
      id: existing?.id ?? '',
      gigId: gigId,
      workerId: workerId,
      businessId: businessId,
      checkInAt: type == AttendanceScanType.checkIn ? n : existing?.checkInAt,
      checkOutAt: type == AttendanceScanType.checkOut ? n : existing?.checkOutAt,
    );

    final payload = <String, dynamic>{
      'gig_id': gigId,
      'worker_id': workerId,
      'business_id': businessId,
      'check_in_at': merged.checkInAt?.toUtc().toIso8601String(),
      'check_out_at': merged.checkOutAt?.toUtc().toIso8601String(),
    };

    final row = await _client
        .from('shift_sessions')
        .upsert(payload, onConflict: 'gig_id,worker_id')
        .select()
        .single();

    final session = _sessionFromRow(Map<String, dynamic>.from(row));
    return (session: session, scanType: type);
  }

  ShiftSession _sessionFromRow(Map<String, dynamic> row) {
    return ShiftSession(
      id: row['id'] as String,
      gigId: row['gig_id'] as String,
      workerId: row['worker_id'] as String,
      businessId: row['business_id'] as String,
      checkInAt: row['check_in_at'] == null
          ? null
          : DateTime.parse(row['check_in_at'] as String),
      checkOutAt: row['check_out_at'] == null
          ? null
          : DateTime.parse(row['check_out_at'] as String),
    );
  }

  AttendanceRecord _attendanceFromRow(Map<String, dynamic> row) {
    return AttendanceRecord(
      id: row['id'] as String,
      gigId: row['gig_id'] as String,
      workerId: row['worker_id'] as String,
      type: AttendanceScanType.values
          .firstWhere((e) => e.name == row['scan_type'] as String),
      scannedAt: DateTime.parse(row['scanned_at'] as String),
    );
  }
}

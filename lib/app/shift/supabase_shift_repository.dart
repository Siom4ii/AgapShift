import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import 'qr_tokens.dart';
import 'shift_day_summary.dart';
import 'shift_repository.dart';

/// Postgres-backed shift sessions ([supabase/migrations/012_shift_lifecycle.sql]).
/// Daily attendance: [019_revenue_model_no_escrow_daily_attendance.sql] `work_date`.
class SupabaseShiftRepository implements ShiftRepository {
  SupabaseShiftRepository({SupabaseClient? client, QrTokenCodec? codec})
      : _client = client ?? Supabase.instance.client,
        _codec = codec ?? QrTokenCodec(secret: 'dev-secret-change-me');

  final SupabaseClient _client;
  final QrTokenCodec _codec;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  String createEmployerAttendanceQr({
    required String gigId,
    required AttendanceScanType type,
    required DateTime workDay,
  }) {
    final day = DateTime(workDay.year, workDay.month, workDay.day);
    return _codec.createToken(
      gigId: gigId,
      type: type,
      workDateYmd: _ymd(day),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<ShiftAttendanceScanResult> scanEmployerAttendanceQr({
    required String qrToken,
    required String workerId,
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now().toUtc();
    final parsed = _codec.parseEmployerAttendance(token: qrToken, now: n);
    if (!parsed.ok) throw StateError(parsed.reason!);

    final gigId = parsed.gigId!;
    final type = parsed.type!;
    final workDateYmd = parsed.workDateYmd!;

    final gigRow = await _client
        .from('gigs')
        .select('business_id, hired_worker_id, status')
        .eq('id', gigId)
        .maybeSingle();
    if (gigRow == null) throw StateError('Gig not found');
    if (gigRow['hired_worker_id'] != workerId) {
      throw StateError('You are not hired on this gig');
    }
    final status = gigRow['status'] as String?;
    if (status != 'filled' && status != 'ongoing') {
      throw StateError('Shift is not active for this gig');
    }
    final businessId = gigRow['business_id'] as String? ?? '';

    final attendance = await listAttendanceForGig(gigId);
    bool sameDay(AttendanceRecord a, String ymd) {
      final ad = a.workDay ??
          DateTime(a.scannedAt.year, a.scannedAt.month, a.scannedAt.day);
      return _ymd(ad) == ymd;
    }

    final dup = attendance.any(
      (a) =>
          a.workerId == workerId &&
          a.type == type &&
          sameDay(a, workDateYmd),
    );
    if (dup) throw StateError('Already scanned ${type.name} for this day');

    if (type == AttendanceScanType.checkOut) {
      final hasIn = attendance.any(
        (a) =>
            a.workerId == workerId &&
            a.type == AttendanceScanType.checkIn &&
            sameDay(a, workDateYmd),
      );
      if (!hasIn) {
        throw StateError('Check in for this day before check out');
      }
    }

    await _client.from('shift_attendance').insert({
      'gig_id': gigId,
      'worker_id': workerId,
      'scan_type': type.name,
      'scanned_at': n.toUtc().toIso8601String(),
      'work_date': workDateYmd,
    });

    final allForWorker = await _client
        .from('shift_attendance')
        .select()
        .eq('gig_id', gigId)
        .eq('worker_id', workerId)
        .order('scanned_at');
    final list = allForWorker as List<dynamic>;
    DateTime? minCi;
    DateTime? maxCo;
    for (final e in list) {
      final row = Map<String, dynamic>.from(e as Map);
      final st = row['scan_type'] as String;
      final at = DateTime.parse(row['scanned_at'] as String);
      if (st == AttendanceScanType.checkIn.name) {
        if (minCi == null || at.isBefore(minCi)) minCi = at;
      } else {
        if (maxCo == null || at.isAfter(maxCo)) maxCo = at;
      }
    }

    final payload = <String, dynamic>{
      'gig_id': gigId,
      'worker_id': workerId,
      'business_id': businessId,
      'check_in_at': minCi?.toUtc().toIso8601String(),
      'check_out_at': maxCo?.toUtc().toIso8601String(),
    };

    final row = await _client
        .from('shift_sessions')
        .upsert(payload, onConflict: 'gig_id,worker_id')
        .select()
        .single();

    final session = _sessionFromRow(Map<String, dynamic>.from(row));
    return (session: session, scanType: type);
  }

  @override
  String createWorkerAttendanceQr({
    required String gigId,
    required String workerId,
    required AttendanceScanType type,
    required DateTime workDay,
  }) {
    final day = DateTime(workDay.year, workDay.month, workDay.day);
    return _codec.createToken(
      gigId: gigId,
      workerId: workerId,
      type: type,
      workDateYmd: _ymd(day),
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
  Future<List<ShiftDaySummary>> listWorkDaySummaries({
    required String gigId,
    required String workerId,
  }) async {
    final rows = await listAttendanceForGig(gigId);
    return summarizeShiftDays(rows, workerId);
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
    final workDateYmd = parsed.workDateYmd!;

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
    bool sameDay(AttendanceRecord a, String ymd) {
      final ad = a.workDay ??
          DateTime(a.scannedAt.year, a.scannedAt.month, a.scannedAt.day);
      return _ymd(ad) == ymd;
    }

    final dup = attendance.any(
      (a) =>
          a.workerId == workerId &&
          a.type == type &&
          sameDay(a, workDateYmd),
    );
    if (dup) throw StateError('Already scanned ${type.name} for this day');

    if (type == AttendanceScanType.checkOut) {
      final hasIn = attendance.any(
        (a) =>
            a.workerId == workerId &&
            a.type == AttendanceScanType.checkIn &&
            sameDay(a, workDateYmd),
      );
      if (!hasIn) {
        throw StateError('Check in for this day before check out');
      }
    }

    await _client.from('shift_attendance').insert({
      'gig_id': gigId,
      'worker_id': workerId,
      'scan_type': type.name,
      'scanned_at': n.toUtc().toIso8601String(),
      'work_date': workDateYmd,
    });

    final allForWorker = await _client
        .from('shift_attendance')
        .select()
        .eq('gig_id', gigId)
        .eq('worker_id', workerId)
        .order('scanned_at');
    final list = allForWorker as List<dynamic>;
    DateTime? minCi;
    DateTime? maxCo;
    for (final e in list) {
      final row = Map<String, dynamic>.from(e as Map);
      final st = row['scan_type'] as String;
      final at = DateTime.parse(row['scanned_at'] as String);
      if (st == AttendanceScanType.checkIn.name) {
        if (minCi == null || at.isBefore(minCi)) minCi = at;
      } else {
        if (maxCo == null || at.isAfter(maxCo)) maxCo = at;
      }
    }

    final payload = <String, dynamic>{
      'gig_id': gigId,
      'worker_id': workerId,
      'business_id': businessId,
      'check_in_at': minCi?.toUtc().toIso8601String(),
      'check_out_at': maxCo?.toUtc().toIso8601String(),
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
    final wd = row['work_date'];
    DateTime? workDay;
    if (wd != null) {
      final s = wd.toString();
      if (s.length >= 10) {
        workDay = DateTime.parse('${s.substring(0, 10)}T12:00:00.000Z');
      }
    }
    return AttendanceRecord(
      id: row['id'] as String,
      gigId: row['gig_id'] as String,
      workerId: row['worker_id'] as String,
      type: AttendanceScanType.values
          .firstWhere((e) => e.name == row['scan_type'] as String),
      scannedAt: DateTime.parse(row['scanned_at'] as String),
      workDay: workDay,
    );
  }
}

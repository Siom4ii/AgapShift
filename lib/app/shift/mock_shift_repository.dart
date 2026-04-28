import 'dart:convert';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../storage/kv_store.dart';
import 'qr_tokens.dart';

class MockShiftRepository {
  MockShiftRepository(this._store, {QrTokenCodec? codec})
      : _codec = codec ?? QrTokenCodec(secret: 'dev-secret-change-me');

  final KvStore _store;
  final QrTokenCodec _codec;

  static const _kShiftSessions = 'agapshift.shift.sessions'; // list
  static const _kAttendance = 'agapshift.shift.attendance'; // list

  String createCheckInQr({required String gigId}) {
    return _codec.createToken(
      gigId: gigId,
      type: AttendanceScanType.checkIn,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    );
  }

  String createCheckOutQr({required String gigId}) {
    return _codec.createToken(
      gigId: gigId,
      type: AttendanceScanType.checkOut,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
    );
  }

  Future<ShiftSession?> getSessionForGig(String gigId) async {
    final all = await listShiftSessions();
    for (final s in all) {
      if (s.gigId == gigId) return s;
    }
    return null;
  }

  Future<List<ShiftSession>> listShiftSessions() async {
    final raw = await _store.getString(_kShiftSessions);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => _sessionFromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AttendanceRecord>> listAttendanceForGig(String gigId) async {
    final raw = await _store.getString(_kAttendance);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => _attendanceFromJson(e as Map<String, dynamic>))
        .where((a) => a.gigId == gigId)
        .toList()
      ..sort((a, b) => a.scannedAt.compareTo(b.scannedAt));
  }

  Future<ShiftSession> scanQr({
    required String qrToken,
    required String gigId,
    required String workerId,
    required String businessId,
    required AttendanceScanType type,
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now().toUtc();
    final validation = _codec.validate(token: qrToken, gigId: gigId, type: type, now: n);
    if (!validation.ok) throw StateError(validation.reason!);

    // Prevent duplicate scans.
    final attendance = await listAttendanceForGig(gigId);
    final already = attendance.any((a) => a.workerId == workerId && a.type == type);
    if (already) throw StateError('Already scanned ${type.name}');

    // Create/Update session.
    final sessions = await listShiftSessions();
    final idx = sessions.indexWhere((s) => s.gigId == gigId && s.workerId == workerId);
    final existing = idx >= 0 ? sessions[idx] : null;
    final sessionId = existing?.id ?? 'shift_${DateTime.now().microsecondsSinceEpoch}';
    final updated = ShiftSession(
      id: sessionId,
      gigId: gigId,
      workerId: workerId,
      businessId: businessId,
      checkInAt: type == AttendanceScanType.checkIn ? n : existing?.checkInAt,
      checkOutAt: type == AttendanceScanType.checkOut ? n : existing?.checkOutAt,
    );
    final updatedSessions = [...sessions];
    if (idx >= 0) {
      updatedSessions[idx] = updated;
    } else {
      updatedSessions.add(updated);
    }
    await _saveSessions(updatedSessions);

    // Record attendance event.
    final rawAll = await _store.getString(_kAttendance);
    final all = (rawAll == null || rawAll.isEmpty)
        ? <AttendanceRecord>[]
        : (jsonDecode(rawAll) as List<dynamic>)
            .map((e) => _attendanceFromJson(e as Map<String, dynamic>))
            .toList();
    final att = AttendanceRecord(
      id: 'att_${DateTime.now().microsecondsSinceEpoch}',
      gigId: gigId,
      workerId: workerId,
      type: type,
      scannedAt: n,
    );
    await _saveAttendance([att, ...all]);

    return updated;
  }

  Future<void> _saveSessions(List<ShiftSession> sessions) async {
    await _store.setString(_kShiftSessions, jsonEncode(sessions.map(_sessionToJson).toList()));
  }

  Future<void> _saveAttendance(List<AttendanceRecord> items) async {
    await _store.setString(_kAttendance, jsonEncode(items.map(_attendanceToJson).toList()));
  }

  Map<String, dynamic> _sessionToJson(ShiftSession s) => {
        'id': s.id,
        'gigId': s.gigId,
        'workerId': s.workerId,
        'businessId': s.businessId,
        'checkInAt': s.checkInAt?.toIso8601String(),
        'checkOutAt': s.checkOutAt?.toIso8601String(),
      };

  ShiftSession _sessionFromJson(Map<String, dynamic> j) => ShiftSession(
        id: j['id'] as String,
        gigId: j['gigId'] as String,
        workerId: j['workerId'] as String,
        businessId: j['businessId'] as String,
        checkInAt: j['checkInAt'] == null ? null : DateTime.parse(j['checkInAt'] as String),
        checkOutAt: j['checkOutAt'] == null ? null : DateTime.parse(j['checkOutAt'] as String),
      );

  Map<String, dynamic> _attendanceToJson(AttendanceRecord a) => {
        'id': a.id,
        'gigId': a.gigId,
        'workerId': a.workerId,
        'type': a.type.name,
        'scannedAt': a.scannedAt.toIso8601String(),
      };

  AttendanceRecord _attendanceFromJson(Map<String, dynamic> j) => AttendanceRecord(
        id: j['id'] as String,
        gigId: j['gigId'] as String,
        workerId: j['workerId'] as String,
        type: AttendanceScanType.values.firstWhere((e) => e.name == (j['type'] as String)),
        scannedAt: DateTime.parse(j['scannedAt'] as String),
      );
}


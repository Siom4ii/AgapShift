import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/enums.dart';

class QrTokenCodec {
  QrTokenCodec({required String secret}) : _secret = secret;

  final String _secret;

  /// [workerId] + [workDateYmd] (`yyyy-MM-dd`) for worker-shown QRs (employer scans).
  String createToken({
    required String gigId,
    required AttendanceScanType type,
    required DateTime expiresAt,
    String? workerId,
    String? workDateYmd,
  }) {
    final payload = <String, dynamic>{
      'v': 2,
      'gigId': gigId,
      'type': type.name,
      'exp': expiresAt.toUtc().millisecondsSinceEpoch,
      'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
      if (workerId != null) 'workerId': workerId,
      if (workDateYmd != null) 'workDate': workDateYmd,
    };
    final body = jsonEncode(payload);
    final sig = _hmac(body);
    return '$body.$sig';
  }

  QrTokenValidationResult validate({
    required String token,
    required String gigId,
    required AttendanceScanType type,
    required DateTime now,
  }) {
    final dot = token.lastIndexOf('.');
    if (dot <= 0 || dot == token.length - 1) {
      return const QrTokenValidationResult.invalid('Malformed token');
    }
    final body = token.substring(0, dot);
    final sig = token.substring(dot + 1);
    if (_hmac(body) != sig) {
      return const QrTokenValidationResult.invalid('Invalid signature');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return const QrTokenValidationResult.invalid('Invalid payload');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['gigId'] != gigId) {
      return const QrTokenValidationResult.invalid('Wrong gig');
    }
    if (map['type'] != type.name) {
      return const QrTokenValidationResult.invalid('Wrong scan type');
    }
    final expMs = map['exp'];
    if (expMs is! int) {
      return const QrTokenValidationResult.invalid('Missing exp');
    }
    final exp = DateTime.fromMillisecondsSinceEpoch(expMs, isUtc: true);
    if (now.toUtc().isAfter(exp)) {
      return const QrTokenValidationResult.invalid('Token expired');
    }
    return QrTokenValidationResult.valid(exp);
  }

  /// Parsed worker attendance QR (signed payload includes [workerId]).
  WorkerAttendanceQrParseResult parseWorkerAttendance({
    required String token,
    required DateTime now,
  }) {
    final dot = token.lastIndexOf('.');
    if (dot <= 0 || dot == token.length - 1) {
      return WorkerAttendanceQrParseResult.invalid('Malformed token');
    }
    final body = token.substring(0, dot);
    final sig = token.substring(dot + 1);
    if (_hmac(body) != sig) {
      return WorkerAttendanceQrParseResult.invalid('Invalid signature');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return WorkerAttendanceQrParseResult.invalid('Invalid payload');
    }
    final map = Map<String, dynamic>.from(decoded);
    final wid = map['workerId'];
    if (wid is! String || wid.isEmpty) {
      return WorkerAttendanceQrParseResult.invalid('Not a worker attendance QR');
    }
    final gid = map['gigId'];
    if (gid is! String || gid.isEmpty) {
      return WorkerAttendanceQrParseResult.invalid('Missing gig');
    }
    final typeRaw = map['type'];
    if (typeRaw is! String) {
      return WorkerAttendanceQrParseResult.invalid('Missing scan type');
    }
    final type = switch (typeRaw) {
      'checkIn' => AttendanceScanType.checkIn,
      'checkOut' => AttendanceScanType.checkOut,
      _ => null,
    };
    if (type == null) {
      return WorkerAttendanceQrParseResult.invalid('Invalid scan type');
    }
    final expMs = map['exp'];
    if (expMs is! int) {
      return WorkerAttendanceQrParseResult.invalid('Missing exp');
    }
    final exp = DateTime.fromMillisecondsSinceEpoch(expMs, isUtc: true);
    if (now.toUtc().isAfter(exp)) {
      return WorkerAttendanceQrParseResult.invalid('Token expired');
    }
    final v = map['v'];
    final int? version = v is int ? v : int.tryParse('$v');
    String workDateYmd;
    final rawWd = map['workDate'];
    if (rawWd is String && rawWd.length >= 10) {
      workDateYmd = rawWd.substring(0, 10);
    } else if (version == null || version < 2) {
      workDateYmd = _dateYmdFromUtc(now);
    } else {
      return WorkerAttendanceQrParseResult.invalid('Missing work day');
    }

    return WorkerAttendanceQrParseResult.valid(
      gigId: gid,
      workerId: wid,
      type: type,
      workDateYmd: workDateYmd,
      expiresAt: exp,
    );
  }

  /// Parsed employer attendance QR (signed payload excludes [workerId]).
  /// Worker scans this; worker identity comes from auth/session.
  EmployerAttendanceQrParseResult parseEmployerAttendance({
    required String token,
    required DateTime now,
  }) {
    final dot = token.lastIndexOf('.');
    if (dot <= 0 || dot == token.length - 1) {
      return EmployerAttendanceQrParseResult.invalid('Malformed token');
    }
    final body = token.substring(0, dot);
    final sig = token.substring(dot + 1);
    if (_hmac(body) != sig) {
      return EmployerAttendanceQrParseResult.invalid('Invalid signature');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return EmployerAttendanceQrParseResult.invalid('Invalid payload');
    }
    final map = Map<String, dynamic>.from(decoded);

    // Must NOT be a worker QR (those include workerId).
    final wid = map['workerId'];
    if (wid is String && wid.isNotEmpty) {
      return EmployerAttendanceQrParseResult.invalid('Not an employer attendance QR');
    }

    final gid = map['gigId'];
    if (gid is! String || gid.isEmpty) {
      return EmployerAttendanceQrParseResult.invalid('Missing gig');
    }
    final typeRaw = map['type'];
    if (typeRaw is! String) {
      return EmployerAttendanceQrParseResult.invalid('Missing scan type');
    }
    final type = switch (typeRaw) {
      'checkIn' => AttendanceScanType.checkIn,
      'checkOut' => AttendanceScanType.checkOut,
      _ => null,
    };
    if (type == null) {
      return EmployerAttendanceQrParseResult.invalid('Invalid scan type');
    }
    final expMs = map['exp'];
    if (expMs is! int) {
      return EmployerAttendanceQrParseResult.invalid('Missing exp');
    }
    final exp = DateTime.fromMillisecondsSinceEpoch(expMs, isUtc: true);
    if (now.toUtc().isAfter(exp)) {
      return EmployerAttendanceQrParseResult.invalid('Token expired');
    }
    final rawWd = map['workDate'];
    if (rawWd is! String || rawWd.length < 10) {
      return EmployerAttendanceQrParseResult.invalid('Missing work day');
    }
    final workDateYmd = rawWd.substring(0, 10);

    return EmployerAttendanceQrParseResult.valid(
      gigId: gid,
      type: type,
      workDateYmd: workDateYmd,
      expiresAt: exp,
    );
  }

  static String _dateYmdFromUtc(DateTime t) {
    final u = t.toUtc();
    final y = u.year.toString().padLeft(4, '0');
    final m = u.month.toString().padLeft(2, '0');
    final d = u.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _hmac(String body) {
    final key = utf8.encode(_secret);
    final bytes = utf8.encode(body);
    return Hmac(sha256, key).convert(bytes).toString();
  }
}

class QrTokenValidationResult {
  const QrTokenValidationResult._(this.ok, this.reason, this.expiresAt);

  const QrTokenValidationResult.valid(DateTime expiresAt) : this._(true, null, expiresAt);
  const QrTokenValidationResult.invalid(String reason) : this._(false, reason, null);

  final bool ok;
  final String? reason;
  final DateTime? expiresAt;
}

class WorkerAttendanceQrParseResult {
  const WorkerAttendanceQrParseResult._({
    required this.ok,
    this.reason,
    this.gigId,
    this.workerId,
    this.type,
    this.workDateYmd,
    this.expiresAt,
  });

  const WorkerAttendanceQrParseResult.invalid(String reason)
      : this._(ok: false, reason: reason);

  factory WorkerAttendanceQrParseResult.valid({
    required String gigId,
    required String workerId,
    required AttendanceScanType type,
    required String workDateYmd,
    required DateTime expiresAt,
  }) {
    return WorkerAttendanceQrParseResult._(
      ok: true,
      gigId: gigId,
      workerId: workerId,
      type: type,
      workDateYmd: workDateYmd,
      expiresAt: expiresAt,
    );
  }

  final bool ok;
  final String? reason;
  final String? gigId;
  final String? workerId;
  final AttendanceScanType? type;
  final String? workDateYmd;
  final DateTime? expiresAt;
}

class EmployerAttendanceQrParseResult {
  const EmployerAttendanceQrParseResult._({
    required this.ok,
    this.reason,
    this.gigId,
    this.type,
    this.workDateYmd,
    this.expiresAt,
  });

  const EmployerAttendanceQrParseResult.invalid(String reason)
      : this._(ok: false, reason: reason);

  factory EmployerAttendanceQrParseResult.valid({
    required String gigId,
    required AttendanceScanType type,
    required String workDateYmd,
    required DateTime expiresAt,
  }) {
    return EmployerAttendanceQrParseResult._(
      ok: true,
      gigId: gigId,
      type: type,
      workDateYmd: workDateYmd,
      expiresAt: expiresAt,
    );
  }

  final bool ok;
  final String? reason;
  final String? gigId;
  final AttendanceScanType? type;
  final String? workDateYmd;
  final DateTime? expiresAt;
}


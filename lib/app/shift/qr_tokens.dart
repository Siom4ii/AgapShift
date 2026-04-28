import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/enums.dart';

class QrTokenCodec {
  QrTokenCodec({required String secret}) : _secret = secret;

  final String _secret;

  String createToken({
    required String gigId,
    required AttendanceScanType type,
    required DateTime expiresAt,
  }) {
    final payload = <String, dynamic>{
      'v': 1,
      'gigId': gigId,
      'type': type.name,
      'exp': expiresAt.toUtc().millisecondsSinceEpoch,
      'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
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
    final map = Map<String, dynamic>.from(decoded as Map);
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


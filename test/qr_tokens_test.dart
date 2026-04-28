import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/shift/qr_tokens.dart';
import 'package:nexora/domain/enums.dart';

void main() {
  test('QR token validates and expires', () {
    final codec = QrTokenCodec(secret: 's');
    final now = DateTime.utc(2026, 5, 1, 9, 0, 0);
    final token = codec.createToken(
      gigId: 'gig_1',
      type: AttendanceScanType.checkIn,
      expiresAt: now.add(const Duration(minutes: 1)),
    );

    final ok = codec.validate(
      token: token,
      gigId: 'gig_1',
      type: AttendanceScanType.checkIn,
      now: now,
    );
    expect(ok.ok, true);

    final expired = codec.validate(
      token: token,
      gigId: 'gig_1',
      type: AttendanceScanType.checkIn,
      now: now.add(const Duration(minutes: 2)),
    );
    expect(expired.ok, false);
  });
}


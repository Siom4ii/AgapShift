import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/payments/mock_payments_repository.dart';
import 'package:nexora/app/payments/stub_payments_repository.dart';
import 'package:nexora/app/storage/memory_kv_store.dart';

void main() {
  test('MockPaymentsRepository returns zero wallet and empty ledger', () async {
    final store = MemoryKvStore();
    final payments = MockPaymentsRepository(store);

    final w = await payments.getWallet('u1');
    expect(w.available.amount, 0);
    expect(w.pending.amount, 0);

    final ledger = await payments.listLedger('u1');
    expect(ledger, isEmpty);

    final payouts = await payments.listPayouts('u1');
    expect(payouts, isEmpty);
  });

  test('StubPaymentsRepository matches mock balances (Supabase path)', () async {
    final stub = StubPaymentsRepository();
    final w = await stub.getWallet('u1');
    expect(w.available.amount, 0);
    expect(await stub.listLedger('u1'), isEmpty);
    expect(await stub.listPayouts('u1'), isEmpty);
  });
}

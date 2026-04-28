import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/payments/mock_payments_repository.dart';
import 'package:nexora/app/storage/memory_kv_store.dart';
import 'package:nexora/domain/models.dart';

void main() {
  test('Escrow fund + release credits worker wallet and withdrawal debits', () async {
    final store = MemoryKvStore();
    final payments = MockPaymentsRepository(store);

    await payments.fundEscrow(gigId: 'gig1', businessId: 'biz1', amount: const Money(amount: 80000));
    await payments.releaseEscrowToWorker(gigId: 'gig1', workerId: 'w1');

    final w = await payments.getWallet('w1');
    expect(w.available.amount, 80000);

    await payments.requestWithdrawal(userId: 'w1', amount: const Money(amount: 50000));
    final w2 = await payments.getWallet('w1');
    expect(w2.available.amount, 30000);
  });
}


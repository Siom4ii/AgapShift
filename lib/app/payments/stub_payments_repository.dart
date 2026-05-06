import '../../domain/models.dart';
import 'payments_repository.dart';

/// No escrow / no ledger persistence — revenue features use separate flows later.
class StubPaymentsRepository implements PaymentsRepository {
  @override
  Future<Wallet> getWallet(String userId) async {
    return Wallet(
      userId: userId,
      available: const Money(amount: 0),
      pending: const Money(amount: 0),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<List<LedgerTransaction>> listLedger(String userId) async => const [];

  @override
  Future<List<Payout>> listPayouts(String userId) async => const [];
}

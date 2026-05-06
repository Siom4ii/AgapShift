import '../../domain/models.dart';

/// In-app ledger removed: salaries are paid off-app. Wallet UI shows informational balances only.
abstract interface class PaymentsRepository {
  Future<Wallet> getWallet(String userId);

  Future<List<LedgerTransaction>> listLedger(String userId);

  Future<List<Payout>> listPayouts(String userId);
}

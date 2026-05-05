import '../../domain/models.dart';

abstract interface class PaymentsRepository {
  Future<Wallet> getWallet(String userId);

  Future<List<LedgerTransaction>> listLedger(String userId);

  Future<List<Payout>> listPayouts(String userId);

  Future<Escrow?> getEscrowForGig(String gigId);

  Future<bool> isEscrowFunded(String gigId);

  Future<Escrow> fundEscrow({
    required String gigId,
    required String businessId,
    required Money amount,
  });

  Future<Escrow> holdEscrow({required String gigId});

  Future<Escrow> releaseEscrowToWorker({
    required String gigId,
    required String workerId,
  });

  Future<Escrow> refundEscrow({
    required String gigId,
    required String businessId,
  });

  Future<Payout> requestWithdrawal({
    required String userId,
    required Money amount,
  });
}

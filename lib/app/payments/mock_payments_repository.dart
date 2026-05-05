import 'dart:convert';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../storage/kv_store.dart';
import 'payments_repository.dart';

class MockPaymentsRepository implements PaymentsRepository {
  MockPaymentsRepository(this._store);

  final KvStore _store;

  static const _kWallets = 'agapshift.payments.wallets'; // userId -> wallet json
  static const _kEscrows = 'agapshift.payments.escrows'; // gigId -> escrow json
  static const _kLedger = 'agapshift.payments.ledger'; // list
  static const _kPayouts = 'agapshift.payments.payouts'; // list

  @override
  Future<Wallet> getWallet(String userId) async {
    final wallets = await _loadWallets();
    return wallets[userId] ??
        Wallet(
          userId: userId,
          available: const Money(amount: 0),
          pending: const Money(amount: 0),
          updatedAt: DateTime.now().toUtc(),
        );
  }

  @override
  Future<List<LedgerTransaction>> listLedger(String userId) async {
    final all = await _loadLedger();
    return all.where((t) => t.userId == userId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<Payout>> listPayouts(String userId) async {
    final all = await _loadPayouts();
    return all.where((p) => p.userId == userId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<Escrow?> getEscrowForGig(String gigId) async {
    final escrows = await _loadEscrows();
    return escrows[gigId];
  }

  @override
  Future<bool> isEscrowFunded(String gigId) async {
    final e = await getEscrowForGig(gigId);
    if (e == null) return false;
    return e.status == EscrowStatus.funded || e.status == EscrowStatus.held;
  }

  @override
  Future<Escrow> fundEscrow({
    required String gigId,
    required String businessId,
    required Money amount,
  }) async {
    final escrows = await _loadEscrows();
    final now = DateTime.now().toUtc();
    final existing = escrows[gigId];
    if (existing != null && existing.status != EscrowStatus.refunded) {
      return existing;
    }

    final escrow = Escrow(
      id: 'esc_${now.microsecondsSinceEpoch}',
      gigId: gigId,
      amount: amount,
      status: EscrowStatus.funded,
      updatedAt: now,
    );
    escrows[gigId] = escrow;
    await _saveEscrows(escrows);

    await _appendLedger(
      LedgerTransaction(
        id: 'txn_${now.microsecondsSinceEpoch}',
        userId: businessId,
        type: TransactionType.escrowFunding,
        amount: Money(amount: amount.amount, currency: amount.currency),
        createdAt: now,
        gigId: gigId,
      ),
    );

    return escrow;
  }

  @override
  Future<Escrow> holdEscrow({required String gigId}) async {
    final escrows = await _loadEscrows();
    final existing = escrows[gigId];
    if (existing == null) throw StateError('Escrow not funded');
    if (existing.status == EscrowStatus.held) return existing;
    final updated = Escrow(
      id: existing.id,
      gigId: existing.gigId,
      amount: existing.amount,
      status: EscrowStatus.held,
      updatedAt: DateTime.now().toUtc(),
    );
    escrows[gigId] = updated;
    await _saveEscrows(escrows);
    return updated;
  }

  @override
  Future<Escrow> releaseEscrowToWorker({
    required String gigId,
    required String workerId,
  }) async {
    final escrows = await _loadEscrows();
    final existing = escrows[gigId];
    if (existing == null) throw StateError('No escrow for gig');
    if (existing.status == EscrowStatus.released) return existing;
    if (existing.status != EscrowStatus.funded && existing.status != EscrowStatus.held) {
      throw StateError('Escrow not releasable');
    }

    final now = DateTime.now().toUtc();
    final updated = Escrow(
      id: existing.id,
      gigId: existing.gigId,
      amount: existing.amount,
      status: EscrowStatus.released,
      updatedAt: now,
    );
    escrows[gigId] = updated;
    await _saveEscrows(escrows);

    // Credit worker wallet (available for MVP).
    await _creditWallet(workerId, existing.amount);
    await _appendLedger(
      LedgerTransaction(
        id: 'txn_${now.microsecondsSinceEpoch}',
        userId: workerId,
        type: TransactionType.escrowRelease,
        amount: existing.amount,
        createdAt: now,
        gigId: gigId,
      ),
    );

    return updated;
  }

  @override
  Future<Escrow> refundEscrow({
    required String gigId,
    required String businessId,
  }) async {
    final escrows = await _loadEscrows();
    final existing = escrows[gigId];
    if (existing == null) throw StateError('No escrow to refund');
    if (existing.status == EscrowStatus.refunded) return existing;
    if (existing.status == EscrowStatus.released) throw StateError('Cannot refund released escrow');

    final now = DateTime.now().toUtc();
    final updated = Escrow(
      id: existing.id,
      gigId: existing.gigId,
      amount: existing.amount,
      status: EscrowStatus.refunded,
      updatedAt: now,
    );
    escrows[gigId] = updated;
    await _saveEscrows(escrows);

    await _appendLedger(
      LedgerTransaction(
        id: 'txn_${now.microsecondsSinceEpoch}',
        userId: businessId,
        type: TransactionType.escrowRefund,
        amount: existing.amount,
        createdAt: now,
        gigId: gigId,
      ),
    );
    return updated;
  }

  @override
  Future<Payout> requestWithdrawal({
    required String userId,
    required Money amount,
  }) async {
    final wallet = await getWallet(userId);
    if (wallet.available.amount < amount.amount) {
      throw StateError('Insufficient available balance');
    }
    final now = DateTime.now().toUtc();
    await _debitWallet(userId, amount);
    final payout = Payout(
      id: 'po_${now.microsecondsSinceEpoch}',
      userId: userId,
      amount: amount,
      status: PayoutStatus.requested,
      createdAt: now,
    );
    final payouts = await _loadPayouts();
    payouts.add(payout);
    await _savePayouts(payouts);

    await _appendLedger(
      LedgerTransaction(
        id: 'txn_${now.microsecondsSinceEpoch}',
        userId: userId,
        type: TransactionType.withdrawalDebit,
        amount: Money(amount: amount.amount, currency: amount.currency),
        createdAt: now,
        gigId: null,
      ),
    );
    return payout;
  }

  Future<void> _creditWallet(String userId, Money amount) async {
    final wallets = await _loadWallets();
    final current = wallets[userId] ??
        Wallet(
          userId: userId,
          available: const Money(amount: 0),
          pending: const Money(amount: 0),
          updatedAt: DateTime.now().toUtc(),
        );
    final updated = Wallet(
      userId: userId,
      available: Money(amount: current.available.amount + amount.amount, currency: amount.currency),
      pending: current.pending,
      updatedAt: DateTime.now().toUtc(),
    );
    wallets[userId] = updated;
    await _saveWallets(wallets);
  }

  Future<void> _debitWallet(String userId, Money amount) async {
    final wallets = await _loadWallets();
    final current = wallets[userId] ??
        Wallet(
          userId: userId,
          available: const Money(amount: 0),
          pending: const Money(amount: 0),
          updatedAt: DateTime.now().toUtc(),
        );
    final newAvailable = current.available.amount - amount.amount;
    if (newAvailable < 0) throw StateError('Negative balance');
    final updated = Wallet(
      userId: userId,
      available: Money(amount: newAvailable, currency: amount.currency),
      pending: current.pending,
      updatedAt: DateTime.now().toUtc(),
    );
    wallets[userId] = updated;
    await _saveWallets(wallets);
  }

  Future<Map<String, Wallet>> _loadWallets() async {
    final raw = await _store.getString(_kWallets);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, _walletFromJson(Map<String, dynamic>.from(v as Map))));
  }

  Future<void> _saveWallets(Map<String, Wallet> wallets) async {
    final encoded = wallets.map((k, v) => MapEntry(k, _walletToJson(v)));
    await _store.setString(_kWallets, jsonEncode(encoded));
  }

  Future<Map<String, Escrow>> _loadEscrows() async {
    final raw = await _store.getString(_kEscrows);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, _escrowFromJson(Map<String, dynamic>.from(v as Map))));
  }

  Future<void> _saveEscrows(Map<String, Escrow> escrows) async {
    final encoded = escrows.map((k, v) => MapEntry(k, _escrowToJson(v)));
    await _store.setString(_kEscrows, jsonEncode(encoded));
  }

  Future<List<LedgerTransaction>> _loadLedger() async {
    final raw = await _store.getString(_kLedger);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => _ledgerFromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _appendLedger(LedgerTransaction txn) async {
    final all = await _loadLedger();
    all.add(txn);
    await _store.setString(_kLedger, jsonEncode(all.map(_ledgerToJson).toList()));
  }

  Future<List<Payout>> _loadPayouts() async {
    final raw = await _store.getString(_kPayouts);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => _payoutFromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _savePayouts(List<Payout> payouts) async {
    await _store.setString(_kPayouts, jsonEncode(payouts.map(_payoutToJson).toList()));
  }

  Map<String, dynamic> _walletToJson(Wallet w) => {
        'userId': w.userId,
        'available': {'amount': w.available.amount, 'currency': w.available.currency},
        'pending': {'amount': w.pending.amount, 'currency': w.pending.currency},
        'updatedAt': w.updatedAt.toIso8601String(),
      };

  Wallet _walletFromJson(Map<String, dynamic> j) => Wallet(
        userId: j['userId'] as String,
        available: Money(
          amount: j['available']['amount'] as int,
          currency: j['available']['currency'] as String,
        ),
        pending: Money(
          amount: j['pending']['amount'] as int,
          currency: j['pending']['currency'] as String,
        ),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  Map<String, dynamic> _escrowToJson(Escrow e) => {
        'id': e.id,
        'gigId': e.gigId,
        'amount': {'amount': e.amount.amount, 'currency': e.amount.currency},
        'status': e.status.name,
        'updatedAt': e.updatedAt.toIso8601String(),
      };

  Escrow _escrowFromJson(Map<String, dynamic> j) => Escrow(
        id: j['id'] as String,
        gigId: j['gigId'] as String,
        amount: Money(
          amount: j['amount']['amount'] as int,
          currency: j['amount']['currency'] as String,
        ),
        status: EscrowStatus.values.firstWhere((e) => e.name == (j['status'] as String)),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
      );

  Map<String, dynamic> _ledgerToJson(LedgerTransaction t) => {
        'id': t.id,
        'userId': t.userId,
        'type': t.type.name,
        'amount': {'amount': t.amount.amount, 'currency': t.amount.currency},
        'createdAt': t.createdAt.toIso8601String(),
        'gigId': t.gigId,
      };

  LedgerTransaction _ledgerFromJson(Map<String, dynamic> j) => LedgerTransaction(
        id: j['id'] as String,
        userId: j['userId'] as String,
        type: TransactionType.values.firstWhere((e) => e.name == (j['type'] as String)),
        amount: Money(
          amount: j['amount']['amount'] as int,
          currency: j['amount']['currency'] as String,
        ),
        createdAt: DateTime.parse(j['createdAt'] as String),
        gigId: j['gigId'] as String?,
      );

  Map<String, dynamic> _payoutToJson(Payout p) => {
        'id': p.id,
        'userId': p.userId,
        'amount': {'amount': p.amount.amount, 'currency': p.amount.currency},
        'status': p.status.name,
        'createdAt': p.createdAt.toIso8601String(),
      };

  Payout _payoutFromJson(Map<String, dynamic> j) => Payout(
        id: j['id'] as String,
        userId: j['userId'] as String,
        amount: Money(
          amount: j['amount']['amount'] as int,
          currency: j['amount']['currency'] as String,
        ),
        status: PayoutStatus.values.firstWhere((e) => e.name == (j['status'] as String)),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}


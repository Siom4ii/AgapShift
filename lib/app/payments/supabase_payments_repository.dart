import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import 'payments_repository.dart';

/// Postgres-backed wallets + escrow ([supabase/migrations/018_wallet_escrow.sql]).
class SupabasePaymentsRepository implements PaymentsRepository {
  SupabasePaymentsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  void _requireSelf(String userId) {
    final me = _client.auth.currentUser?.id;
    if (me == null || me != userId) {
      throw StateError('Not authorized for this wallet');
    }
  }

  @override
  Future<Wallet> getWallet(String userId) async {
    _requireSelf(userId);
    final row = await _client
        .from('wallets')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) {
      return Wallet(
        userId: userId,
        available: const Money(amount: 0),
        pending: const Money(amount: 0),
        updatedAt: DateTime.now().toUtc(),
      );
    }
    return _walletFromRow(Map<String, dynamic>.from(row));
  }

  @override
  Future<List<LedgerTransaction>> listLedger(String userId) async {
    _requireSelf(userId);
    final rows = await _client
        .from('ledger_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    final list = rows as List<dynamic>;
    return list
        .map((e) => _ledgerFromRow(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<Payout>> listPayouts(String userId) async {
    _requireSelf(userId);
    final rows = await _client
        .from('payouts')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    final list = rows as List<dynamic>;
    return list
        .map((e) => _payoutFromRow(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<Escrow?> getEscrowForGig(String gigId) async {
    final row = await _client
        .from('escrows')
        .select()
        .eq('gig_id', gigId)
        .maybeSingle();
    if (row == null) return null;
    return _escrowFromRow(Map<String, dynamic>.from(row));
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
    _requireSelf(businessId);
    await _client.rpc<void>('payments_fund_escrow', params: {'p_gig_id': gigId});
    final e = await getEscrowForGig(gigId);
    if (e == null) throw StateError('Escrow not created');
    return e;
  }

  @override
  Future<Escrow> holdEscrow({required String gigId}) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw StateError('Not signed in');
    await _client.rpc<void>('payments_hold_escrow', params: {'p_gig_id': gigId});
    final e = await getEscrowForGig(gigId);
    if (e == null) throw StateError('Escrow not found');
    return e;
  }

  @override
  Future<Escrow> releaseEscrowToWorker({
    required String gigId,
    required String workerId,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw StateError('Not signed in');
    if (me != workerId && me != (await _gigBusinessId(gigId))) {
      throw StateError('Not authorized to release this escrow');
    }
    await _client.rpc<void>('payments_release_escrow', params: {'p_gig_id': gigId});
    final e = await getEscrowForGig(gigId);
    if (e == null) throw StateError('Escrow not found');
    return e;
  }

  @override
  Future<Escrow> refundEscrow({
    required String gigId,
    required String businessId,
  }) async {
    _requireSelf(businessId);
    await _client.rpc<void>('payments_refund_escrow', params: {'p_gig_id': gigId});
    final e = await getEscrowForGig(gigId);
    if (e == null) throw StateError('Escrow not found');
    return e;
  }

  @override
  Future<Payout> requestWithdrawal({
    required String userId,
    required Money amount,
  }) async {
    _requireSelf(userId);
    await _client.rpc<void>(
      'payments_request_payout',
      params: <String, dynamic>{
        'p_amount_cents': amount.amount,
        'p_currency': amount.currency,
      },
    );
    final rows = await _client
        .from('payouts')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1);
    final list = rows as List<dynamic>;
    if (list.isEmpty) throw StateError('Payout not recorded');
    return _payoutFromRow(Map<String, dynamic>.from(list.first as Map));
  }

  Future<String?> _gigBusinessId(String gigId) async {
    final row = await _client
        .from('gigs')
        .select('business_id')
        .eq('id', gigId)
        .maybeSingle();
    if (row == null) return null;
    return row['business_id'] as String?;
  }

  static Wallet _walletFromRow(Map<String, dynamic> row) {
    final cur = row['currency'] as String? ?? 'PHP';
    return Wallet(
      userId: row['user_id'] as String,
      available: Money(
        amount: row['available_amount'] as int,
        currency: cur,
      ),
      pending: Money(
        amount: row['pending_amount'] as int,
        currency: cur,
      ),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  static Escrow _escrowFromRow(Map<String, dynamic> row) {
    final cur = row['currency'] as String? ?? 'PHP';
    return Escrow(
      id: row['id'] as String,
      gigId: row['gig_id'] as String,
      amount: Money(
        amount: row['amount'] as int,
        currency: cur,
      ),
      status: EscrowStatus.values.firstWhere((e) => e.name == row['status']),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  static LedgerTransaction _ledgerFromRow(Map<String, dynamic> row) {
    final cur = row['currency'] as String? ?? 'PHP';
    return LedgerTransaction(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      type: TransactionType.values.firstWhere((e) => e.name == row['type']),
      amount: Money(amount: row['amount'] as int, currency: cur),
      createdAt: DateTime.parse(row['created_at'] as String),
      gigId: row['gig_id'] as String?,
    );
  }

  static Payout _payoutFromRow(Map<String, dynamic> row) {
    final cur = row['currency'] as String? ?? 'PHP';
    return Payout(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      amount: Money(amount: row['amount'] as int, currency: cur),
      status: PayoutStatus.values.firstWhere((e) => e.name == row['status']),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

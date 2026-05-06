import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';

/// In-app payment stubs until a gateway (e.g. PayMongo, Stripe) is wired.
/// Updates entitlement tables from [019] / [024].
abstract final class RevenueStubService {
  static const verificationFeeValidity = Duration(days: 365);
  static const workerSubscriptionValidity = Duration(days: 30);
  static const postBoostValidity = Duration(days: 7);

  /// Employer: unlocks 2nd+ job posts (verification & security).
  static Future<void> payEmployerVerificationFee(String businessId) async {
    if (!SupabaseConfig.isConfigured || businessId.isEmpty) return;
    final until = DateTime.now().toUtc().add(verificationFeeValidity);
    final now = DateTime.now().toUtc().toIso8601String();
    final client = Supabase.instance.client;
    try {
      final existing = await client
          .from('employer_entitlements')
          .select('business_id')
          .eq('business_id', businessId)
          .maybeSingle();
      if (existing != null) {
        await client.from('employer_entitlements').update({
          'verification_fee_paid_until': until.toIso8601String(),
          'updated_at': now,
        }).eq('business_id', businessId);
      } else {
        await client.from('employer_entitlements').insert({
          'business_id': businessId,
          'jobs_posted_count': 0,
          'verification_fee_paid_until': until.toIso8601String(),
          'updated_at': now,
        });
      }
    } catch (_) {}
  }

  /// Worker: multiple / continuous applications and concurrent shifts.
  static Future<void> payWorkerSubscription(String workerId) async {
    if (!SupabaseConfig.isConfigured || workerId.isEmpty) return;
    final until = DateTime.now().toUtc().add(workerSubscriptionValidity);
    final client = Supabase.instance.client;
    try {
      await client.from('worker_entitlements').upsert({
        'user_id': workerId,
        'subscription_expires_at': until.toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Optional: boost end time for a new gig (caller passes into [createGig]).
  static DateTime boostedUntilNow() {
    return DateTime.now().toUtc().add(postBoostValidity);
  }
}

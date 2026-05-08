import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';

/// In-app payment stubs until a gateway (e.g. PayMongo, Stripe) is wired.
///
/// Product copy: worker ₱99/mo, employer ₱149/mo, post boost ₱49 / 3 days.
abstract final class RevenueStubService {
  /// Shown in UI; not charged until a gateway exists.
  static const int workerSubscriptionPhp = 99;
  static const int employerSubscriptionPhp = 149;
  static const int postBoostPhp = 49;

  static const Duration workerSubscriptionValidity = Duration(days: 30);
  static const Duration employerSubscriptionValidity = Duration(days: 30);
  static const Duration postBoostValidity = Duration(days: 3);

  static DateTime _extendedExpiryUtc({
    required DateTime nowUtc,
    DateTime? currentEndUtc,
    required Duration add,
  }) {
    final base = currentEndUtc != null && currentEndUtc.isAfter(nowUtc)
        ? currentEndUtc
        : nowUtc;
    return base.add(add);
  }

  /// Employer: unlimited posts & hires while active (from 2nd listing onward).
  static Future<void> payEmployerSubscription(String businessId) async {
    if (!SupabaseConfig.isConfigured || businessId.isEmpty) return;
    final nowUtc = DateTime.now().toUtc();
    final nowStr = nowUtc.toIso8601String();
    final client = Supabase.instance.client;
    try {
      final row = await client
          .from('employer_entitlements')
          .select('subscription_expires_at')
          .eq('business_id', businessId)
          .maybeSingle();
      DateTime? cur;
      final raw = row?['subscription_expires_at'];
      if (raw != null) {
        cur = DateTime.parse(raw as String);
      }
      final until = _extendedExpiryUtc(
        nowUtc: nowUtc,
        currentEndUtc: cur,
        add: employerSubscriptionValidity,
      );
      final untilStr = until.toIso8601String();
      if (row != null) {
        await client.from('employer_entitlements').update({
          'subscription_expires_at': untilStr,
          'updated_at': nowStr,
        }).eq('business_id', businessId);
      } else {
        await client.from('employer_entitlements').insert({
          'business_id': businessId,
          'jobs_posted_count': 0,
          'subscription_expires_at': untilStr,
          'updated_at': nowStr,
        });
      }
    } catch (_) {}
  }

  /// Worker: continuous applies, concurrent shifts, after free tier.
  static Future<void> payWorkerSubscription(String workerId) async {
    if (!SupabaseConfig.isConfigured || workerId.isEmpty) return;
    final nowUtc = DateTime.now().toUtc();
    final client = Supabase.instance.client;
    try {
      final row = await client
          .from('worker_entitlements')
          .select('subscription_expires_at')
          .eq('user_id', workerId)
          .maybeSingle();
      DateTime? cur;
      final raw = row?['subscription_expires_at'];
      if (raw != null) {
        cur = DateTime.parse(raw as String);
      }
      final until = _extendedExpiryUtc(
        nowUtc: nowUtc,
        currentEndUtc: cur,
        add: workerSubscriptionValidity,
      );
      await client.from('worker_entitlements').upsert({
        'user_id': workerId,
        'subscription_expires_at': until.toIso8601String(),
        'updated_at': nowUtc.toIso8601String(),
      });
    } catch (_) {}
  }

  /// Boost end time for a new gig (caller passes into [createGig]).
  static DateTime boostedUntilNow() {
    return DateTime.now().toUtc().add(postBoostValidity);
  }
}

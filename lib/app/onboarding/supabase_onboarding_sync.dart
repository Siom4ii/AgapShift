import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';

/// Persists worker/business onboarding answers to
/// [worker_onboarding_responses] / [business_onboarding_responses].
///
/// Call only when the user **finishes** registration (final submit). Partial
/// wizard progress is not written to the database.
///
/// **Passwords:** Never put passwords in [payload] or snapshots. Login secrets
/// live only in `auth.users` as hashes (managed by Supabase Auth).
abstract final class SupabaseOnboardingSync {
  /// Writes a denormalized snapshot to [profiles.identity_snapshot] so one row
  /// per user holds the same structured data as the final onboarding payload
  /// (still no passwords). Call only on final submit.
  static Future<void> syncProfileIdentitySnapshot({
    required String flow,
    required Map<String, dynamic> snapshot,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final wrapped = <String, dynamic>{
        'flow': flow,
        'captured_at': DateTime.now().toUtc().toIso8601String(),
        'data': snapshot,
      };
      await client.from('profiles').update({
        'identity_snapshot': wrapped,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (_) {}
  }

  /// Final submission only — sets [submitted_at] and replaces [payload].
  static Future<void> saveWorker(Map<String, dynamic> payload) async {
    await _saveFinal(
      table: 'worker_onboarding_responses',
      payload: payload,
    );
  }

  /// Final submission only — sets [submitted_at] and replaces [payload].
  static Future<void> saveBusiness(Map<String, dynamic> payload) async {
    await _saveFinal(
      table: 'business_onboarding_responses',
      payload: payload,
    );
  }

  static Future<void> _saveFinal({
    required String table,
    required Map<String, dynamic> payload,
  }) async {
    if (!SupabaseConfig.isConfigured) return;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await client.from(table).upsert(<String, dynamic>{
        'user_id': uid,
        'payload': payload,
        'updated_at': now,
        'submitted_at': now,
      });
    } catch (_) {}
  }
}

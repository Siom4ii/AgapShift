import 'package:supabase_flutter/supabase_flutter.dart';

import '../session/app_actor_id.dart';
import '../session/session_controller.dart';
import '../shift/shift_repository.dart';
import '../supabase/supabase_config.dart';

/// Enforces one active shift and post-completion apply rules ([019] subscription hook).
class WorkerApplyGuard {
  WorkerApplyGuard._();

  /// `null` if the worker may apply; otherwise a user-facing reason.
  static Future<String?> blockingReason({
    required ShiftRepository shiftRepo,
    required SessionController session,
  }) async {
    if (!SupabaseConfig.isConfigured) return null;

    final workerId = appActorId(session, mockFallback: '');
    if (workerId.isEmpty) return null;

    final sessions = await shiftRepo.listShiftSessions();
    final mine = sessions.where((s) => s.workerId == workerId);
    final activeCount = mine.where((s) => s.checkOutAt == null).length;
    final hasCompleted = mine.any((s) => s.checkOutAt != null);

    final sub = await _subscriptionActive(workerId);
    if (sub) return null;

    if (activeCount >= 1) {
      return 'You already have an active shift. Finish it before applying elsewhere, '
          'or subscribe to hold multiple shifts at once.';
    }
    if (hasCompleted) {
      return 'Subscribe to apply for more shifts after completing a job.';
    }
    return null;
  }

  static Future<bool> _subscriptionActive(String workerId) async {
    try {
      final row = await Supabase.instance.client
          .from('worker_entitlements')
          .select('subscription_expires_at')
          .eq('user_id', workerId)
          .maybeSingle();
      if (row == null) return false;
      final exp = row['subscription_expires_at'];
      if (exp == null) return false;
      return DateTime.parse(exp as String).isAfter(DateTime.now().toUtc());
    } catch (_) {
      return false;
    }
  }
}

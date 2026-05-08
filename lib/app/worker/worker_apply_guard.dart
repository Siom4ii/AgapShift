import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/enums.dart';
import '../session/app_actor_id.dart';
import '../session/session_controller.dart';
import '../shift/shift_repository.dart';
import '../subscriptions/revenue_stub_service.dart';
import '../supabase/supabase_config.dart';

/// Enforces worker free tier vs paid subscription ([019] + revenue model).
///
/// Free tier: one active shift, no simultaneous pending/hired applications on
/// other gigs, no new applies after completing a shift. Paid: unrestricted.
class WorkerApplyGuard {
  WorkerApplyGuard._();

  /// [applyingToGigId] should be the gig the worker is trying to apply to.
  /// `null` if unknown (treats any other commitment as blocking).
  static Future<String?> blockingReason({
    required ShiftRepository shiftRepo,
    required SessionController session,
    String? applyingToGigId,
  }) async {
    if (!SupabaseConfig.isConfigured) return null;

    final workerId = appActorId(session, mockFallback: '');
    if (workerId.isEmpty) return null;

    final sub = await _subscriptionActive(workerId);
    if (sub) return null;

    final sessions = await shiftRepo.listShiftSessions();
    final mine = sessions.where((s) => s.workerId == workerId);
    final activeCount = mine.where((s) => s.checkOutAt == null).length;
    final hasCompleted = mine.any((s) => s.checkOutAt != null);

    if (activeCount >= 1) {
      return 'Your free plan allows only one active shift at a time. Finish it '
          'before taking another job, or subscribe (₱${RevenueStubService.workerSubscriptionPhp}/mo) '
          'for multiple concurrent shifts.';
    }
    if (hasCompleted) {
      return 'You have already completed a shift on the free plan. Subscribe '
          '(₱${RevenueStubService.workerSubscriptionPhp}/month) to keep applying and working.';
    }

    final otherCommitment = await _otherGigCommitment(
      workerId: workerId,
      applyingToGigId: applyingToGigId,
    );
    if (otherCommitment) {
      return 'Free plan allows only one job opportunity at a time. Withdraw your '
          'other pending application or finish your current hire, or subscribe '
          'to apply for multiple jobs at once.';
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

  /// Pending application or hire on another gig (free tier cannot stack).
  static Future<bool> _otherGigCommitment({
    required String workerId,
    String? applyingToGigId,
  }) async {
    try {
      final response = await Supabase.instance.client
          .from('gig_applications')
          .select('gig_id,status')
          .eq('worker_id', workerId);
      final rows = response as List<dynamic>;
      for (final raw in rows) {
        final m = Map<String, dynamic>.from(raw as Map);
        final gid = m['gig_id']?.toString();
        if (gid == null || gid.isEmpty) continue;
        if (applyingToGigId != null && gid == applyingToGigId) continue;
        final stRaw = m['status']?.toString();
        if (stRaw == null) continue;
        final ApplicationStatus st;
        try {
          st = ApplicationStatus.values.byName(stRaw);
        } catch (_) {
          continue;
        }
        if (st == ApplicationStatus.withdrawn || st == ApplicationStatus.rejected) {
          continue;
        }
        if (st == ApplicationStatus.applied || st == ApplicationStatus.hired) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
}

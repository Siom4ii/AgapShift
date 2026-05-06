import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../subscriptions/revenue_stub_service.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';

/// Worker paid tier: multiple concurrent shifts + apply after completing jobs.
///
/// Billing is a stub until a payment provider is integrated.
class WorkerSubscriptionScreen extends StatefulWidget {
  const WorkerSubscriptionScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<WorkerSubscriptionScreen> createState() =>
      _WorkerSubscriptionScreenState();
}

class _WorkerSubscriptionScreenState extends State<WorkerSubscriptionScreen> {
  bool _loading = true;
  bool _busy = false;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    DateTime? exp;
    if (SupabaseConfig.isConfigured) {
      final id = appActorId(widget.session, mockFallback: '');
      if (id.isNotEmpty) {
        try {
          final row = await Supabase.instance.client
              .from('worker_entitlements')
              .select('subscription_expires_at')
              .eq('user_id', id)
              .maybeSingle();
          final raw = row?['subscription_expires_at'];
          if (raw != null) {
            exp = DateTime.parse(raw as String);
          }
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _expiresAt = exp;
      _loading = false;
    });
  }

  Future<void> _subscribeStub() async {
    final id = appActorId(widget.session, mockFallback: '');
    if (id.isEmpty) return;
    setState(() => _busy = true);
    await RevenueStubService.payWorkerSubscription(id);
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Subscription active (demo). Connect a payment provider for production.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _expiresAt != null && _expiresAt!.isAfter(DateTime.now().toUtc());

    return Scaffold(
      backgroundColor: AgapColors.pageBackground,
      appBar: AppBar(
        title: Text(
          'Worker subscription',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'AgapShift Worker',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Free tier: one active shift at a time, and your first shift cycle '
                  'without a subscription. Subscribe to apply broadly and hold multiple shifts.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: AgapColors.textMuted,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AgapColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active ? 'Status: Active' : 'Status: Not subscribed',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: active
                              ? AgapColors.businessGreen
                              : const Color(0xFF92400E),
                        ),
                      ),
                      if (active && _expiresAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Renews / ends: ${_expiresAt!.toLocal()}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        '• Apply for more jobs after you complete a shift\n'
                        '• Hold more than one active shift at a time',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                          color: const Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '₱149 / month (demo price)',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _subscribeStub,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          active ? 'Extend 30 days (demo pay)' : 'Subscribe (demo pay)',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

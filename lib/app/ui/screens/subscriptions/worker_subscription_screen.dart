import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../billing/paymongo_billing_service.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../subscriptions/revenue_stub_service.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';

/// Worker paid tier: continuous applications and multiple concurrent shifts
/// after the one free job opportunity on the free tier.
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
  bool _subscribedCongratsShownThisSession = false;

  String _formatDateTime(DateTime d) {
    final local = d.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ap = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}/${local.year} '
        '$h:$m $ap';
  }

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

    final activeNow = exp != null && exp.isAfter(DateTime.now().toUtc());
    if (activeNow && !_subscribedCongratsShownThisSession && mounted) {
      _subscribedCongratsShownThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSubscribedCongrats();
      });
    }
  }

  Future<void> _showSubscribedCongrats() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1D4ED8), Color(0xFF60A5FA)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Congratulations!',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your worker subscription is now active.',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Subscribed privileges',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1E3A8A),
                ),
              ),
              const SizedBox(height: 10),
              const _SubPrivilegeRow(
                icon: Icons.all_inclusive_rounded,
                text: 'Unlimited job applications while subscribed',
                accent: Color(0xFF1D4ED8),
                bg: Color(0xFFEFF6FF),
              ),
              const SizedBox(height: 10),
              const _SubPrivilegeRow(
                icon: Icons.work_outline_rounded,
                text: 'Apply for jobs continuously',
                accent: Color(0xFF1D4ED8),
                bg: Color(0xFFEFF6FF),
              ),
              const SizedBox(height: 10),
              const _SubPrivilegeRow(
                icon: Icons.layers_rounded,
                text: 'Take multiple shifts at the same time',
                accent: Color(0xFF1D4ED8),
                bg: Color(0xFFEFF6FF),
              ),
              const SizedBox(height: 10),
              const _SubPrivilegeRow(
                icon: Icons.autorenew_rounded,
                text: 'Keep applying after completing shifts',
                accent: Color(0xFF1D4ED8),
                bg: Color(0xFFEFF6FF),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Continue',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _subscribe() async {
    final id = appActorId(widget.session, mockFallback: '');
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      final url = await PaymongoBillingService.startCheckout(
        product: BillingProduct.workerSub,
      );
      if (url == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to start checkout.')),
        );
        return;
      }
      await PaymongoBillingService.openCheckoutUrl(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete payment in PayMongo, then tap Refresh.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment could not be started.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _expiresAt != null && _expiresAt!.isAfter(DateTime.now().toUtc());
    final statusLabel = active ? 'Active' : 'Not subscribed';
    final statusColor = active ? const Color(0xFF065F46) : const Color(0xFF92400E);
    final statusBg = active ? const Color(0xFFD1FAE5) : const Color(0xFFFFF7ED);
    final statusBorder = active ? const Color(0xFF6EE7B7) : const Color(0xFFFED7AA);

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
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF60A5FA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.workspace_premium_rounded,
                                color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Worker Plan',
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Unlimited applications + multiple shifts',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.92),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (active && _expiresAt != null)
                        Text(
                          'Valid through ${_formatDateTime(_expiresAt!)}',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                        )
                      else
                        Text(
                          'Start with 1 free job opportunity, then subscribe to keep applying.',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.92),
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AgapColors.borderSubtle),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.info_outline_rounded,
                            color: Color(0xFF1D4ED8), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Free tier rules: one pending application or hire at a time, '
                          'one active shift, and no new applications after you complete that shift.',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF334155),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AgapColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'What you get',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: statusBorder),
                            ),
                            child: Text(
                              '₱${RevenueStubService.workerSubscriptionPhp}/mo',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _PerkRow(icon: Icons.task_alt_rounded, text: 'Apply for jobs continuously'),
                      const SizedBox(height: 10),
                      _PerkRow(icon: Icons.all_inclusive_rounded, text: 'Unlimited applications while subscribed'),
                      const SizedBox(height: 10),
                      _PerkRow(icon: Icons.layers_rounded, text: 'Take multiple shifts at the same time'),
                      const SizedBox(height: 10),
                      _PerkRow(icon: Icons.autorenew_rounded, text: 'Keep applying after completing shifts'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          active ? 'Plan is active' : 'Upgrade when you’re ready',
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (!mounted) return;
                                final messenger = ScaffoldMessenger.of(context);
                                final reconciled =
                                    await PaymongoBillingService.reconcileLatest();
                                if (!mounted) return;
                                await _refresh();
                                if (!mounted) return;
                                if (reconciled) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Payment verified. Subscription is now active.'),
                                    ),
                                  );
                                  if (!_subscribedCongratsShownThisSession) {
                                    _subscribedCongratsShownThisSession = true;
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (!mounted) return;
                                      _showSubscribedCongrats();
                                    });
                                  }
                                }
                              },
                        child: Text(
                          'Refresh',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _subscribe,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
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
                          active ? 'Extend 30 days' : 'Subscribe now',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  'After paying, tap Refresh to update your status.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AgapColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
    );
  }
}

class _PerkRow extends StatelessWidget {
  const _PerkRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF1D4ED8)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: const Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }
}

class _SubPrivilegeRow extends StatelessWidget {
  const _SubPrivilegeRow({
    required this.icon,
    required this.text,
    required this.accent,
    required this.bg,
  });

  final IconData icon;
  final String text;
  final Color accent;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12.8,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: const Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }
}

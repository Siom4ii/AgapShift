import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../payments/mock_payments_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/locked_action.dart';
import '../../widgets/shell_screen_polish.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    required this.payments,
    required this.session,
    this.embedded = false,
  });

  final MockPaymentsRepository payments;
  final SessionController session;
  final bool embedded;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = false;
  String? _error;
  Wallet? _wallet;
  List<LedgerTransaction> _ledger = const [];
  int _txFilter = 0; // 0=All, 1=Received, 2=Sent

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = appActorId(widget.session, mockFallback: '');
      final wallet = await widget.payments.getWallet(userId);
      final ledger = await widget.payments.listLedger(userId);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _ledger = ledger;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _withdraw() async {
    if (!canPerformVerifiedAction(widget.session)) {
      await showLockedFeatureDialog(
        context,
        session: widget.session,
        featureName: 'Withdrawals',
      );
      return;
    }
    final userId = appActorId(widget.session, mockFallback: '');
    final amount = await _showWithdrawSheet(
      context,
      availableCentavos: _wallet?.available.amount ?? 0,
    );
    if (amount == null) return;
    try {
      await widget.payments.requestWithdrawal(
        userId: userId,
        amount: Money(amount: amount),
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Withdrawal requested')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cannot withdraw: $e')));
    }
  }

  String _peso(int centavos) {
    final v = (centavos / 100).toStringAsFixed(2);
    return '₱ $v';
  }

  List<_TxDisplay> _buildTransactionRows() {
    final fromLedger = _ledger.map(_TxDisplay.fromLedger).toList();
    if (fromLedger.length >= 8) return fromLedger.take(8).toList();
    final demo = _demoTransactions();
    final merged = [...fromLedger];
    for (final d in demo) {
      if (merged.length >= 8) break;
      if (!merged.any(
        (m) => m.title == d.title && m.amountCents == d.amountCents,
      )) {
        merged.add(d);
      }
    }
    return merged.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text('Error: $_error'))
        : wallet == null
        ? const Center(child: Text('No wallet'))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                _WalletHeader(
                  availablePeso: _peso(wallet.available.amount),
                  pendingLabel: wallet.pending.amount > 0
                      ? '+ ${_peso(wallet.pending.amount)} pending release'
                      : null,
                  onWithdraw: wallet.available.amount > 0 ? _withdraw : null,
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _AccountPillsRow(
                    onAdd: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Add account (demo)')),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'Transactions',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      _TxFilterTabs(
                        index: _txFilter,
                        onChange: (i) => setState(() => _txFilter = i),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _TxList(
                    items: _applyTxFilter(_buildTransactionRows(), _txFilter),
                  ),
                ),
              ],
            ),
          );

    if (widget.embedded) {
      // The shell already has its own app bar; avoid adding extra top padding so
      // the header can render as a full-width “cover”.
      return ShellChromeBackground(
        kind: ShellChromeKind.worker,
        child: SafeArea(top: false, child: content),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: content),
    );
  }
}

// (Old wallet widgets removed during redesign.)

enum _TxKind { income, withdrawal, pendingIncome }

class _TxDisplay {
  _TxDisplay({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.amountCents,
    required this.badgeLabel,
    required this.badgeBg,
    required this.badgeFg,
  });

  final _TxKind kind;
  final String title;
  final String subtitle;
  final int amountCents;
  final String badgeLabel;
  final Color badgeBg;
  final Color badgeFg;

  static _TxDisplay fromLedger(LedgerTransaction t) {
    final cents = t.amount.amount.abs();
    switch (t.type) {
      case TransactionType.earningCredit:
      case TransactionType.escrowRelease:
        return _TxDisplay(
          kind: _TxKind.income,
          title: 'Shift payment',
          subtitle: t.gigId != null
              ? 'Gig ${t.gigId!.length > 12 ? '${t.gigId!.substring(0, 8)}…' : t.gigId!}'
              : 'AgapShift',
          amountCents: cents,
          badgeLabel: 'COMPLETED',
          badgeBg: const Color(0xFFDCFCE7),
          badgeFg: const Color(0xFF166534),
        );
      case TransactionType.withdrawalDebit:
        return _TxDisplay(
          kind: _TxKind.withdrawal,
          title: 'Withdrawal to GCash',
          subtitle: 'Transfer',
          amountCents: -cents,
          badgeLabel: 'SUCCESS',
          badgeBg: const Color(0xFFDBEAFE),
          badgeFg: const Color(0xFF1E40AF),
        );
      default:
        return _TxDisplay(
          kind: _TxKind.pendingIncome,
          title: t.type.name,
          subtitle: 'Transaction',
          amountCents: cents,
          badgeLabel: 'PENDING',
          badgeBg: const Color(0xFFFFEDD5),
          badgeFg: const Color(0xFF9A3412),
        );
    }
  }
}

List<_TxDisplay> _demoTransactions() {
  return [
    _TxDisplay(
      kind: _TxKind.income,
      title: 'Warehouse Sorting Shift',
      subtitle: 'LogiCorp Inc.',
      amountCents: 150000,
      badgeLabel: 'COMPLETED',
      badgeBg: const Color(0xFFDCFCE7),
      badgeFg: const Color(0xFF166534),
    ),
    _TxDisplay(
      kind: _TxKind.withdrawal,
      title: 'Withdrawal to GCash',
      subtitle: '',
      amountCents: -300000,
      badgeLabel: 'SUCCESS',
      badgeBg: const Color(0xFFDBEAFE),
      badgeFg: const Color(0xFF1E40AF),
    ),
    _TxDisplay(
      kind: _TxKind.income,
      title: 'Event Setup Assistant',
      subtitle: 'Stellar Events',
      amountCents: 220000,
      badgeLabel: 'COMPLETED',
      badgeBg: const Color(0xFFDCFCE7),
      badgeFg: const Color(0xFF166534),
    ),
    _TxDisplay(
      kind: _TxKind.pendingIncome,
      title: 'Data Entry Specialist',
      subtitle: 'TechFlow',
      amountCents: 180000,
      badgeLabel: 'PENDING',
      badgeBg: const Color(0xFFFFEDD5),
      badgeFg: const Color(0xFF9A3412),
    ),
  ];
}

class _TransactionRowTile extends StatelessWidget {
  const _TransactionRowTile({required this.tx});

  final _TxDisplay tx;

  @override
  Widget build(BuildContext context) {
    final isPositive = tx.amountCents >= 0;
    final amountStr =
        '${isPositive ? '+ ' : '- '}₱ ${(tx.amountCents.abs() / 100).toStringAsFixed(2)}';

    Color circleBg;
    Color iconColor;
    IconData icon;
    switch (tx.kind) {
      case _TxKind.income:
        circleBg = const Color(0xFFDCFCE7);
        iconColor = const Color(0xFF166534);
        icon = Icons.south_west_rounded;
        break;
      case _TxKind.withdrawal:
        circleBg = const Color(0xFFDBEAFE);
        iconColor = const Color(0xFF1E40AF);
        icon = Icons.north_east_rounded;
        break;
      case _TxKind.pendingIncome:
        circleBg = const Color(0xFFF3F4F6);
        iconColor = AgapColors.accentOrange;
        icon = Icons.schedule_rounded;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: circleBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                if (tx.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tx.subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AgapColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amountStr,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: isPositive
                      ? const Color(0xFF166534)
                      : const Color(0xFF1E40AF),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tx.badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tx.badgeLabel,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: tx.badgeFg,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

List<_TxDisplay> _applyTxFilter(List<_TxDisplay> items, int filter) {
  if (filter == 1) {
    return items.where((t) => t.amountCents > 0).toList();
  }
  if (filter == 2) {
    return items.where((t) => t.amountCents < 0).toList();
  }
  return items;
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({
    required this.availablePeso,
    required this.pendingLabel,
    required this.onWithdraw,
  });

  final String availablePeso;
  final String? pendingLabel;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Wallet',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Available Balance',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                availablePeso.replaceAll('₱ ', '₱'),
                style: GoogleFonts.inter(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: Colors.white,
                ),
              ),
              if (pendingLabel != null) ...[
                const SizedBox(height: 6),
                Text(
                  pendingLabel!,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: onWithdraw != null
                          ? FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF5B21B6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: onWithdraw,
                              icon: const Icon(
                                Icons.north_east_rounded,
                                size: 18,
                              ),
                              label: Text(
                                'Withdraw',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white.withValues(
                                  alpha: 0.9,
                                ),
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.10,
                                ),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: null,
                              icon: Icon(
                                Icons.north_east_rounded,
                                size: 18,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                              label: Text(
                                'Withdraw',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountPillsRow extends StatelessWidget {
  const _AccountPillsRow({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    Widget pill({
      required IconData icon,
      required String title,
      String? subtitle,
      required Color tint,
      bool outlined = true,
      VoidCallback? onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: outlined ? const Color(0xFFE5E7EB) : Colors.transparent,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: tint),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AgapColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final items = [
      () => pill(
        icon: Icons.favorite_rounded,
        title: 'GCash',
        subtitle: '0917••••4567',
        tint: const Color(0xFF7C3AED),
      ),
      () => pill(
        icon: Icons.favorite_rounded,
        title: 'Maya',
        subtitle: 'Linked',
        tint: const Color(0xFF2563EB),
      ),
      () => pill(
        icon: Icons.add_rounded,
        title: '+ Add',
        tint: const Color(0xFF7C3AED),
        onTap: onAdd,
      ),
    ];

    // Horizontal scroll prevents overlap on narrow screens while keeping the
    // exact “3 pills” layout from the mock.
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, i) {
          return ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140),
            child: items[i](),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: items.length,
      ),
    );
  }
}

class _TxFilterTabs extends StatelessWidget {
  const _TxFilterTabs({required this.index, required this.onChange});

  final int index;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, int i) {
      final selected = index == i;
      return InkWell(
        onTap: () => onChange(i),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected ? const Color(0xFF111827) : AgapColors.textMuted,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [tab('All', 0), tab('Received', 1), tab('Sent', 2)],
      ),
    );
  }
}

class _TxList extends StatelessWidget {
  const _TxList({required this.items});
  final List<_TxDisplay> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Center(
          child: Text(
            'No transactions yet.',
            style: GoogleFonts.inter(
              color: AgapColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          ShellStaggerItem(
            index: i,
            child: ShellLift(
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _TransactionRowTile(tx: items[i]),
              ),
            ),
          ),
      ],
    );
  }
}

Future<int?> _showWithdrawSheet(
  BuildContext context, {
  required int availableCentavos,
}) async {
  final controller = TextEditingController();
  int selected = 0; // 0=GCash, 1=Maya, 2=Bank
  int? amountCentavos;

  String peso(int c) => '₱${(c / 100).toStringAsFixed(2)}';

  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModal) {
          void setQuick(int php) {
            amountCentavos = php * 100;
            controller.text = php.toStringAsFixed(0);
            setModal(() {});
          }

          int parsed() {
            final v = double.tryParse(controller.text.trim());
            if (v == null) return 0;
            return (v * 100).round();
          }

          final entered = amountCentavos ?? parsed();
          final can = entered > 0 && entered <= availableCentavos;
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;

          Widget methodTab(String label, int i) {
            final s = selected == i;
            return Expanded(
              child: InkWell(
                onTap: () => setModal(() => selected = i),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: s
                        ? const Color(0xFFF3E8FF)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: s
                          ? const Color(0xFF7C3AED)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: s
                            ? const Color(0xFF6D28D9)
                            : AgapColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Withdraw Funds',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE9D5FF)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Available Balance',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF6D28D9),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              peso(availableCentavos),
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF6D28D9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Withdraw to',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    methodTab('GCash', 0),
                    const SizedBox(width: 10),
                    methodTab('Maya', 1),
                    const SizedBox(width: 10),
                    methodTab('Bank', 2),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Amount',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      prefixText: '₱ ',
                      hintText: '0.00',
                      hintStyle: GoogleFonts.inter(color: AgapColors.textMuted),
                    ),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                    onChanged: (_) => setModal(() => amountCentavos = null),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickAmount(
                        label: '₱500',
                        onTap: () => setQuick(500),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickAmount(
                        label: '₱1000',
                        onTap: () => setQuick(1000),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _QuickAmount(
                        label: '₱2000',
                        onTap: () => setQuick(2000),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: can
                          ? const Color(0xFF6D28D9)
                          : AgapColors.textMuted.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: can
                        ? () {
                            Navigator.of(ctx).pop(entered);
                          }
                        : null,
                    child: Text(
                      'Withdraw Now',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  selected == 0
                      ? 'Funds will be sent to your GCash account (demo).'
                      : selected == 1
                      ? 'Funds will be sent to your Maya wallet (demo).'
                      : 'Funds will be sent to your bank account (demo).',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AgapColors.textMuted,
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _QuickAmount extends StatelessWidget {
  const _QuickAmount({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
        ),
      ),
    );
  }
}

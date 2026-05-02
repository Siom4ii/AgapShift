import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';

class BusinessWalletScreen extends StatefulWidget {
  const BusinessWalletScreen({super.key, this.onOpenNotifications});

  final VoidCallback? onOpenNotifications;

  @override
  State<BusinessWalletScreen> createState() => _BusinessWalletScreenState();
}

class _BusinessWalletScreenState extends State<BusinessWalletScreen> {
  int _filter = 0;

  static const _filters = ['All', 'Top-Ups', 'Payments'];

  static const _tx = [
    _Tx(
      title: 'Worker Payment',
      subtitle: '4 workers × ₱850 – Warehouse shift',
      time: 'Today, 6:00 PM',
      amount: '-₱3,400',
      negative: true,
      icon: Icons.north_east_rounded,
    ),
    _Tx(
      title: 'Wallet Top-up',
      subtitle: 'Bank Transfer – BDO',
      time: 'Yesterday, 2:15 PM',
      amount: '+₱10,000',
      negative: false,
      icon: Icons.south_west_rounded,
    ),
    _Tx(
      title: 'Worker Payment',
      subtitle: 'Service crew · Evening shift',
      time: 'Apr 28, 4:30 PM',
      amount: '-₱750',
      negative: true,
      icon: Icons.north_east_rounded,
    ),
  ];

  void _openTopUp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (_, scrollController) {
            return DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Top Up Wallet',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: Icon(
                            Icons.close_rounded,
                            color: AgapColors.textMuted,
                          ),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Choose a payment method to top up your business wallet.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AgapColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [
                        Text(
                          'Amount',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '₱ 0.00',
                            filled: true,
                            fillColor: AgapColors.pageBackground,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final v in [5000, 10000, 20000])
                              ActionChip(
                                label: Text('₱${_fmt(v)}'),
                                onPressed: () {},
                                backgroundColor: AgapColors.businessMint,
                                side: BorderSide(
                                  color: AgapColors.borderSubtle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Pay via',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        _PayTile(
                          icon: Icons.account_balance_rounded,
                          title: 'BDO Bank Transfer',
                        ),
                        const SizedBox(height: 10),
                        _PayTile(
                          icon: Icons.phone_android_rounded,
                          title: 'GCash for Business',
                        ),
                        const SizedBox(height: 10),
                        _PayTile(
                          icon: Icons.payment_rounded,
                          title: 'Maya Business',
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AgapColors.businessGreen,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Top-up started (demo)'),
                                ),
                              );
                            },
                            child: Text(
                              'Top Up Now',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
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

  static String _fmt(int n) {
    final digits = n.toString().split('').reversed.toList();
    final out = <String>[];
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 3 == 0) out.add(',');
      out.add(digits[i]);
    }
    return out.reversed.join();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ShellChromeBackground(
      kind: ShellChromeKind.business,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AgapColors.businessGreenDeep,
                    AgapColors.businessGreen,
                    AgapColors.businessGreenLight,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Business Wallet',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (widget.onOpenNotifications != null)
                        Material(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            onPressed: widget.onOpenNotifications,
                            icon: Badge(
                              label: Text(
                                '2',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              backgroundColor: Colors.red.shade600,
                              child: const Icon(
                                Icons.notifications_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Available Balance',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₱15,500',
                    style: GoogleFonts.inter(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total spent: ₱48,200',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.88),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AgapColors.businessGreenDeep,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => _openTopUp(context),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: Text(
                            'Top Up',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Pay workers (demo)'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.north_east_rounded, size: 18),
                          label: Text(
                            'Pay Workers',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.trending_down_rounded,
                        iconColor: AgapColors.businessGreen,
                        label: 'This Month',
                        value: '₱30,550',
                        caption: 'Spent on workers',
                        captionColor: AgapColors.businessGreen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.groups_rounded,
                        iconColor: const Color(0xFF7C3AED),
                        label: 'This Month',
                        value: '124',
                        caption: 'Workers hired',
                        captionColor: AgapColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Transactions',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final sel = i == _filter;
                  return FilterChip(
                    label: Text(_filters[i]),
                    selected: sel,
                    onSelected: (_) => setState(() => _filter = i),
                    showCheckmark: false,
                    selectedColor: AgapColors.businessMint,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: sel
                          ? AgapColors.businessGreen
                          : AgapColors.borderSubtle,
                    ),
                    labelStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: sel
                          ? AgapColors.businessGreen
                          : AgapColors.textMuted,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                },
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottom),
            sliver: SliverList.separated(
              itemCount: _tx.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => ShellStaggerItem(
                index: i,
                child: ShellLift(child: _TxCard(tx: _tx[i])),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.caption,
    required this.captionColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String caption;
  final Color captionColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AgapColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AgapColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: captionColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tx {
  const _Tx({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.amount,
    required this.negative,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String time;
  final String amount;
  final bool negative;
  final IconData icon;
}

class _TxCard extends StatelessWidget {
  const _TxCard({required this.tx});

  final _Tx tx;

  @override
  Widget build(BuildContext context) {
    final squareBg = tx.negative
        ? AgapColors.pageBackground
        : AgapColors.businessMint;
    final iconFg = AgapColors.businessGreen;
    final amtColor = tx.negative
        ? const Color(0xFF111827)
        : AgapColors.businessGreen;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgapColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: squareBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(tx.icon, color: iconFg, size: 22),
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
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tx.subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AgapColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tx.time,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AgapColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            tx.amount,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: amtColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayTile extends StatelessWidget {
  const _PayTile({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AgapColors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, color: AgapColors.businessGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AgapColors.textMuted),
        ],
      ),
    );
  }
}

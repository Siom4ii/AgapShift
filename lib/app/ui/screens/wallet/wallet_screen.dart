import 'package:flutter/material.dart';

import '../../../../domain/models.dart';
import '../../../payments/mock_payments_repository.dart';
import '../../../session/session_controller.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    required this.payments,
    required this.session,
  });

  final MockPaymentsRepository payments;
  final SessionController session;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = false;
  String? _error;
  Wallet? _wallet;
  List<LedgerTransaction> _ledger = const [];
  List<Payout> _payouts = const [];

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
      final userId = widget.session.state.email ?? '';
      final wallet = await widget.payments.getWallet(userId);
      final ledger = await widget.payments.listLedger(userId);
      final payouts = await widget.payments.listPayouts(userId);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _ledger = ledger;
        _payouts = payouts;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _withdraw() async {
    final userId = widget.session.state.email ?? '';
    final amount = await _promptAmount(context);
    if (amount == null) return;
    try {
      await widget.payments.requestWithdrawal(userId: userId, amount: Money(amount: amount));
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Withdrawal requested')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot withdraw: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
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
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('Error: $_error'))
                : wallet == null
                    ? const Center(child: Text('No wallet'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Available', style: Theme.of(context).textTheme.titleSmall),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₱${(wallet.available.amount / 100).toStringAsFixed(2)}',
                                    style: Theme.of(context).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 12),
                                  Text('Pending', style: Theme.of(context).textTheme.titleSmall),
                                  const SizedBox(height: 4),
                                  Text('₱${(wallet.pending.amount / 100).toStringAsFixed(2)}'),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: wallet.available.amount > 0 ? _withdraw : null,
                                      child: const Text('Withdraw'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text('Payouts', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          if (_payouts.isEmpty)
                            const Text('No payout requests yet.')
                          else
                            ..._payouts.map(
                              (p) => ListTile(
                                title: Text('₱${(p.amount.amount / 100).toStringAsFixed(2)}'),
                                subtitle: Text(p.status.name),
                              ),
                            ),
                          const Divider(height: 24),
                          Text('Transactions', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          if (_ledger.isEmpty)
                            const Text('No transactions yet.')
                          else
                            ..._ledger.map(
                              (t) => ListTile(
                                title: Text(t.type.name),
                                subtitle: Text('₱${(t.amount.amount / 100).toStringAsFixed(2)}'),
                                trailing: t.gigId == null ? null : Text(t.gigId!),
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }
}

Future<int?> _promptAmount(BuildContext context) async {
  final controller = TextEditingController(text: '50000'); // ₱500 default
  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Withdraw amount (centavos)'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(hintText: 'e.g., 50000 for ₱500.00'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = int.tryParse(controller.text.trim());
            Navigator.pop(context, v);
          },
          child: const Text('Continue'),
        ),
      ],
    ),
  );
}


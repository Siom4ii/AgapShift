import 'package:flutter/material.dart';

import '../../../../domain/enums.dart';
import '../../../ratings/mock_ratings_repository.dart';
import '../../../session/session_controller.dart';
import '../../../shift/mock_shift_repository.dart';

class WorkerProfileScreen extends StatefulWidget {
  const WorkerProfileScreen({
    super.key,
    required this.session,
    required this.shiftRepo,
    required this.ratings,
  });

  final SessionController session;
  final MockShiftRepository shiftRepo;
  final MockRatingsRepository ratings;

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  double _avg = 0;
  int _completed = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = widget.session.state.email ?? '';
    final avg = await widget.ratings.averageForUser(userId);
    final sessions = await widget.shiftRepo.listShiftSessions();
    final completed = sessions.where((s) => s.workerId == userId && s.checkOutAt != null).length;
    if (!mounted) return;
    setState(() {
      _avg = avg;
      _completed = completed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.session.state.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const CircleAvatar(radius: 26, child: Icon(Icons.person)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userId, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.verified, size: 16),
                          const SizedBox(width: 6),
                          Text((widget.session.state.accountStatus ?? AccountStatus.pendingVerification).name),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat(label: 'Rating', value: _avg == 0 ? '—' : _avg.toStringAsFixed(1)),
                    _Stat(label: 'Shifts', value: _completed.toString()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Resume (MVP placeholder)'),
            const SizedBox(height: 6),
            const Text('Skills, experience, and education will show here once stored from onboarding.'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}


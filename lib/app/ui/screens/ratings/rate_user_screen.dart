import 'package:flutter/material.dart';

import '../../../ratings/mock_ratings_repository.dart';

class RateUserScreen extends StatefulWidget {
  const RateUserScreen({
    super.key,
    required this.ratings,
    required this.gigId,
    required this.raterUserId,
    required this.ratedUserId,
    required this.title,
  });

  final MockRatingsRepository ratings;
  final String gigId;
  final String raterUserId;
  final String ratedUserId;
  final String title;

  @override
  State<RateUserScreen> createState() => _RateUserScreenState();
}

class _RateUserScreenState extends State<RateUserScreen> {
  int _stars = 5;
  final _feedback = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.ratings.create(
        gigId: widget.gigId,
        raterUserId: widget.raterUserId,
        ratedUserId: widget.ratedUserId,
        stars: _stars,
        feedback: _feedback.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rate')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('Select a rating:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: List.generate(5, (i) {
                final v = i + 1;
                final selected = v == _stars;
                return ChoiceChip(
                  label: Text('$v'),
                  selected: selected,
                  onSelected: (s) => setState(() => _stars = v),
                );
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _feedback,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Feedback (optional)',
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit rating'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


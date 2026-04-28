import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../shift/mock_shift_repository.dart';

class BusinessQrScreen extends StatefulWidget {
  const BusinessQrScreen({
    super.key,
    required this.shiftRepo,
    required this.gig,
  });

  final MockShiftRepository shiftRepo;
  final Gig gig;

  @override
  State<BusinessQrScreen> createState() => _BusinessQrScreenState();
}

class _BusinessQrScreenState extends State<BusinessQrScreen> {
  AttendanceScanType _type = AttendanceScanType.checkIn;
  String _token = '';

  @override
  void initState() {
    super.initState();
    _regen();
  }

  void _regen() {
    final token = _type == AttendanceScanType.checkIn
        ? widget.shiftRepo.createCheckInQr(gigId: widget.gig.id)
        : widget.shiftRepo.createCheckOutQr(gigId: widget.gig.id);
    setState(() => _token = token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR attendance')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.gig.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SegmentedButton<AttendanceScanType>(
                segments: const [
                  ButtonSegment(value: AttendanceScanType.checkIn, label: Text('Check-in')),
                  ButtonSegment(value: AttendanceScanType.checkOut, label: Text('Check-out')),
                ],
                selected: {_type},
                onSelectionChanged: (s) {
                  setState(() => _type = s.first);
                  _regen();
                },
              ),
              const SizedBox(height: 16),
              Center(
                child: QrImageView(
                  data: _token,
                  size: 260,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tip: regenerate every few minutes (tokens expire).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _regen,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Regenerate QR'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


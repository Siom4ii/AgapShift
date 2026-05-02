import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../theme/agap_colors.dart';

/// Pay unit shown next to the rate (/day, /hr, /shift).
enum _PayUnit { day, hour, shift }

class BusinessCreateGigScreen extends StatefulWidget {
  const BusinessCreateGigScreen({
    super.key,
    required this.repo,
    required this.session,
    required this.onCreated,
  });

  final MarketplaceRepository repo;
  final SessionController session;
  final Future<void> Function() onCreated;

  @override
  State<BusinessCreateGigScreen> createState() =>
      _BusinessCreateGigScreenState();
}

class _BusinessCreateGigScreenState extends State<BusinessCreateGigScreen> {
  static const _creamBg = Color(0xFFF7F5F0);
  static const _navyTitle = Color(0xFF0F172A);
  static const _labelGrey = Color(0xFF64748B);
  static const _borderField = Color(0xFFE2E8F0);
  static const _chipOrange = Color(0xFFFF9800);
  static const _chipOrangeDeep = Color(0xFFE65100);
  static const _minRatePhp = 150.0;

  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _address = TextEditingController();
  final _payRate = TextEditingController(text: '850');
  final _requirements = TextEditingController();
  final _benefits = TextEditingController();

  String _category = 'Warehouse';
  DateTime? _startDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  int _workersNeeded = 1;
  _PayUnit _payUnit = _PayUnit.day;
  bool _urgent = false;

  bool _submitting = false;
  String? _error;

  static const _jobTypeKeys = <String>[
    'Warehouse',
    'Food Service',
    'Retail',
    'Events',
    'Construction',
    'Delivery',
    'Cleaning',
    'Other',
  ];

  bool get _canSubmit {
    if (_title.text.trim().isEmpty) return false;
    if (_desc.text.trim().isEmpty) return false;
    if (_address.text.trim().isEmpty) return false;
    if (_startDate == null || _startTime == null || _endTime == null) {
      return false;
    }
    final rate = double.tryParse(_payRate.text.trim()) ?? 0;
    if (rate < _minRatePhp) return false;
    final startDt = _composeDateTime(_startDate!, _startTime!);
    final endDt = _composeDateTime(_startDate!, _endTime!);
    if (!endDt.isAfter(startDt)) return false;
    return true;
  }

  DateTime _composeDateTime(DateTime d, TimeOfDay t) {
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  int get _payCentavos {
    if (_startDate == null || _startTime == null || _endTime == null) {
      return 0;
    }
    final ratePhp = double.tryParse(_payRate.text.trim()) ?? 0;
    final rateCentavos = (ratePhp * 100).round();
    final workers = _workersNeeded.clamp(1, 999);
    final startDt = _composeDateTime(_startDate!, _startTime!);
    final endDt = _composeDateTime(_startDate!, _endTime!);
    final hours =
        endDt.difference(startDt).inMinutes.clamp(1, 24 * 60) / 60.0;

    switch (_payUnit) {
      case _PayUnit.hour:
        return (rateCentavos * hours * workers).round();
      case _PayUnit.day:
      case _PayUnit.shift:
        return rateCentavos * workers;
    }
  }

  String _buildDescriptionBody() {
    final parts = <String>[];
    if (_desc.text.trim().isNotEmpty) parts.add(_desc.text.trim());
    if (_requirements.text.trim().isNotEmpty) {
      parts.add('Requirements: ${_requirements.text.trim()}');
    }
    if (_benefits.text.trim().isNotEmpty) {
      parts.add('Benefits: ${_benefits.text.trim()}');
    }
    if (_urgent) parts.add('Marked as urgent — workers prioritized.');
    parts.add('Workers needed: $_workersNeeded');
    return parts.join('\n\n');
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _address.dispose();
    _payRate.dispose();
    _requirements.dispose();
    _benefits.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _startDate = d);
  }

  Future<void> _pickStartTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (t != null) setState(() => _startTime = t);
  }

  Future<void> _pickEndTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _endTime ??
          const TimeOfDay(hour: 17, minute: 0),
    );
    if (t != null) setState(() => _endTime = t);
  }

  bool _validate() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Job title is required.');
      return false;
    }
    if (_desc.text.trim().isEmpty) {
      setState(() => _error = 'Job description is required.');
      return false;
    }
    if (_address.text.trim().isEmpty) {
      setState(() => _error = 'Work site address is required.');
      return false;
    }
    if (_startDate == null || _startTime == null || _endTime == null) {
      setState(() => _error = 'Please set date, start time, and end time.');
      return false;
    }
    final rate = double.tryParse(_payRate.text.trim()) ?? 0;
    if (rate < _minRatePhp) {
      setState(
        () => _error =
            'Minimum pay rate is ₱${_minRatePhp.toStringAsFixed(0)}.',
      );
      return false;
    }
    final startDt = _composeDateTime(_startDate!, _startTime!);
    final endDt = _composeDateTime(_startDate!, _endTime!);
    if (!endDt.isAfter(startDt)) {
      setState(() => _error = 'End time must be after start time.');
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final businessId = appActorId(widget.session, mockFallback: 'business');
      final startDt = _composeDateTime(_startDate!, _startTime!);
      final endDt = _composeDateTime(_startDate!, _endTime!);

      await widget.repo.createGig(
        businessId: businessId,
        title: _title.text.trim(),
        description: _buildDescriptionBody(),
        location: const GeoPoint(lat: 14.5995, lng: 120.9842),
        addressLabel: _address.text.trim(),
        startAt: startDt.toUtc(),
        endAt: endDt.toUtc(),
        pay: Money(amount: _payCentavos),
        category: _category,
      );
      if (!mounted) return;
      await widget.onCreated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job posted')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _formatDate(DateTime d) {
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _creamBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: const Color(0xFFF1F5F9),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.chevron_left_rounded,
                          size: 22,
                          color: _navyTitle,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Post a Job',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _navyTitle,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fill in the job details',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: _labelGrey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24, thickness: 1, color: _borderField),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Material(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Basic Info'),
                          const SizedBox(height: 18),
                          _labelRequired('Job Title'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _title,
                            onChanged: (_) => setState(() {}),
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: _navyTitle,
                            ),
                            decoration: _inputDecoration(
                              hint: 'e.g., Warehouse Picker, Service Crew',
                            ),
                          ),
                          const SizedBox(height: 18),
                          _labelRequired('Job Type'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _jobTypeKeys.map((k) {
                              final selected = _category == k;
                              return ChoiceChip(
                                label: Text(k),
                                selected: selected,
                                onSelected: (_) =>
                                    setState(() => _category = k),
                                selectedColor: AgapColors.mintSoft,
                                backgroundColor: const Color(0xFFF1F5F9),
                                labelStyle: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? AgapColors.businessGreenDeep
                                      : _labelGrey,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: selected
                                        ? AgapColors.businessGreen
                                        : _borderField,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 18),
                          _labelRequired('Job Description'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _desc,
                            onChanged: (_) => setState(() {}),
                            maxLines: 4,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _navyTitle,
                              height: 1.45,
                            ),
                            decoration: _inputDecoration(
                              hint:
                                  'Describe the tasks, expectations, and anything workers should know...',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Schedule'),
                          const SizedBox(height: 18),
                          _labelRequired('Date'),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: _inputDecoration().copyWith(
                                suffixIcon: const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 20,
                                  color: _labelGrey,
                                ),
                              ),
                              child: Text(
                                _startDate == null
                                    ? 'mm/dd/yyyy'
                                    : _formatDate(_startDate!),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: _startDate == null
                                      ? _labelGrey
                                      : _navyTitle,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _labelRequired('Start Time'),
                                    const SizedBox(height: 8),
                                    InkWell(
                                      onTap: _pickStartTime,
                                      borderRadius: BorderRadius.circular(12),
                                      child: InputDecorator(
                                        decoration: _inputDecoration()
                                            .copyWith(
                                          suffixIcon: const Icon(
                                            Icons.schedule_rounded,
                                            size: 20,
                                            color: _labelGrey,
                                          ),
                                        ),
                                        child: Text(
                                          _startTime == null
                                              ? '--:-- --'
                                              : _formatTime(_startTime!),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: _startTime == null
                                                ? _labelGrey
                                                : _navyTitle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _labelRequired('End Time'),
                                    const SizedBox(height: 8),
                                    InkWell(
                                      onTap: _pickEndTime,
                                      borderRadius: BorderRadius.circular(12),
                                      child: InputDecorator(
                                        decoration: _inputDecoration()
                                            .copyWith(
                                          suffixIcon: const Icon(
                                            Icons.schedule_rounded,
                                            size: 20,
                                            color: _labelGrey,
                                          ),
                                        ),
                                        child: Text(
                                          _endTime == null
                                              ? '--:-- --'
                                              : _formatTime(_endTime!),
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: _endTime == null
                                                ? _labelGrey
                                                : _navyTitle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Location'),
                          const SizedBox(height: 18),
                          _labelRequired('Work Site Address'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _address,
                            onChanged: (_) => setState(() {}),
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            decoration: _inputDecoration(
                              hint: 'Street, Building, City',
                            ).copyWith(
                              prefixIcon: const Icon(
                                Icons.place_outlined,
                                color: _labelGrey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Hiring & Pay'),
                          const SizedBox(height: 18),
                          Text(
                            'Number of Workers Needed',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _navyTitle,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Material(
                                color: const Color(0xFFE2E8F0),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => setState(() {
                                    if (_workersNeeded > 1) _workersNeeded--;
                                  }),
                                  child: const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(Icons.remove, size: 18),
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  '$_workersNeeded',
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: _navyTitle,
                                  ),
                                ),
                              ),
                              Material(
                                color: _chipOrange.withValues(alpha: 0.25),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => setState(() {
                                    if (_workersNeeded < 99) {
                                      _workersNeeded++;
                                    }
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Icon(
                                      Icons.add,
                                      size: 18,
                                      color: _chipOrangeDeep,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Pay Rate',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _navyTitle,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _payRate,
                                  onChanged: (_) => setState(() {}),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                  decoration: _inputDecoration(
                                    hint: '850',
                                  ).copyWith(
                                    prefixText: '₱ ',
                                    prefixStyle: GoogleFonts.inter(
                                      fontWeight: FontWeight.w800,
                                      color: _navyTitle,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: _PayUnitToggle(
                                  value: _payUnit,
                                  onChanged: (u) =>
                                      setState(() => _payUnit = u),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Minimum ₱${_minRatePhp.toStringAsFixed(0)} · Total estimate ₱${(_payCentavos / 100).toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _labelGrey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Mark as Urgent',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: _navyTitle,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Workers will be prioritized',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: _labelGrey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _urgent,
                                activeThumbColor: AgapColors.businessGreen,
                                onChanged: (v) => setState(() => _urgent = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Requirements & Benefits'),
                          const SizedBox(height: 18),
                          Text(
                            'Requirements',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _navyTitle,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _requirements,
                            onChanged: (_) => setState(() {}),
                            maxLines: 3,
                            style: GoogleFonts.inter(fontSize: 14),
                            decoration: _inputDecoration(
                              hint:
                                  'Age, physical requirements, experience needed...',
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Benefits',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _navyTitle,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _benefits,
                            onChanged: (_) => setState(() {}),
                            maxLines: 3,
                            style: GoogleFonts.inter(fontSize: 14),
                            decoration: _inputDecoration(
                              hint: 'Meals, transportation, uniform...',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _canSubmit
                              ? AgapColors.businessGreen
                              : const Color(0xFFE2E8F0),
                          foregroundColor: _canSubmit
                              ? Colors.white
                              : const Color(0xFF94A3B8),
                          disabledBackgroundColor: const Color(0xFFE2E8F0),
                          disabledForegroundColor: const Color(0xFF94A3B8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: _canSubmit ? 2 : 0,
                        ),
                        onPressed: (_submitting || !_canSubmit) ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Post Job Now',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Text(
      t,
      style: GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: _navyTitle,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _labelRequired(String t) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _labelGrey,
        ),
        children: [
          TextSpan(text: t),
          TextSpan(
            text: ' *',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: Colors.red.shade600,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        color: const Color(0xFF94A3B8),
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderField),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderField),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: AgapColors.businessGreen,
          width: 1.5,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PayUnitToggle extends StatelessWidget {
  const _PayUnitToggle({
    required this.value,
    required this.onChanged,
  });

  final _PayUnit value;
  final ValueChanged<_PayUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _unitChip('/day', _PayUnit.day),
          _unitChip('/hr', _PayUnit.hour),
          _unitChip('/shift', _PayUnit.shift),
        ],
      ),
    );
  }

  Widget _unitChip(String label, _PayUnit unit) {
    final selected = value == unit;
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        elevation: selected ? 1 : 0,
        shadowColor: Colors.black26,
        child: InkWell(
          onTap: () => onChanged(unit),
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? const Color(0xFF0F172A)
                    : AgapColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

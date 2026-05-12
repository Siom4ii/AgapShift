import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/models.dart';
import '../../../location/davao_del_sur_scope.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../billing/paymongo_billing_service.dart';
import '../../../subscriptions/revenue_stub_service.dart';
import '../../../supabase/supabase_config.dart';
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
  final _otherJobType = TextEditingController();

  String _category = 'Warehouse';
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  int _workersNeeded = 1;
  _PayUnit _payUnit = _PayUnit.day;
  bool _urgent = false;

  bool _submitting = false;
  bool _payingEmployerSubscription = false;
  String? _error;
  /// From `employer_entitlements.jobs_posted_count` when Supabase is on.
  int? _employerJobsPostedCount;
  /// `subscription_expires_at` (or legacy `verification_fee_paid_until`).
  DateTime? _employerSubscriptionUntil;
  bool _wantBoost = false;

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

  bool get _employerSubscriptionOk {
    if (!SupabaseConfig.isConfigured) return true;
    final c = _employerJobsPostedCount;
    if (c == null) return true;
    if (c < 1) return true;
    final v = _employerSubscriptionUntil;
    if (v == null) return false;
    return v.isAfter(DateTime.now());
  }

  bool get _canSubmit {
    if (_title.text.trim().isEmpty) return false;
    if (_desc.text.trim().isEmpty) return false;
    if (_address.text.trim().isEmpty) return false;
    if (_startDate == null ||
        _endDate == null ||
        _startTime == null ||
        _endTime == null) {
      return false;
    }
    if (_category == 'Other' && _otherJobType.text.trim().isEmpty) return false;
    final rate = double.tryParse(_payRate.text.trim()) ?? 0;
    if (rate < _minRatePhp) return false;
    final startDt = _composeDateTime(_startDate!, _startTime!);
    final endDt = _composeDateTime(_endDate!, _endTime!);
    if (!endDt.isAfter(startDt)) return false;
    if (!_employerSubscriptionOk) return false;
    return true;
  }

  DateTime _composeDateTime(DateTime d, TimeOfDay t) {
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  int get _payCentavos {
    if (_startDate == null ||
        _endDate == null ||
        _startTime == null ||
        _endTime == null) {
      return 0;
    }
    final ratePhp = double.tryParse(_payRate.text.trim()) ?? 0;
    final rateCentavos = (ratePhp * 100).round();
    final workers = _workersNeeded.clamp(1, 999);
    final startDt = _composeDateTime(_startDate!, _startTime!);
    final endDt = _composeDateTime(_startDate!, _endTime!);
    final hoursPerDay =
        endDt.difference(startDt).inMinutes.clamp(1, 24 * 60) / 60.0;
    final days = _daysInclusive(_startDate!, _endDate!);

    switch (_payUnit) {
      case _PayUnit.hour:
        return (rateCentavos * hoursPerDay * days * workers).round();
      case _PayUnit.day:
        return rateCentavos * days * workers;
      case _PayUnit.shift:
        return rateCentavos * workers; // one-time per gig
    }
  }

  int _daysInclusive(DateTime a, DateTime b) {
    final s = DateTime(a.year, a.month, a.day);
    final e = DateTime(b.year, b.month, b.day);
    if (e.isBefore(s)) return 0;
    return e.difference(s).inDays + 1;
  }

  String _effectiveCategory() {
    if (_category != 'Other') return _category;
    final spec = _otherJobType.text.trim();
    if (spec.isEmpty) return _category;
    return 'Other - $spec';
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
  void initState() {
    super.initState();
    _loadEmployerPostCount();
  }

  Future<void> _loadEmployerPostCount() async {
    if (!SupabaseConfig.isConfigured) return;
    final id = appActorId(widget.session, mockFallback: '');
    if (id.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('employer_entitlements')
          .select(
            'jobs_posted_count, subscription_expires_at, verification_fee_paid_until',
          )
          .eq('business_id', id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        if (row == null) {
          _employerJobsPostedCount = 0;
          _employerSubscriptionUntil = null;
        } else {
          final n = row['jobs_posted_count'];
          _employerJobsPostedCount =
              n is int ? n : int.tryParse('$n') ?? 0;
          final sub = row['subscription_expires_at'];
          final leg = row['verification_fee_paid_until'];
          final subDt =
              sub == null ? null : DateTime.parse(sub as String);
          final legDt =
              leg == null ? null : DateTime.parse(leg as String);
          _employerSubscriptionUntil = subDt ?? legDt;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _employerJobsPostedCount = null;
          _employerSubscriptionUntil = null;
        });
      }
    }
  }

  Future<void> _payEmployerSubscription() async {
    final id = appActorId(widget.session, mockFallback: '');
    if (id.isEmpty) return;
    setState(() => _payingEmployerSubscription = true);
    try {
      final url = await PaymongoBillingService.startCheckout(
        product: BillingProduct.employerSub,
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
        const SnackBar(content: Text('Pay in PayMongo, then tap Refresh.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment could not be started.')),
      );
    } finally {
      if (mounted) setState(() => _payingEmployerSubscription = false);
      if (mounted) await _loadEmployerPostCount();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _address.dispose();
    _payRate.dispose();
    _requirements.dispose();
    _benefits.dispose();
    _otherJobType.dispose();
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
    if (d != null) {
      setState(() {
        _startDate = d;
        _endDate ??= d;
        if (_endDate != null && _endDate!.isBefore(d)) {
          _endDate = d;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final start = _startDate ?? now.add(const Duration(days: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: _endDate ?? start,
      firstDate: start,
      lastDate: start.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _endDate = d);
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
    if (_startDate == null ||
        _endDate == null ||
        _startTime == null ||
        _endTime == null) {
      setState(() => _error = 'Please set start date, end date, start time, and end time.');
      return false;
    }
    if (_category == 'Other' && _otherJobType.text.trim().isEmpty) {
      setState(() => _error = 'Please specify the job type.');
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
    final endDt = _composeDateTime(_endDate!, _endTime!);
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
      final endDt = _composeDateTime(_endDate!, _endTime!);

      await widget.repo.createGig(
        businessId: businessId,
        title: _title.text.trim(),
        description: _buildDescriptionBody(),
        location: DavaoDelSurScope.defaultCenter,
        addressLabel: _address.text.trim(),
        startAt: startDt.toUtc(),
        endAt: endDt.toUtc(),
        pay: Money(amount: _payCentavos),
        category: _effectiveCategory(),
        workersNeeded: _workersNeeded.clamp(1, 999),
        isUrgent: _urgent,
        boostedUntil: _wantBoost ? RevenueStubService.boostedUntilNow() : null,
      );
      if (!mounted) return;
      await _loadEmployerPostCount();
      await widget.onCreated();
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
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
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
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Post a Job',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _navyTitle,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Fill in the job details',
                            style: GoogleFonts.inter(
                              fontSize: 13,
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
            const Divider(height: 16, thickness: 1, color: _borderField),
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
                    if (SupabaseConfig.isConfigured &&
                        _employerJobsPostedCount != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _EmployerPostingFeeNotice(
                          jobsPostedCount: _employerJobsPostedCount!,
                          subscriptionActive: _employerSubscriptionOk,
                          payBusy: _payingEmployerSubscription,
                          onPaySubscription: _payEmployerSubscription,
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
                                onSelected: (_) => setState(() => _category = k),
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
                          if (_category == 'Other') ...[
                            const SizedBox(height: 14),
                            _labelRequired('Specify job type'),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _otherJobType,
                              onChanged: (_) => setState(() {}),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: _navyTitle,
                              ),
                              decoration: _inputDecoration(
                                hint: 'e.g., Data Entry / Admin',
                              ),
                            ),
                          ],
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
                          _labelRequired('Start Date'),
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
                          const SizedBox(height: 14),
                          _labelRequired('End Date'),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: _pickEndDate,
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
                                _endDate == null
                                    ? 'mm/dd/yyyy'
                                    : _formatDate(_endDate!),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: _endDate == null
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
                          if (_startDate != null &&
                              _endDate != null &&
                              _startTime != null &&
                              _endTime != null) ...[
                            const SizedBox(height: 14),
                            Builder(
                              builder: (context) {
                                final days = _daysInclusive(_startDate!, _endDate!);
                                final startDt = _composeDateTime(_startDate!, _startTime!);
                                final endDt = _composeDateTime(_startDate!, _endTime!);
                                final hoursPerDay =
                                    endDt.difference(startDt).inMinutes.clamp(1, 24 * 60) / 60.0;
                                final dLabel = days == 1 ? '1 day' : '$days days';
                                final hLabel = '${hoursPerDay.toStringAsFixed(1)} hrs/day';
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: _borderField),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.timelapse_rounded,
                                        size: 18,
                                        color: _labelGrey,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Duration: $dLabel • $hLabel',
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: _labelGrey,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
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
                              Switch(
                                value: _urgent,
                                onChanged: (v) => setState(() => _urgent = v),
                                activeThumbColor: AgapColors.businessGreen,
                                activeTrackColor: AgapColors.businessGreen
                                    .withValues(alpha: 0.45),
                                inactiveTrackColor: const Color(0xFFE2E8F0),
                                inactiveThumbColor: const Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFFF7ED),
                                  Color(0xFFFFEDD5),
                                ],
                              ),
                              border: Border.all(
                                color: const Color(0xFFF59E0B).withValues(
                                  alpha: 0.55,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFF59E0B).withValues(
                                    alpha: 0.18,
                                  ),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          12,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.bolt_rounded,
                                        color: Colors.orange.shade800,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Boost visibility',
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                              color: const Color(0xFF9A3412),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Get up to ~3× more views at the top of worker feeds.',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              height: 1.35,
                                              color: const Color(0xFFB45309),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: _wantBoost,
                                      onChanged: (v) =>
                                          setState(() => _wantBoost = v),
                                      activeThumbColor: const Color(0xFFEA580C),
                                      activeTrackColor: const Color(0xFFEA580C)
                                          .withValues(alpha: 0.45),
                                      inactiveTrackColor:
                                          const Color(0xFFE2E8F0),
                                      inactiveThumbColor:
                                          const Color(0xFF94A3B8),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '₱${RevenueStubService.postBoostPhp} · '
                                  '${RevenueStubService.postBoostValidity.inDays} days (optional, demo)',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF92400E),
                                  ),
                                ),
                              ],
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

/// First job post free; 2nd+ requires employer subscription; optional boost.
class _EmployerPostingFeeNotice extends StatelessWidget {
  const _EmployerPostingFeeNotice({
    required this.jobsPostedCount,
    required this.subscriptionActive,
    this.payBusy = false,
    this.onPaySubscription,
  });

  /// Existing rows in `gigs` for this employer (before this draft is submitted).
  final int jobsPostedCount;
  final bool subscriptionActive;
  final bool payBusy;
  final Future<void> Function()? onPaySubscription;

  @override
  Widget build(BuildContext context) {
    final isFirst = jobsPostedCount == 0;
    final needsSubscription = !isFirst && !subscriptionActive;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFirst ? Icons.celebration_outlined : Icons.workspace_premium_outlined,
                size: 22,
                color: const Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isFirst
                      ? 'First job post is free'
                      : (subscriptionActive
                          ? 'Employer subscription active'
                          : 'Employer subscription required'),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E3A8A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isFirst
                ? 'Your first listing and hire are free, including any number of '
                    'workers on that post. From your second job posting onward, '
                    'subscribe at ₱${RevenueStubService.employerSubscriptionPhp}/month for '
                    'unlimited listings and hires.'
                : (subscriptionActive
                    ? 'You can post and hire without limits while your plan is active. '
                        'Optional: boost this post (₱${RevenueStubService.postBoostPhp}) for '
                        '${RevenueStubService.postBoostValidity.inDays} days at the top of worker feeds.'
                    : 'You already used your free post. Subscribe (₱${RevenueStubService.employerSubscriptionPhp}/mo, demo pay) '
                        'to publish more jobs and keep hiring.'),
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: const Color(0xFF1E40AF),
            ),
          ),
          if (needsSubscription && onPaySubscription != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: payBusy ? null : onPaySubscription,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDBEAFE),
                  foregroundColor: const Color(0xFF1E3A8A),
                ),
                child: payBusy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Subscribe (demo ₱${RevenueStubService.employerSubscriptionPhp}/mo)',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ],
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

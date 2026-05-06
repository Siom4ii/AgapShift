import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../marketplace/marketplace_scope.dart';
import '../../../onboarding/kyc_storage_service.dart';
import '../../../onboarding/supabase_onboarding_sync.dart';
import '../../../session/session_models.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/kyc_upload_zone.dart';
import 'davao_del_sur_locations.dart';
import 'onboarding_location_widgets.dart';

enum _CollegeTrack { none, undergraduate, graduate }

/// 6-step worker onboarding flow with animated progress bar.
class WorkerOnboardingScreen extends StatefulWidget {
  const WorkerOnboardingScreen({
    super.key,
    required this.onSubmit,
    required this.onBack,
  });

  final Future<void> Function() onSubmit;

  /// Called when the user presses the in-header back button (or the Android
  /// system back gesture) while on step 1. The onboarding screen is mounted
  /// directly by `SessionGate`, so `Navigator.maybePop` would be a silent
  /// no-op — the parent must transition the auth stage instead.
  final Future<void> Function() onBack;

  @override
  State<WorkerOnboardingScreen> createState() => _WorkerOnboardingScreenState();
}

class _WorkerOnboardingScreenState extends State<WorkerOnboardingScreen> {
  static const _totalSteps = 6;

  int _step = 0; // 0..5 (steps), 6 = submitted view.
  int _direction = 1; // +1 = forward (slide in from right), -1 = backward.
  bool _submitting = false;

  // Step 1 — Create Account
  final _email = TextEditingController();
  final _password = TextEditingController();
  /// Lazy so hot restart/reload never leaves this undefined on web (DDC).
  TextEditingController? _confirmPasswordCtl;
  TextEditingController get _confirmPassword =>
      _confirmPasswordCtl ??= TextEditingController();
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  // Step 2 — Personal Info
  final _fullName = TextEditingController();
  DateTime? _birthdate;
  final _phone = TextEditingController();
  final _address = TextEditingController();
  // Cascading address pickers (province is fixed to Davao del Sur).
  String? _municipality;
  String? _barangay;
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();

  // Step 3 — Identity Verification
  String? _govIdFile;
  String? _selfieFile;
  String? _govIdStoragePath;
  String? _selfieStoragePath;
  bool _kycBusy = false;

  // Step 4 — Resume & Skills (short-term / quick-hire roles)
  static const _availableSkills = [
    'Waiter / Service Crew',
    'Sales Associate / Sales Lady',
    'Cashier',
    'Helper / Utility Worker',
    'Dishwasher / Washer',
    'Stock Clerk / Inventory Assistant',
    'Promoter / Brand Ambassador',
    'Warehouse / Logistics',
    'Food Service (Kitchen)',
    'Retail / Sales',
    'Events & Promotions',
    'Delivery / Courier',
    'Cleaning / Janitorial',
    'Data Entry / Admin',
    'Customer Service',
    'Driver',
  ];
  final Set<String> _selectedSkills = {};
  final _customSkill = TextEditingController();
  final _bio = TextEditingController();
  final _workExp = TextEditingController();

  // Step 5 — Education
  final _elemSchool = TextEditingController();
  final _hsSchool = TextEditingController();
  final _shsSchool = TextEditingController();
  _CollegeTrack _collegeTrack = _CollegeTrack.none;
  final _collegeCourse = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await MarketplaceScope.of(context).session.refreshFromSupabaseProfile();
      if (!mounted) return;
      await _skipAccountStepIfAlreadySignedIn();
    });
  }

  /// Returning users with an existing session skip Create Account; users who
  /// tapped **Sign Up** (role-first) always see step 0 until they finish it.
  Future<void> _skipAccountStepIfAlreadySignedIn() async {
    final sessionCtrl = MarketplaceScope.of(context).session;
    if (!await sessionCtrl.shouldSkipOnboardingCreateAccountStep()) return;
    if (!mounted || _step != 0) return;
    final email = sessionCtrl.state.email;
    if (email != null && email.isNotEmpty) {
      _email.text = email;
    }
    setState(() => _step = 1);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPasswordCtl?.dispose();
    _fullName.dispose();
    _phone.dispose();
    _address.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _customSkill.dispose();
    _bio.dispose();
    _workExp.dispose();
    _elemSchool.dispose();
    _hsSchool.dispose();
    _shsSchool.dispose();
    _collegeCourse.dispose();
    super.dispose();
  }

  /// Both password fields have text but differ (for inline validation UI).
  bool get _passwordsMismatch {
    final p = _password.text;
    final c = _confirmPassword.text;
    if (p.isEmpty || c.isEmpty) return false;
    return p != c;
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        final emailOk = _email.text.trim().contains('@');
        final passOk = _password.text.length >= 6 &&
            _password.text == _confirmPassword.text;
        return emailOk && passOk;
      case 1:
        return _fullName.text.trim().isNotEmpty &&
            _birthdate != null &&
            _isValidPhMobile(_phone.text) &&
            _municipality != null &&
            _barangay != null &&
            _emergencyName.text.trim().isNotEmpty &&
            _isValidPhMobile(_emergencyPhone.text);
      case 2:
        return _govIdFile != null && _selfieFile != null;
      case 3:
        return _selectedSkills.isNotEmpty;
      case 4:
        return _educationStepValid();
      case 5:
        return true;
      default:
        return false;
    }
  }

  /// PH mobile format: exactly 11 digits, starts with `09`.
  bool _isValidPhMobile(String value) {
    final t = value.trim();
    return t.length == 11 &&
        t.startsWith('09') &&
        RegExp(r'^[0-9]+$').hasMatch(t);
  }

  bool _educationStepValid() {
    bool filled(String s) => s.trim().isNotEmpty;
    if (!filled(_elemSchool.text) ||
        !filled(_hsSchool.text) ||
        !filled(_shsSchool.text)) {
      return false;
    }
    if (_collegeTrack == _CollegeTrack.none) return true;
    return filled(_collegeCourse.text);
  }

  String _educationReviewSummary() {
    final college = switch (_collegeTrack) {
      _CollegeTrack.none => 'College: None',
      _CollegeTrack.undergraduate =>
        'College (Undergraduate): ${_collegeCourse.text.trim()}',
      _CollegeTrack.graduate =>
        'College (Graduate): ${_collegeCourse.text.trim()}',
    };
    return 'Elementary: ${_elemSchool.text.trim()}\n'
        'High school: ${_hsSchool.text.trim()}\n'
        'Senior high: ${_shsSchool.text.trim()}\n'
        '$college';
  }

  String get _stepTitle {
    switch (_step) {
      case 0:
        return 'Create Account';
      case 1:
        return 'Personal Info';
      case 2:
        return 'Identity Verification';
      case 3:
        return 'Skills & Experience';
      case 4:
        return 'Education';
      case 5:
        return 'Review';
      default:
        return '';
    }
  }

  Future<void> _next() async {
    if (!_canContinue || _submitting) return;

    if (_step == 0 && SupabaseConfig.isConfigured) {
      setState(() => _submitting = true);
      final session = MarketplaceScope.of(context).session;
      final result = await session.signUpWithEmailPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      setState(() => _submitting = false);

      switch (result) {
        case SignUpResult.skipped:
        case SignUpResult.success:
          break;
        case SignUpResult.emailAlreadyRegistered:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This email is already in use. Sign in from the login screen, '
                'or use the password for this email.',
              ),
            ),
          );
          return;
        case SignUpResult.weakPassword:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Password was rejected. Try a stronger password (often 6+ chars).',
              ),
            ),
          );
          return;
        case SignUpResult.unexpectedError:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not create account. Try again.'),
            ),
          );
          return;
      }
    }

    if (_step < _totalSteps - 1) {
      final completed = _step;
      setState(() {
        _direction = 1;
        _step += 1;
      });
      if (completed == 0) {
        await MarketplaceScope.of(context).session.markOnboardingAccountStepFinished();
      }
    } else {
      await _submitWorkerResponsesToSupabase();
      await _submitApplication();
    }
  }

  /// Writes onboarding answers only after the user completes the full wizard.
  Future<void> _submitWorkerResponsesToSupabase() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      await SupabaseOnboardingSync.saveWorker(
        _buildWorkerPayload(completedStep: 5),
      );
    } catch (_) {}
  }

  Map<String, dynamic> _buildWorkerPayload({required int completedStep}) {
    final m = <String, dynamic>{
      'schema_version': 1,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (completedStep >= 0) {
      final em = _email.text.trim();
      if (em.isNotEmpty) m['email'] = em;
    }
    if (completedStep >= 1) {
      m['personal'] = {
        'full_name': _fullName.text.trim(),
        'birthdate': _birthdate?.toIso8601String(),
        'phone': _phone.text.trim(),
        'municipality': _municipality,
        'barangay': _barangay,
        'address_line': _address.text.trim(),
        'emergency_contact_name': _emergencyName.text.trim(),
        'emergency_contact_phone': _emergencyPhone.text.trim(),
      };
    }
    if (completedStep >= 2) {
      final identity = <String, dynamic>{};
      KycStorageService.putFileRef(
        identity,
        'government_id',
        _govIdFile,
        _govIdStoragePath,
      );
      KycStorageService.putFileRef(
        identity,
        'selfie',
        _selfieFile,
        _selfieStoragePath,
      );
      m['identity'] = identity;
    }
    if (completedStep >= 3) {
      m['resume'] = {
        'skills': _selectedSkills.toList(),
        'bio': _bio.text.trim(),
        'work_experience': _workExp.text.trim(),
      };
    }
    if (completedStep >= 4) {
      m['education'] = {
        'elementary_school': _elemSchool.text.trim(),
        'high_school': _hsSchool.text.trim(),
        'senior_high_school': _shsSchool.text.trim(),
        'college_track': _collegeTrack.name,
        'college_course': _collegeCourse.text.trim(),
      };
    }
    return m;
  }

  void _back() {
    if (_submitting) return;
    if (_step == 0) {
      widget.onBack();
      return;
    }
    setState(() {
      _direction = -1;
      _step -= 1;
    });
  }

  Future<void> _submitApplication() async {
    setState(() => _submitting = true);
    if (SupabaseConfig.isConfigured) {
      await SupabaseOnboardingSync.syncProfileIdentitySnapshot(
        flow: 'worker',
        snapshot: _buildWorkerPayload(completedStep: 5),
      );
    }
    if (!mounted) return;
    // Persist this email as a registered account so the user can log back in
    // afterwards using the new login screen.
    final email = _email.text.trim();
    if (email.isNotEmpty) {
      await MarketplaceScope.of(context).session.registerEmail(email);
    }
    // Simulate the brief admin-review animation, then hand off.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _step = _totalSteps; // Show submitted view.
    });
    // After a short demo delay drop the user into the dashboard with limited
    // (pending) access — the dashboard itself shows the verification banner.
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await widget.onSubmit();
    });
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    // 18+ requirement: latest selectable date is exactly 18 years ago today.
    final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(now.year - 22, now.month, now.day),
      firstDate: DateTime(now.year - 80),
      lastDate: eighteenYearsAgo,
      helpText: 'Select your birthdate (18+)',
    );
    if (picked != null) {
      setState(() => _birthdate = picked);
    }
  }

  Future<void> _pickMunicipality() async {
    final picked = await showLocationOptionPicker(
      context: context,
      title: 'Select Municipality',
      options: DavaoDelSur.municipalities,
      selected: _municipality,
    );
    if (picked == null) return;
    setState(() {
      _municipality = picked;
      // Reset barangay whenever the municipality changes.
      _barangay = null;
      _address.text = DavaoDelSur.formatAddress(
        barangay: _barangay,
        municipality: _municipality,
      );
    });
  }

  Future<void> _pickBarangay() async {
    final muni = _municipality;
    if (muni == null) return;
    final list = DavaoDelSur.barangays[muni] ?? const <String>[];
    final picked = await showLocationOptionPicker(
      context: context,
      title: 'Select Barangay',
      options: list,
      selected: _barangay,
    );
    if (picked == null) return;
    setState(() {
      _barangay = picked;
      _address.text = DavaoDelSur.formatAddress(
        barangay: _barangay,
        municipality: _municipality,
      );
    });
  }

  Future<void> _pickGovId() async {
    final file = await pickKycDocumentFile();
    if (!mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No file selected.'),
          action: SnackBarAction(
            label: 'Use demo',
            onPressed: () => setState(() {
              _govIdFile = 'demo_government_id.jpg';
              _govIdStoragePath = null;
            }),
          ),
        ),
      );
      return;
    }

    final label = kycFileLabel(file);
    if (!SupabaseConfig.isConfigured) {
      setState(() {
        _govIdFile = label;
        _govIdStoragePath = null;
      });
      return;
    }

    setState(() => _kycBusy = true);
    try {
      final path = await KycStorageService.upload(
        file: file,
        flow: 'worker',
        documentType: 'government_id',
      );
      if (!mounted) return;
      setState(() {
        _govIdFile = label;
        _govIdStoragePath = path;
      });
    } on KycUploadTooLargeException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File must be 10MB or smaller.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload ID: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _kycBusy = false);
    }
  }

  Future<void> _captureSelfie() async {
    final file = await pickKycSelfieImageFile();
    if (!mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No selfie selected.'),
          action: SnackBarAction(
            label: 'Use demo',
            onPressed: () => setState(() {
              _selfieFile = 'demo_selfie.jpg';
              _selfieStoragePath = null;
            }),
          ),
        ),
      );
      return;
    }

    final label = kycFileLabel(file);
    if (!SupabaseConfig.isConfigured) {
      setState(() {
        _selfieFile = label;
        _selfieStoragePath = null;
      });
      return;
    }

    setState(() => _kycBusy = true);
    try {
      final path = await KycStorageService.upload(
        file: file,
        flow: 'worker',
        documentType: 'selfie',
      );
      if (!mounted) return;
      setState(() {
        _selfieFile = label;
        _selfieStoragePath = path;
      });
    } on KycUploadTooLargeException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File must be 10MB or smaller.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload selfie: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _kycBusy = false);
    }
  }

  void _addCustomSkill() {
    final raw = _customSkill.text.trim();
    if (raw.isEmpty) return;
    // Match against the preset list and any already-selected skill case-
    // insensitively so we don't create dupes that only differ in casing.
    final lower = raw.toLowerCase();
    final isPreset = _availableSkills.any((s) => s.toLowerCase() == lower);
    final alreadySelected = _selectedSkills.any(
      (s) => s.toLowerCase() == lower,
    );
    if (isPreset) {
      // Just toggle the matching preset on instead of adding a duplicate.
      final preset = _availableSkills.firstWhere(
        (s) => s.toLowerCase() == lower,
      );
      setState(() {
        _selectedSkills.add(preset);
        _customSkill.clear();
      });
      return;
    }
    if (alreadySelected) {
      setState(() => _customSkill.clear());
      return;
    }
    setState(() {
      _selectedSkills.add(raw);
      _customSkill.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_step >= _totalSteps) {
      return _ApplicationSubmittedView(email: _email.text.trim());
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _back();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F4FB),
        body: SafeArea(
          child: Column(
            children: [
              _OnboardingHeader(
                step: _step,
                total: _totalSteps,
                title: _stepTitle,
                onBack: _back,
              ),
              Expanded(
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 360),
                    reverseDuration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      // Outgoing renders BELOW so it never paints on top of the
                      // incoming step.
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: <Widget>[
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (child, anim) {
                      final isIncoming = child.key == ValueKey<int>(_step);
                      // For both incoming and outgoing the controller advances
                      // from 0→1 (incoming) or 1→0 (outgoing).
                      //
                      // Both tweens end at Offset.zero, but begin at opposite
                      // sides depending on direction so the outgoing step slides
                      // OFF in the opposite direction of the incoming step.
                      final begin = isIncoming
                          ? Offset(_direction.toDouble(), 0) // e.g. (+1, 0)
                          : Offset(-_direction.toDouble(), 0); // e.g. (-1, 0)
                      final position = Tween<Offset>(
                        begin: begin,
                        end: Offset.zero,
                      ).animate(anim);
                      return SlideTransition(
                        position: position,
                        child: FadeTransition(
                          // anim runs 0→1 on entry and 1→0 on exit, so this
                          // fades both in/out correctly with no inversion.
                          opacity: anim,
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey<int>(_step),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        physics: const ClampingScrollPhysics(),
                        child: _buildStepBody(),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _canContinue && !_submitting
                          ? AgapColors.brandWordmarkBlue
                          : const Color(0xFFCBD5E1),
                      foregroundColor: Colors.white,
                      elevation: _canContinue && !_submitting ? 8 : 0,
                      shadowColor: AgapColors.brandWordmarkBlue.withValues(
                        alpha: 0.30,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _canContinue && !_submitting ? () => _next() : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _step == _totalSteps - 1
                                ? 'Submit Application'
                                : 'Continue',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
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

  Widget _buildStepBody() {
    final body = _buildStepInner();
    // Staggered right→left cascade for the step's elements on every change.
    return _CascadeIn(direction: _direction, child: body);
  }

  Widget _buildStepInner() {
    switch (_step) {
      case 0:
        return _CreateAccountStep(
          email: _email,
          password: _password,
          confirmPassword: _confirmPassword,
          passwordsMismatch: _passwordsMismatch,
          passwordVisible: _passwordVisible,
          confirmPasswordVisible: _confirmPasswordVisible,
          onTogglePassword: () =>
              setState(() => _passwordVisible = !_passwordVisible),
          onToggleConfirmPassword: () => setState(
            () => _confirmPasswordVisible = !_confirmPasswordVisible,
          ),
          onChanged: () => setState(() {}),
        );
      case 1:
        return _PersonalInfoStep(
          fullName: _fullName,
          birthdate: _birthdate,
          phone: _phone,
          municipality: _municipality,
          barangay: _barangay,
          emergencyName: _emergencyName,
          emergencyPhone: _emergencyPhone,
          onPickBirthdate: _pickBirthdate,
          onPickMunicipality: _pickMunicipality,
          onPickBarangay: _pickBarangay,
          onChanged: () => setState(() {}),
        );
      case 2:
        return _IdentityStep(
          govIdFile: _govIdFile,
          selfieFile: _selfieFile,
          kycBusy: _kycBusy,
          onPickGovId: _pickGovId,
          onCaptureSelfie: _captureSelfie,
        );
      case 3:
        return _ResumeSkillsStep(
          allSkills: _availableSkills,
          selected: _selectedSkills,
          customSkill: _customSkill,
          bio: _bio,
          workExp: _workExp,
          onToggle: (s) => setState(() {
            if (_selectedSkills.contains(s)) {
              _selectedSkills.remove(s);
            } else {
              _selectedSkills.add(s);
            }
          }),
          onAddCustomSkill: _addCustomSkill,
          onRemoveCustomSkill: (s) => setState(() => _selectedSkills.remove(s)),
        );
      case 4:
        return _EducationStep(
          elementary: _elemSchool,
          highSchool: _hsSchool,
          seniorHigh: _shsSchool,
          collegeCourse: _collegeCourse,
          collegeTrack: _collegeTrack,
          onCollegeTrack: (t) => setState(() {
            _collegeTrack = t;
            if (t == _CollegeTrack.none) _collegeCourse.clear();
          }),
          onChanged: () => setState(() {}),
        );
      case 5:
        return _ReviewStep(
          email: _email.text.trim(),
          fullName: _fullName.text.trim(),
          phone: _phone.text.trim(),
          address: _address.text.trim(),
          skills: _selectedSkills,
          educationSummary: _educationReviewSummary(),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Header with back button, "Step X of N", title, and an animated progress bar.
class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({
    required this.step,
    required this.total,
    required this.title,
    required this.onBack,
  });

  final int step;
  final int total;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final value = (step + 1) / total;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 20, 18),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Material(
                color: const Color(0xFFEEF2F7),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onBack,
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step ${step + 1} of $total',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Animated progress bar — eases between values whenever step changes.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: const Color(0xFFEDEAF6),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AgapColors.brandWordmarkBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Step 1: Create Account ----------

class _CreateAccountStep extends StatelessWidget {
  const _CreateAccountStep({
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.passwordsMismatch,
    required this.passwordVisible,
    required this.confirmPasswordVisible,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onChanged,
  });

  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController confirmPassword;
  final bool passwordsMismatch;
  final bool passwordVisible;
  final bool confirmPasswordVisible;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmPassword;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIcon(icon: Icons.alternate_email_rounded),
        const SizedBox(height: 12),
        _StepCaption('Enter your email to create your worker account'),
        const SizedBox(height: 22),
        const _FieldLabel('Email Address'),
        _RoundedField(
          controller: email,
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Password'),
        _RoundedField(
          controller: password,
          hint: 'Create a strong password',
          hasError: passwordsMismatch,
          obscureText: !passwordVisible,
          suffix: IconButton(
            icon: Icon(
              passwordVisible
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              color: const Color(0xFF94A3B8),
              size: 20,
            ),
            onPressed: onTogglePassword,
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Confirm Password'),
        _RoundedField(
          controller: confirmPassword,
          hint: 'Re-enter your password',
          hasError: passwordsMismatch,
          errorMessage:
              passwordsMismatch ? 'Passwords do not match' : null,
          obscureText: !confirmPasswordVisible,
          suffix: IconButton(
            icon: Icon(
              confirmPasswordVisible
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              color: const Color(0xFF94A3B8),
              size: 20,
            ),
            onPressed: onToggleConfirmPassword,
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

// ---------- Step 2: Personal Info ----------

class _PersonalInfoStep extends StatelessWidget {
  const _PersonalInfoStep({
    required this.fullName,
    required this.birthdate,
    required this.phone,
    required this.municipality,
    required this.barangay,
    required this.emergencyName,
    required this.emergencyPhone,
    required this.onPickBirthdate,
    required this.onPickMunicipality,
    required this.onPickBarangay,
    required this.onChanged,
  });

  final TextEditingController fullName;
  final DateTime? birthdate;
  final TextEditingController phone;
  final String? municipality;
  final String? barangay;
  final TextEditingController emergencyName;
  final TextEditingController emergencyPhone;
  final VoidCallback onPickBirthdate;
  final VoidCallback onPickMunicipality;
  final VoidCallback onPickBarangay;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final dateText = birthdate == null
        ? 'mm/dd/yyyy'
        : '${birthdate!.month.toString().padLeft(2, '0')}/${birthdate!.day.toString().padLeft(2, '0')}/${birthdate!.year}';
    final barangayDisabled = municipality == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIcon(icon: Icons.person_rounded),
        const SizedBox(height: 12),
        _StepCaption('Tell us about yourself'),
        const SizedBox(height: 22),
        const _FieldLabel('Full Name'),
        _RoundedField(
          controller: fullName,
          hint: 'Juan dela Cruz',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 16),
        const _FieldLabel('Birthdate'),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPickBirthdate,
          child: IgnorePointer(
            child: _RoundedField(
              controller: TextEditingController(text: dateText),
              hint: 'mm/dd/yyyy',
              suffix: const Icon(
                Icons.calendar_today_rounded,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
        ),
        _FieldHint('You must be at least 18 years old.'),
        const SizedBox(height: 16),
        const _FieldLabel('Phone Number'),
        _PhoneField(controller: phone, onChanged: onChanged),
        const SizedBox(height: 16),
        const _FieldLabel('Province'),
        OnboardingLocationSelectField(
          value: DavaoDelSur.province,
          hint: DavaoDelSur.province,
          enabled: false,
          icon: Icons.flag_rounded,
        ),
        const SizedBox(height: 12),
        const _FieldLabel('Municipality'),
        OnboardingLocationSelectField(
          value: municipality,
          hint: 'Select municipality',
          enabled: true,
          icon: Icons.location_city_rounded,
          onTap: onPickMunicipality,
        ),
        const SizedBox(height: 12),
        const _FieldLabel('Barangay'),
        OnboardingLocationSelectField(
          value: barangay,
          hint: barangayDisabled
              ? 'Pick a municipality first'
              : 'Select barangay',
          enabled: !barangayDisabled,
          icon: Icons.holiday_village_rounded,
          onTap: barangayDisabled ? null : onPickBarangay,
        ),
        const SizedBox(height: 16),
        const _FieldLabel('Emergency Contact Name'),
        _RoundedField(
          controller: emergencyName,
          hint: 'Full name',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 12),
        const _FieldLabel('Emergency Contact Number'),
        _PhoneField(controller: emergencyPhone, onChanged: onChanged),
      ],
    );
  }
}

/// Reusable PH-mobile field: digits-only, max 11 chars, must start with 09.
/// Surfaces inline error text once the user starts typing something invalid.
class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final raw = controller.text;
    String? errorText;
    if (raw.isNotEmpty) {
      if (raw.length < 2) {
        errorText = 'Must start with 09';
      } else if (!raw.startsWith('09')) {
        errorText = 'Must start with 09';
      } else if (raw.length < 11) {
        errorText = 'Phone must be 11 digits (${raw.length}/11)';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoundedField(
          controller: controller,
          hint: '09XXXXXXXXX',
          keyboardType: TextInputType.phone,
          maxLength: 11,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 4),
        if (errorText != null)
          Text(
            errorText,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFEF4444),
            ),
          )
        else
          Text(
            '11 digits, must start with 09.',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF94A3B8),
            ),
          ),
      ],
    );
  }
}

class _FieldHint extends StatelessWidget {
  const _FieldHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}

// ---------- Step 3: Identity Verification ----------

class _IdentityStep extends StatelessWidget {
  const _IdentityStep({
    required this.govIdFile,
    required this.selfieFile,
    required this.kycBusy,
    required this.onPickGovId,
    required this.onCaptureSelfie,
  });

  final String? govIdFile;
  final String? selfieFile;
  final bool kycBusy;
  final VoidCallback onPickGovId;
  final VoidCallback onCaptureSelfie;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIcon(icon: Icons.badge_outlined),
        const SizedBox(height: 12),
        _StepCaption('Verify your identity to unlock all features'),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFCD9A0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why we need this',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF92400E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Identity verification ensures trust and safety for all users on the platform.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.4,
                  color: const Color(0xFFB45309),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _FieldLabel('Government ID'),
        _UploadDropZone(
          icon: Icons.upload_rounded,
          title: govIdFile == null ? 'Upload Government ID' : 'Uploaded',
          subtitle:
              govIdFile ??
              'SSS ID, UMID, PhilHealth, Passport, Driver\'s License',
          actionLabel: govIdFile == null ? 'Choose File' : 'Replace File',
          onAction: onPickGovId,
          disabled: kycBusy,
        ),
        const SizedBox(height: 18),
        _FieldLabel('Liveness Check (Selfie)'),
        _UploadDropZone(
          icon: Icons.photo_camera_outlined,
          title: selfieFile == null ? 'Take a Selfie' : 'Selfie captured',
          subtitle:
              selfieFile ?? 'We\'ll compare your selfie with your ID photo',
          actionLabel: selfieFile == null ? 'Open Camera' : 'Retake',
          onAction: onCaptureSelfie,
          circle: true,
          disabled: kycBusy,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE6FBF1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFB7EAD2)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.verified_rounded,
                color: AgapColors.brandWordmarkGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Demo mode: Identity verification will be simulated',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF065F46),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UploadDropZone extends StatelessWidget {
  const _UploadDropZone({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.circle = false,
    this.disabled = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final bool circle;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFCFD3DC),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: circle ? 60 : 44,
            height: circle ? 60 : 44,
            decoration: BoxDecoration(
              color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.10),
              shape: circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: circle ? null : BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AgapColors.brandWordmarkBlue, size: 26),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AgapColors.brandWordmarkBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AgapColors.brandWordmarkBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: disabled ? null : onAction,
            child: Text(
              actionLabel,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Step 4: Resume & Skills ----------

class _ResumeSkillsStep extends StatelessWidget {
  const _ResumeSkillsStep({
    required this.allSkills,
    required this.selected,
    required this.customSkill,
    required this.bio,
    required this.workExp,
    required this.onToggle,
    required this.onAddCustomSkill,
    required this.onRemoveCustomSkill,
  });

  final List<String> allSkills;
  final Set<String> selected;
  final TextEditingController customSkill;
  final TextEditingController bio;
  final TextEditingController workExp;
  final void Function(String) onToggle;
  final VoidCallback onAddCustomSkill;
  final void Function(String) onRemoveCustomSkill;

  @override
  Widget build(BuildContext context) {
    final presetLowercase = allSkills.map((s) => s.toLowerCase()).toSet();
    // Anything in `selected` that isn't part of the preset list is treated
    // as a user-added custom skill (rendered as a removable chip).
    final customSelected = selected
        .where((s) => !presetLowercase.contains(s.toLowerCase()))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIcon(icon: Icons.assignment_outlined),
        const SizedBox(height: 12),
        _StepCaption('Showcase your skills and experience'),
        const SizedBox(height: 18),
        const _FieldLabel('Select Your Skills'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in allSkills)
              _SkillChip(
                label: s,
                selected: selected.contains(s),
                onTap: () => onToggle(s),
              ),
            // User-added skills appear inline with the preset chips so the
            // whole list reads as a single set of selections.
            for (final s in customSelected)
              _RemovableSkillChip(
                label: s,
                onRemove: () => onRemoveCustomSkill(s),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Add-custom-skill input row, kept inside the same section.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _RoundedField(
                controller: customSkill,
                hint: 'Add a custom skill…',
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AgapColors.brandWordmarkBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onAddCustomSkill,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  'Add',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Short Bio'),
        _RoundedField(
          controller: bio,
          hint: 'Tell employers about yourself…',
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        const _FieldLabel('Work Experience'),
        _RoundedField(
          controller: workExp,
          hint: 'List your previous jobs…',
          maxLines: 3,
        ),
      ],
    );
  }
}

class _EducationStep extends StatelessWidget {
  const _EducationStep({
    required this.elementary,
    required this.highSchool,
    required this.seniorHigh,
    required this.collegeCourse,
    required this.collegeTrack,
    required this.onCollegeTrack,
    required this.onChanged,
  });

  final TextEditingController elementary;
  final TextEditingController highSchool;
  final TextEditingController seniorHigh;
  final TextEditingController collegeCourse;
  final _CollegeTrack collegeTrack;
  final ValueChanged<_CollegeTrack> onCollegeTrack;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIcon(icon: Icons.school_outlined),
        const SizedBox(height: 12),
        _StepCaption(
          'Enter your schools (use “None” if not applicable)',
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Elementary school'),
        _RoundedField(
          controller: elementary,
          hint: 'School name or None',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 14),
        const _FieldLabel('High school'),
        _RoundedField(
          controller: highSchool,
          hint: 'School name or None',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 14),
        const _FieldLabel('Senior high school'),
        _RoundedField(
          controller: seniorHigh,
          hint: 'School name or None',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 14),
        const _FieldLabel('College'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Not attending / N/A'),
              selected: collegeTrack == _CollegeTrack.none,
              onSelected: (_) => onCollegeTrack(_CollegeTrack.none),
            ),
            ChoiceChip(
              label: const Text('Undergraduate'),
              selected: collegeTrack == _CollegeTrack.undergraduate,
              onSelected: (_) => onCollegeTrack(_CollegeTrack.undergraduate),
            ),
            ChoiceChip(
              label: const Text('Graduate'),
              selected: collegeTrack == _CollegeTrack.graduate,
              onSelected: (_) => onCollegeTrack(_CollegeTrack.graduate),
            ),
          ],
        ),
        if (collegeTrack != _CollegeTrack.none) ...[
          const SizedBox(height: 12),
          _RoundedField(
            controller: collegeCourse,
            hint: 'Course / program',
            onChanged: (_) => onChanged(),
          ),
        ],
      ],
    );
  }
}

/// Same visual treatment as a selected [_SkillChip], with a small inline X
/// icon for removing user-added skills.
class _RemovableSkillChip extends StatelessWidget {
  const _RemovableSkillChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onRemove,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AgapColors.brandWordmarkBlue, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AgapColors.brandWordmarkBlue,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.close_rounded,
                size: 14,
                color: AgapColors.brandWordmarkBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AgapColors.brandWordmarkBlue.withValues(alpha: 0.10)
          : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AgapColors.brandWordmarkBlue
                  : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected
                  ? AgapColors.brandWordmarkBlue
                  : const Color(0xFF334155),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Step 6: Review ----------

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.email,
    required this.fullName,
    required this.phone,
    required this.address,
    required this.skills,
    required this.educationSummary,
  });

  final String email;
  final String fullName;
  final String phone;
  final String address;
  final Set<String> skills;
  final String educationSummary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFE6FBF1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(
              child: Text('🎉', style: TextStyle(fontSize: 28)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Almost there!',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        _StepCaption('Review your information before submitting'),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _ReviewRow(label: 'Email', value: email.isEmpty ? '—' : email),
              const _Divider(),
              _ReviewRow(
                label: 'Full Name',
                value: fullName.isEmpty ? '—' : fullName,
              ),
              const _Divider(),
              _ReviewRow(label: 'Phone', value: phone.isEmpty ? '—' : phone),
              const _Divider(),
              _ReviewRow(
                label: 'Address',
                value: address.isEmpty ? '—' : address,
              ),
              const _Divider(),
              _ReviewRow(
                label: 'Skills',
                value: skills.isEmpty ? '—' : skills.take(3).join(', '),
              ),
              const _Divider(),
              _ReviewRow(label: 'Education', value: educationSummary),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFCD9A0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⏳', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending Admin Verification',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'After submitting, your account will be reviewed by our admin team. This usually takes 1–2 business days.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.4,
                        color: const Color(0xFFB45309),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9));
}

// ---------- Application Submitted ----------

class _ApplicationSubmittedView extends StatelessWidget {
  const _ApplicationSubmittedView({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4FB),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AgapColors.brandWordmarkBlue, Color(0xFF1E40AF)],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.access_time_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ).animate().scale(
                    duration: 360.ms,
                    curve: Curves.easeOutBack,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Application Submitted!',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Our admin team is reviewing your information',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verification Progress',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const _TimelineRow(
                            icon: Icons.check_rounded,
                            iconBg: Color(0xFFB7EAD2),
                            iconFg: Color(0xFF065F46),
                            label: 'Account Created',
                            statusIcon: Icons.check_circle_outline_rounded,
                            statusColor: AgapColors.brandWordmarkGreen,
                          ),
                          const _TimelineRow(
                            icon: Icons.description_outlined,
                            iconBg: Color(0xFFEDE9FE),
                            iconFg: Color(0xFF6D28D9),
                            label: 'Documents Submitted',
                            statusIcon: Icons.check_circle_outline_rounded,
                            statusColor: AgapColors.brandWordmarkGreen,
                          ),
                          const _TimelineRow(
                            icon: Icons.hourglass_top_rounded,
                            iconBg: Color(0xFFFFF1D6),
                            iconFg: Color(0xFFB45309),
                            label: 'Admin Review',
                            statusText: 'In Progress',
                            statusColor: Color(0xFFB45309),
                          ),
                          const _TimelineRow(
                            icon: Icons.lock_outline_rounded,
                            iconBg: Color(0xFFE2E8F0),
                            iconFg: Color(0xFF94A3B8),
                            label: 'Account Verified',
                            dimmed: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.notifications_active_rounded,
                            size: 20,
                            color: AgapColors.brandBoltYellow,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'We\'ll notify you',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'You\'ll receive a notification once your account is verified. This usually takes 1–2 business days.',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: const Color(0xFF64748B),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7E6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCD9A0)),
                      ),
                      child: Text(
                        'Demo: Account will be auto-approved in a few seconds for demonstration purposes.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFB45309),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (email.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Reviewing for: $email',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF94A3B8),
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
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.label,
    this.statusIcon,
    this.statusText,
    this.statusColor,
    this.dimmed = false,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String label;
  final IconData? statusIcon;
  final String? statusText;
  final Color? statusColor;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconFg, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: dimmed
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF0F172A),
              ),
            ),
          ),
          if (statusIcon != null)
            Icon(
              statusIcon,
              color: statusColor ?? const Color(0xFF94A3B8),
              size: 18,
            )
          else if (statusText != null)
            Text(
              statusText!,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: statusColor ?? const Color(0xFF94A3B8),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- Shared bits ----------

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AgapColors.brandWordmarkBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: AgapColors.brandWordmarkBlue, size: 30),
      ),
    );
  }
}

class _StepCaption extends StatelessWidget {
  const _StepCaption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF64748B),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 13.5,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF0F172A),
        ),
      ),
    );
  }
}

class _RoundedField extends StatelessWidget {
  const _RoundedField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
    this.hasError = false,
    this.errorMessage,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final bool hasError;
  final String? errorMessage;

  static const _errorRed = Color(0xFFEF4444);
  static const _errorRedDeep = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    final enabledSide = BorderSide(
      color: hasError ? _errorRed : const Color(0xFFE2E8F0),
      width: hasError ? 1.4 : 1,
    );
    final focusedSide = BorderSide(
      color: hasError ? _errorRedDeep : AgapColors.brandWordmarkBlue,
      width: 1.4,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: obscureText ? 1 : maxLines,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              fontSize: 13.5,
              color: const Color(0xFFB6BFCB),
              fontWeight: FontWeight.w600,
            ),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: suffix,
            // Hide the auto-generated character counter when maxLength is set; we
            // surface our own helper text below the field instead.
            counterText: maxLength != null ? '' : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: enabledSide,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: focusedSide,
            ),
          ),
        ),
        if (errorMessage != null && errorMessage!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              errorMessage!,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _errorRedDeep,
              ),
            ),
          ),
      ],
    );
  }
}

/// Wraps a step body's Column so that its children cascade in with a small
/// staggered right→left (or left→right) slide-and-fade. Falls back to a single
/// animated child if [child] is not a Column.
class _CascadeIn extends StatelessWidget {
  const _CascadeIn({required this.direction, required this.child});

  final int direction; // +1 (incoming from right) or -1 (incoming from left)
  final Widget child;

  static const _stepMs = 60;
  static const _maxStagger = 9; // cap so very long forms don't drag forever

  @override
  Widget build(BuildContext context) {
    final beginX = 0.06 * direction.toDouble(); // small horizontal nudge
    if (child is Column) {
      final col = child as Column;
      final children = <Widget>[];
      for (var i = 0; i < col.children.length; i++) {
        final c = col.children[i];
        // Skip pure spacers from animation work.
        if (c is SizedBox && c.child == null) {
          children.add(c);
          continue;
        }
        final delay = (i.clamp(0, _maxStagger) * _stepMs).ms;
        children.add(
          c
              .animate()
              .fadeIn(
                delay: delay,
                duration: 320.ms,
                curve: Curves.easeOutCubic,
              )
              .slideX(
                begin: beginX,
                end: 0,
                delay: delay,
                duration: 360.ms,
                curve: Curves.easeOutCubic,
              ),
        );
      }
      return Column(
        mainAxisSize: col.mainAxisSize,
        mainAxisAlignment: col.mainAxisAlignment,
        crossAxisAlignment: col.crossAxisAlignment,
        textDirection: col.textDirection,
        verticalDirection: col.verticalDirection,
        textBaseline: col.textBaseline,
        children: children,
      );
    }

    return child
        .animate()
        .fadeIn(duration: 320.ms, curve: Curves.easeOutCubic)
        .slideX(
          begin: beginX,
          end: 0,
          duration: 360.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

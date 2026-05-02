import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../../marketplace/marketplace_scope.dart';
import '../../../onboarding/supabase_onboarding_sync.dart';
import '../../../session/session_models.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/kyc_upload_zone.dart';
import 'davao_del_sur_locations.dart';
import 'onboarding_location_widgets.dart';
import 'pinnable_business_map.dart';

/// 6-step business onboarding flow:
///   Step 1: Create Account (email + password)
///   Step 2: Business Type — pick Sole Proprietorship, Partnership, or
///           Corporation. The next step's required fields depend on this.
///   Step 3: Business Details — type-specific identity + uploads:
///             • Sole Proprietorship: owner's legal name, trade name, TIN,
///               DTI Certificate of Registration, Mayor's permit, owner's
///               government ID.
///             • Partnership: managing partner name, registered partnership
///               name, Articles of Partnership, Mayor's permit.
///             • Corporation: SEC registration number, corporate name,
///               authorized representative title, SEC Certificate of
///               Incorporation, Mayor's permit, Secretary's certificate.
///   Step 4: Location Setup (address, map pin, contact phone)
///   Step 5: Payment Setup (GCash / Maya / Bank)
///   Step 6: Review + submit
///
/// Uses the same slide-and-fade transition + cascading element animation as
/// the worker side, with the brand green accent (no orange).
class BusinessOnboardingScreen extends StatefulWidget {
  const BusinessOnboardingScreen({
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
  State<BusinessOnboardingScreen> createState() =>
      _BusinessOnboardingScreenState();
}

// Business onboarding theme — brand greens (matches `AgapColors`) on a soft
// mint surface, never orange.
const Color _brandGreen = AgapColors.brandWordmarkGreen; // 0xFF43A047
const Color _brandGreenDark = AgapColors.primary; // 0xFF005C39
const Color _mintBg = AgapColors.mintSurface; // 0xFFE8F5EF
const Color _mintSoft = AgapColors.mintSoft; // 0xFFB8E0D2

class _BusinessOnboardingScreenState extends State<BusinessOnboardingScreen> {
  static const _totalSteps = 6;

  int _step = 0;
  int _direction = 1; // +1 forward, -1 backward
  bool _submitting = false;

  // Step 1 — Account
  final _email = TextEditingController();
  final _password = TextEditingController();
  TextEditingController? _confirmPasswordCtl;
  TextEditingController get _confirmPassword =>
      _confirmPasswordCtl ??= TextEditingController();
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  // Step 2 — Business Type
  _BusinessKind _kind = _BusinessKind.soleProprietorship;

  // Step 3 — Type-specific business details. Every controller is allocated up
  // front so users can flip between kinds without losing what they typed for
  // the previously-selected kind. Validation only checks the controllers
  // belonging to the currently-selected kind.

  // Sole Proprietorship
  final _ownerLegalName = TextEditingController();
  final _tradeName = TextEditingController();
  final _tin = TextEditingController();
  String? _dtiCertFile;
  String? _ownerGovIdFile;

  // Partnership
  final _managingPartnerName = TextEditingController();
  final _partnershipName = TextEditingController();
  String? _articlesOfPartnershipFile;

  // Corporation
  final _secRegNumber = TextEditingController();
  final _corporateName = TextEditingController();
  final _authorizedRepTitle = TextEditingController();
  String? _secCertOfIncorporationFile;
  String? _secretaryCertFile;

  // Shared by all three kinds
  String? _mayorPermitFile;

  // Step 4 — Location (same structure as worker: Davao del Sur + optional street)
  String? _locationMunicipality;
  String? _locationBarangay;
  final _streetDetail = TextEditingController();
  double? _locationLat;
  double? _locationLng;
  final _phone = TextEditingController();

  // Step 5 — Payment / payout (mirrors worker onboarding `_PayoutStep`)
  static const List<String> _phBanks = <String>[
    'BDO Unibank',
    'Bank of the Philippine Islands (BPI)',
    'Metrobank',
    'Land Bank of the Philippines',
    'Philippine National Bank (PNB)',
    'Security Bank',
    'UnionBank of the Philippines',
    'China Banking Corporation',
    'RCBC (Rizal Commercial Banking Corp)',
    'EastWest Bank',
    'PSBank (Philippine Savings Bank)',
    'Maybank Philippines',
    'Maya Bank',
    'GoTyme Bank',
    'CIMB Bank Philippines',
    'ING Bank Philippines',
    'Citibank Philippines',
    'Robinsons Bank',
    'HSBC Philippines',
    'Development Bank of the Philippines (DBP)',
    'Asia United Bank (AUB)',
    'BDO Network Bank',
  ];

  _BizPayMethod _payMethod = _BizPayMethod.ewallet;
  _BizEWallet _eWallet = _BizEWallet.gcash;
  String? _payBankName;
  final _payAccount = TextEditingController();

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
    _ownerLegalName.dispose();
    _tradeName.dispose();
    _tin.dispose();
    _managingPartnerName.dispose();
    _partnershipName.dispose();
    _secRegNumber.dispose();
    _corporateName.dispose();
    _authorizedRepTitle.dispose();
    _streetDetail.dispose();
    _phone.dispose();
    _payAccount.dispose();
    super.dispose();
  }

  /// Same PH-mobile rule as worker payout: 11 digits starting with `09`.
  bool _isValidPhMobile(String value) {
    final t = value.trim();
    return t.length == 11 &&
        t.startsWith('09') &&
        RegExp(r'^[0-9]+$').hasMatch(t);
  }

  /// PH bank account: digits only, 10–19 chars (same as worker onboarding).
  bool _isValidBankAccount(String value) {
    final t = value.trim();
    return t.length >= 10 && t.length <= 19 && RegExp(r'^[0-9]+$').hasMatch(t);
  }

  LatLng? get _locationPin =>
      _locationLat != null && _locationLng != null
          ? LatLng(_locationLat!, _locationLng!)
          : null;

  String _businessLocationAddressLine() {
    final muni = _locationMunicipality;
    final brgy = _locationBarangay;
    final formatted = (muni != null && brgy != null)
        ? DavaoDelSur.formatAddress(barangay: brgy, municipality: muni)
        : '';
    final street = _streetDetail.text.trim();
    if (street.isEmpty) return formatted;
    if (formatted.isEmpty) return street;
    return '$street, $formatted';
  }

  /// Search string for map geocoding (Photon). Only non-null when muni+brgy set.
  String? _geocodeQueryForMap() {
    final m = _locationMunicipality;
    final b = _locationBarangay;
    if (m == null || b == null) return null;
    final street = _streetDetail.text.trim();
    return <String>[
      if (street.isNotEmpty) street,
      b,
      m,
      DavaoDelSur.province,
      'Philippines',
    ].join(', ');
  }

  Future<void> _pickBizMunicipality() async {
    final picked = await showLocationOptionPicker(
      context: context,
      title: 'Select Municipality',
      options: DavaoDelSur.municipalities,
      selected: _locationMunicipality,
      focusedBorderColor: _brandGreen,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _locationMunicipality = picked;
      _locationBarangay = null;
    });
  }

  Future<void> _pickBizBarangay() async {
    final muni = _locationMunicipality;
    if (muni == null) return;
    final list = DavaoDelSur.barangays[muni] ?? const <String>[];
    final picked = await showLocationOptionPicker(
      context: context,
      title: 'Select Barangay',
      options: list,
      selected: _locationBarangay,
      focusedBorderColor: _brandGreen,
    );
    if (picked == null || !mounted) return;
    setState(() => _locationBarangay = picked);
  }

  String _paymentSummary() {
    final acct = _payAccount.text.trim();
    switch (_payMethod) {
      case _BizPayMethod.ewallet:
        return acct.isEmpty ? _eWallet.label : '${_eWallet.label} · $acct';
      case _BizPayMethod.bank:
        final b = _payBankName ?? 'Bank';
        return acct.isEmpty ? b : '$b · $acct';
    }
  }

  /// Display name of the business based on the selected kind. Used by the
  /// review step + the submission slug fallback.
  String get _displayBusinessName {
    switch (_kind) {
      case _BusinessKind.soleProprietorship:
        return _tradeName.text.trim();
      case _BusinessKind.partnership:
        return _partnershipName.text.trim();
      case _BusinessKind.corporation:
        return _corporateName.text.trim();
    }
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        final emailOk = _email.text.trim().contains('@');
        final passOk = _password.text.length >= 6 &&
            _password.text == _confirmPassword.text;
        return emailOk && passOk;
      case 1:
        return true; // a kind is always selected
      case 2:
        return _detailsValidForKind(_kind);
      case 3:
        return _locationMunicipality != null &&
            _locationBarangay != null &&
            _locationLat != null &&
            _locationLng != null &&
            _isValidContactPhone(_phone.text);
      case 4:
        switch (_payMethod) {
          case _BizPayMethod.ewallet:
            return _isValidPhMobile(_payAccount.text);
          case _BizPayMethod.bank:
            return _payBankName != null &&
                _isValidBankAccount(_payAccount.text);
        }
      case 5:
        return true;
      default:
        return false;
    }
  }

  /// Step 3 validation, branched on the selected business kind. Each branch
  /// requires every type-specific text field to be non-empty AND every
  /// type-specific document upload to be present.
  bool _detailsValidForKind(_BusinessKind kind) {
    bool nonEmpty(TextEditingController c) => c.text.trim().isNotEmpty;
    switch (kind) {
      case _BusinessKind.soleProprietorship:
        return nonEmpty(_ownerLegalName) &&
            nonEmpty(_tradeName) &&
            nonEmpty(_tin) &&
            _dtiCertFile != null &&
            _mayorPermitFile != null &&
            _ownerGovIdFile != null;
      case _BusinessKind.partnership:
        return nonEmpty(_managingPartnerName) &&
            nonEmpty(_partnershipName) &&
            _articlesOfPartnershipFile != null &&
            _mayorPermitFile != null;
      case _BusinessKind.corporation:
        return nonEmpty(_secRegNumber) &&
            nonEmpty(_corporateName) &&
            nonEmpty(_authorizedRepTitle) &&
            _secCertOfIncorporationFile != null &&
            _mayorPermitFile != null &&
            _secretaryCertFile != null;
    }
  }

  /// Accepts mobile (11 digits, starts with `09`) OR a landline-style number
  /// (10 digits, starts with `0` and the area code, e.g. `02XXXXXXXX`).
  /// Dashes are stripped before checking.
  bool _isValidContactPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11 && digits.startsWith('09')) return true;
    if (digits.length == 10 && digits.startsWith('0')) return true;
    return false;
  }

  String get _stepTitle {
    switch (_step) {
      case 0:
        return 'Create Account';
      case 1:
        return 'Business Type';
      case 2:
        return 'Business Details';
      case 3:
        return 'Location Setup';
      case 4:
        return 'Payment Setup';
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
      await _submitBusinessResponsesToSupabase();
      await _submitApplication();
    }
  }

  /// Writes onboarding answers only after the user completes the full wizard.
  Future<void> _submitBusinessResponsesToSupabase() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      await SupabaseOnboardingSync.saveBusiness(
        _buildBusinessPayload(completedStep: 5),
      );
    } catch (_) {}
  }

  Map<String, dynamic> _buildBusinessPayload({required int completedStep}) {
    final m = <String, dynamic>{
      'schema_version': 1,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (completedStep >= 0) {
      final em = _email.text.trim();
      if (em.isNotEmpty) m['email'] = em;
    }
    if (completedStep >= 1) {
      m['business_kind'] = _kind.name;
    }
    if (completedStep >= 2) {
      m['details'] = {
        'kind': _kind.name,
        'sole_proprietorship': {
          'owner_legal_name': _ownerLegalName.text.trim(),
          'trade_name': _tradeName.text.trim(),
          'tin': _tin.text.trim(),
          'dti_cert_file': _dtiCertFile,
          'mayor_permit_file': _mayorPermitFile,
          'owner_gov_id_file': _ownerGovIdFile,
        },
        'partnership': {
          'managing_partner_name': _managingPartnerName.text.trim(),
          'partnership_name': _partnershipName.text.trim(),
          'articles_of_partnership_file': _articlesOfPartnershipFile,
          'mayor_permit_file': _mayorPermitFile,
        },
        'corporation': {
          'sec_reg_number': _secRegNumber.text.trim(),
          'corporate_name': _corporateName.text.trim(),
          'authorized_rep_title': _authorizedRepTitle.text.trim(),
          'sec_certificate_file': _secCertOfIncorporationFile,
          'mayor_permit_file': _mayorPermitFile,
          'secretary_certificate_file': _secretaryCertFile,
        },
      };
    }
    if (completedStep >= 3) {
      m['location'] = {
        'province': DavaoDelSur.province,
        'municipality': _locationMunicipality,
        'barangay': _locationBarangay,
        'street_detail': _streetDetail.text.trim(),
        'address': _businessLocationAddressLine(),
        'latitude': _locationLat,
        'longitude': _locationLng,
        'phone': _phone.text.trim(),
      };
    }
    if (completedStep >= 4) {
      m['payment'] = {
        'method': _payMethod.name,
        'ewallet': _eWallet.name,
        'bank_name': _payBankName,
        'account': _payAccount.text.trim(),
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
        flow: 'business',
        snapshot: _buildBusinessPayload(completedStep: 5),
      );
    }
    if (!mounted) return;
    // Register the email so the user can log back in next time.
    final session = MarketplaceScope.of(context).session;
    final existing = session.state.email;
    final email = _email.text.trim();
    if (email.isNotEmpty) {
      await session.registerEmail(email);
    } else if (existing == null || existing.isEmpty) {
      // Fallback: synthesize a placeholder if somehow no email was entered.
      final slug = _displayBusinessName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final synthesized = '${slug.isEmpty ? 'business' : slug}@business.local';
      await session.registerEmail(synthesized);
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _step = _totalSteps; // show submitted view
    });
    // Hand off to the dashboard with a limited-access status after a short delay.
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      await widget.onSubmit();
    });
  }

  Future<void> _pickFile({
    required String currentValueLabel,
    required ValueSetter<String> onPicked,
    required String demoFilename,
  }) async {
    final picked = await pickKycDocument();
    if (!mounted) return;
    if (picked != null) {
      onPicked(picked);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'No file selected. Picker may be unavailable on this device.',
        ),
        action: SnackBarAction(
          label: 'Use demo',
          onPressed: () => onPicked(demoFilename),
        ),
      ),
    );
  }

  /// Pre-fills only the documents required for the currently-selected
  /// business kind so users can advance through the demo without an actual
  /// file picker.
  void _useDemoDocuments() {
    setState(() {
      _mayorPermitFile = 'demo_mayors_permit.pdf';
      switch (_kind) {
        case _BusinessKind.soleProprietorship:
          _dtiCertFile = 'demo_dti_certificate.pdf';
          _ownerGovIdFile = 'demo_owner_government_id.jpg';
        case _BusinessKind.partnership:
          _articlesOfPartnershipFile = 'demo_articles_of_partnership.pdf';
        case _BusinessKind.corporation:
          _secCertOfIncorporationFile = 'demo_sec_certificate.pdf';
          _secretaryCertFile = 'demo_secretarys_certificate.pdf';
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo documents applied — you can continue.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_step >= _totalSteps) {
      return _ApplicationSubmittedView(
        email: _email.text.trim(),
        companyName: _displayBusinessName,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _back();
      },
      child: Scaffold(
        backgroundColor: _mintBg,
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
                      final begin = isIncoming
                          ? Offset(_direction.toDouble(), 0)
                          : Offset(-_direction.toDouble(), 0);
                      final position = Tween<Offset>(
                        begin: begin,
                        end: Offset.zero,
                      ).animate(anim);
                      return SlideTransition(
                        position: position,
                        child: FadeTransition(opacity: anim, child: child),
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
                          ? _brandGreen
                          : const Color(0xFFCBD5E1),
                      foregroundColor: Colors.white,
                      elevation: _canContinue && !_submitting ? 8 : 0,
                      shadowColor: _brandGreen.withValues(alpha: 0.30),
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
    return _CascadeIn(direction: _direction, child: body);
  }

  Widget _buildStepInner() {
    switch (_step) {
      case 0:
        return _AccountStep(
          email: _email,
          password: _password,
          confirmPassword: _confirmPassword,
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
        return _BusinessKindStep(
          kind: _kind,
          onChangeKind: (k) => setState(() => _kind = k),
        );
      case 2:
        return _BusinessDetailsStep(
          kind: _kind,
          // Sole Proprietorship
          ownerLegalName: _ownerLegalName,
          tradeName: _tradeName,
          tin: _tin,
          dtiCertFile: _dtiCertFile,
          ownerGovIdFile: _ownerGovIdFile,
          onPickDtiCert: () => _pickFile(
            currentValueLabel: _dtiCertFile ?? '',
            onPicked: (n) => setState(() => _dtiCertFile = n),
            demoFilename: 'demo_dti_certificate.pdf',
          ),
          onPickOwnerGovId: () => _pickFile(
            currentValueLabel: _ownerGovIdFile ?? '',
            onPicked: (n) => setState(() => _ownerGovIdFile = n),
            demoFilename: 'demo_owner_government_id.jpg',
          ),
          // Partnership
          managingPartnerName: _managingPartnerName,
          partnershipName: _partnershipName,
          articlesOfPartnershipFile: _articlesOfPartnershipFile,
          onPickArticlesOfPartnership: () => _pickFile(
            currentValueLabel: _articlesOfPartnershipFile ?? '',
            onPicked: (n) => setState(() => _articlesOfPartnershipFile = n),
            demoFilename: 'demo_articles_of_partnership.pdf',
          ),
          // Corporation
          secRegNumber: _secRegNumber,
          corporateName: _corporateName,
          authorizedRepTitle: _authorizedRepTitle,
          secCertOfIncorporationFile: _secCertOfIncorporationFile,
          secretaryCertFile: _secretaryCertFile,
          onPickSecCertOfIncorporation: () => _pickFile(
            currentValueLabel: _secCertOfIncorporationFile ?? '',
            onPicked: (n) => setState(() => _secCertOfIncorporationFile = n),
            demoFilename: 'demo_sec_certificate.pdf',
          ),
          onPickSecretaryCert: () => _pickFile(
            currentValueLabel: _secretaryCertFile ?? '',
            onPicked: (n) => setState(() => _secretaryCertFile = n),
            demoFilename: 'demo_secretarys_certificate.pdf',
          ),
          // Shared
          mayorPermitFile: _mayorPermitFile,
          onPickMayorPermit: () => _pickFile(
            currentValueLabel: _mayorPermitFile ?? '',
            onPicked: (n) => setState(() => _mayorPermitFile = n),
            demoFilename: 'demo_mayors_permit.pdf',
          ),
          onUseDemoDocs: _useDemoDocuments,
          onChanged: () => setState(() {}),
        );
      case 3:
        return _LocationStep(
          municipality: _locationMunicipality,
          barangay: _locationBarangay,
          streetDetail: _streetDetail,
          phone: _phone,
          pin: _locationPin,
          geocodeQuery: _geocodeQueryForMap(),
          onPickMunicipality: _pickBizMunicipality,
          onPickBarangay: _pickBizBarangay,
          onPinChanged: (LatLng ll) => setState(() {
            _locationLat = ll.latitude;
            _locationLng = ll.longitude;
          }),
          onChanged: () => setState(() {}),
        );
      case 4:
        return _PaymentStep(
          method: _payMethod,
          eWallet: _eWallet,
          bankName: _payBankName,
          account: _payAccount,
          banks: _phBanks,
          onChangeMethod: (m) => setState(() {
            _payMethod = m;
            _payAccount.clear();
          }),
          onChangeEWallet: (k) => setState(() {
            _eWallet = k;
            _payAccount.clear();
          }),
          onChangeBank: (b) => setState(() {
            _payBankName = b;
            _payAccount.clear();
          }),
          onChanged: () => setState(() {}),
        );
      case 5:
        return _ReviewStep(
          email: _email.text.trim(),
          kind: _kind,
          businessName: _displayBusinessName,
          paymentSummary: _paymentSummary(),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ---------- Header ----------

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
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: _mintBg,
                valueColor: const AlwaysStoppedAnimation<Color>(_brandGreen),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Step 1: Create Account ----------

class _AccountStep extends StatelessWidget {
  const _AccountStep({
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.passwordVisible,
    required this.confirmPasswordVisible,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onChanged,
  });

  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController confirmPassword;
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
        _StepCaption('Create your business account'),
        const SizedBox(height: 22),
        const _FieldLabel('Business Email'),
        _RoundedField(
          controller: email,
          hint: 'hr@company.ph',
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Password'),
        _RoundedField(
          controller: password,
          hint: 'Create a strong password',
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

// ---------- Step 2: Business Type ----------

/// Three legally-distinct business kinds AgapShift supports onboarding for.
/// Each kind drives a different set of required fields + uploaded documents
/// in step 3.
enum _BusinessKind { soleProprietorship, partnership, corporation }

extension _BusinessKindInfo on _BusinessKind {
  String get label => switch (this) {
    _BusinessKind.soleProprietorship => 'Sole Proprietorship',
    _BusinessKind.partnership => 'Partnership',
    _BusinessKind.corporation => 'Corporation',
  };

  String get description => switch (this) {
    _BusinessKind.soleProprietorship => 'Owned by a single individual',
    _BusinessKind.partnership => 'Owned by 2 or more partners',
    _BusinessKind.corporation => 'Legally incorporated entity',
  };

  IconData get icon => switch (this) {
    _BusinessKind.soleProprietorship => Icons.person_rounded,
    _BusinessKind.partnership => Icons.handshake_rounded,
    _BusinessKind.corporation => Icons.apartment_rounded,
  };
}

class _BusinessKindStep extends StatelessWidget {
  const _BusinessKindStep({required this.kind, required this.onChangeKind});

  final _BusinessKind kind;
  final ValueChanged<_BusinessKind> onChangeKind;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIcon(icon: Icons.business_rounded),
        const SizedBox(height: 12),
        _StepCaption('What kind of business do you have?'),
        const SizedBox(height: 22),
        for (var i = 0; i < _BusinessKind.values.length; i++) ...[
          _BusinessKindCard(
            kind: _BusinessKind.values[i],
            selected: kind == _BusinessKind.values[i],
            onTap: () => onChangeKind(_BusinessKind.values[i]),
          ),
          if (i != _BusinessKind.values.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _BusinessKindCard extends StatelessWidget {
  const _BusinessKindCard({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final _BusinessKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _mintBg : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _brandGreen : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? _brandGreen.withValues(alpha: 0.16)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  kind.icon,
                  color: selected ? _brandGreen : const Color(0xFF64748B),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.label,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: selected ? _brandGreen : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kind.description,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? _brandGreen.withValues(alpha: 0.12)
                      : Colors.transparent,
                  border: Border.all(
                    color: selected ? _brandGreen : const Color(0xFFCBD5E1),
                    width: 1.6,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: _brandGreen,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Step 3: Business Details (type-specific) ----------

/// Renders the legally-required fields + document uploads for the selected
/// business kind. Every kind needs the Mayor's permit; the rest of the
/// requirements are kind-specific (see the file's top doc comment).
class _BusinessDetailsStep extends StatelessWidget {
  const _BusinessDetailsStep({
    required this.kind,
    required this.ownerLegalName,
    required this.tradeName,
    required this.tin,
    required this.dtiCertFile,
    required this.ownerGovIdFile,
    required this.onPickDtiCert,
    required this.onPickOwnerGovId,
    required this.managingPartnerName,
    required this.partnershipName,
    required this.articlesOfPartnershipFile,
    required this.onPickArticlesOfPartnership,
    required this.secRegNumber,
    required this.corporateName,
    required this.authorizedRepTitle,
    required this.secCertOfIncorporationFile,
    required this.secretaryCertFile,
    required this.onPickSecCertOfIncorporation,
    required this.onPickSecretaryCert,
    required this.mayorPermitFile,
    required this.onPickMayorPermit,
    required this.onUseDemoDocs,
    required this.onChanged,
  });

  final _BusinessKind kind;

  // Sole Proprietorship
  final TextEditingController ownerLegalName;
  final TextEditingController tradeName;
  final TextEditingController tin;
  final String? dtiCertFile;
  final String? ownerGovIdFile;
  final VoidCallback onPickDtiCert;
  final VoidCallback onPickOwnerGovId;

  // Partnership
  final TextEditingController managingPartnerName;
  final TextEditingController partnershipName;
  final String? articlesOfPartnershipFile;
  final VoidCallback onPickArticlesOfPartnership;

  // Corporation
  final TextEditingController secRegNumber;
  final TextEditingController corporateName;
  final TextEditingController authorizedRepTitle;
  final String? secCertOfIncorporationFile;
  final String? secretaryCertFile;
  final VoidCallback onPickSecCertOfIncorporation;
  final VoidCallback onPickSecretaryCert;

  // Shared
  final String? mayorPermitFile;
  final VoidCallback onPickMayorPermit;

  final VoidCallback onUseDemoDocs;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIcon(icon: Icons.description_rounded),
        const SizedBox(height: 12),
        _StepCaption(
          'Provide your ${kind.label.toLowerCase()} details and documents',
        ),
        const SizedBox(height: 18),
        ..._fieldsForKind(),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onUseDemoDocs,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: _mintBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _mintSoft),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_box_rounded,
                  color: _brandGreenDark,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Demo mode: tap to simulate uploading every required document',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _brandGreenDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _fieldsForKind() {
    switch (kind) {
      case _BusinessKind.soleProprietorship:
        return [
          const _FieldLabel("Owner's Legal Name"),
          _RoundedField(
            controller: ownerLegalName,
            hint: 'Juan dela Cruz',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Business Trade Name'),
          _RoundedField(
            controller: tradeName,
            hint: "e.g., Juan's Sari-Sari Store",
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('TIN Number'),
          _RoundedField(
            controller: tin,
            hint: '000-000-000-000',
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              LengthLimitingTextInputFormatter(15),
            ],
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 18),
          _DocumentUploadTile(
            title: 'DTI Certificate of Registration',
            subtitle: 'Department of Trade and Industry',
            icon: Icons.assignment_rounded,
            fileName: dtiCertFile,
            onPick: onPickDtiCert,
          ),
          const SizedBox(height: 12),
          _DocumentUploadTile(
            title: "Mayor's / Business Permit",
            subtitle: 'Local government unit permit',
            icon: Icons.account_balance_rounded,
            fileName: mayorPermitFile,
            onPick: onPickMayorPermit,
          ),
          const SizedBox(height: 12),
          _DocumentUploadTile(
            title: "Owner's Government ID",
            subtitle: 'SSS, UMID, PhilHealth, Passport',
            icon: Icons.badge_rounded,
            fileName: ownerGovIdFile,
            onPick: onPickOwnerGovId,
          ),
        ];
      case _BusinessKind.partnership:
        return [
          const _FieldLabel('Managing Partner Name'),
          _RoundedField(
            controller: managingPartnerName,
            hint: 'Juan dela Cruz',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Registered Partnership Name'),
          _RoundedField(
            controller: partnershipName,
            hint: 'Cruz & Reyes Partners',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 18),
          _DocumentUploadTile(
            title: 'Articles of Partnership',
            subtitle: 'Notarized partnership document',
            icon: Icons.article_rounded,
            fileName: articlesOfPartnershipFile,
            onPick: onPickArticlesOfPartnership,
          ),
          const SizedBox(height: 12),
          _DocumentUploadTile(
            title: "Mayor's Permit",
            subtitle: 'Local government unit permit',
            icon: Icons.account_balance_rounded,
            fileName: mayorPermitFile,
            onPick: onPickMayorPermit,
          ),
        ];
      case _BusinessKind.corporation:
        return [
          const _FieldLabel('SEC Registration Number'),
          _RoundedField(
            controller: secRegNumber,
            hint: 'CS00000000',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Corporate Name'),
          _RoundedField(
            controller: corporateName,
            hint: 'AgapShift Holdings, Inc.',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Authorized Representative Title'),
          _RoundedField(
            controller: authorizedRepTitle,
            hint: 'e.g., President, CFO, HR Director',
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 18),
          _DocumentUploadTile(
            title: 'SEC Certificate of Incorporation',
            subtitle: 'Securities and Exchange Commission',
            icon: Icons.assignment_turned_in_rounded,
            fileName: secCertOfIncorporationFile,
            onPick: onPickSecCertOfIncorporation,
          ),
          const SizedBox(height: 12),
          _DocumentUploadTile(
            title: "Mayor's Permit",
            subtitle: 'Local government unit permit',
            icon: Icons.account_balance_rounded,
            fileName: mayorPermitFile,
            onPick: onPickMayorPermit,
          ),
          const SizedBox(height: 12),
          _DocumentUploadTile(
            title: "Secretary's Certificate",
            subtitle: 'Notarized board secretary attestation',
            icon: Icons.fact_check_rounded,
            fileName: secretaryCertFile,
            onPick: onPickSecretaryCert,
          ),
        ];
    }
  }
}

class _DocumentUploadTile extends StatelessWidget {
  const _DocumentUploadTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fileName,
    required this.onPick,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? fileName;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final isUploaded = fileName != null && fileName!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _mintSoft, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _brandGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _brandGreen, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _brandGreen,
                side: BorderSide(
                  color: _brandGreen.withValues(alpha: isUploaded ? 1 : 0.6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onPick,
              icon: Icon(
                isUploaded ? Icons.check_circle_rounded : Icons.upload_rounded,
                size: 18,
              ),
              label: Text(
                isUploaded ? fileName! : 'Upload Document',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Step 4: Location ----------

class _LocationStep extends StatelessWidget {
  const _LocationStep({
    required this.municipality,
    required this.barangay,
    required this.streetDetail,
    required this.phone,
    required this.pin,
    required this.geocodeQuery,
    required this.onPickMunicipality,
    required this.onPickBarangay,
    required this.onPinChanged,
    required this.onChanged,
  });

  final String? municipality;
  final String? barangay;
  final TextEditingController streetDetail;
  final TextEditingController phone;
  final LatLng? pin;
  final String? geocodeQuery;
  final VoidCallback onPickMunicipality;
  final VoidCallback onPickBarangay;
  final ValueChanged<LatLng> onPinChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final barangayDisabled = municipality == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIcon(icon: Icons.location_on_rounded),
        const SizedBox(height: 12),
        _StepCaption('Set your business location'),
        const SizedBox(height: 22),
        const _FieldLabel('Province'),
        OnboardingLocationSelectField(
          value: DavaoDelSur.province,
          hint: DavaoDelSur.province,
          enabled: false,
          icon: Icons.flag_rounded,
          focusAccentColor: _brandGreen,
        ),
        const SizedBox(height: 12),
        const _FieldLabel('Municipality'),
        OnboardingLocationSelectField(
          value: municipality,
          hint: 'Select municipality',
          enabled: true,
          icon: Icons.location_city_rounded,
          onTap: onPickMunicipality,
          focusAccentColor: _brandGreen,
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
          focusAccentColor: _brandGreen,
        ),
        const SizedBox(height: 12),
        const _FieldLabel('Street / building / unit (optional)'),
        _RoundedField(
          controller: streetDetail,
          hint: 'e.g. Door 2, Juan Luna St.',
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Pin location on map'),
        PinnableBusinessMapCard(
          pin: pin,
          onPinChanged: onPinChanged,
          addressQueryForGeocode: geocodeQuery,
          accentColor: _brandGreen,
        ),
        const SizedBox(height: 6),
        _FieldHint(
          'After you choose barangay, the map moves there automatically. '
          'Use My Location pins GPS; you can drag accuracy by tapping the map. '
          '© OpenStreetMap',
        ),
        const SizedBox(height: 18),
        const _FieldLabel('Contact Phone'),
        _RoundedField(
          controller: phone,
          hint: '02-XXXX-XXXX or 09XXXXXXXXX',
          keyboardType: TextInputType.phone,
          maxLength: 13,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
            LengthLimitingTextInputFormatter(13),
          ],
          onChanged: (_) => onChanged(),
        ),
        _FieldHint(
          'Mobile (11 digits, 09…) or landline (10 digits, 02-XXXX-XXXX)',
        ),
      ],
    );
  }
}

// ---------- Step 5: Payment ----------
// Same layout as worker onboarding `_PayoutStep`: top-level **E-wallet vs
// Bank**, then either GCash/Maya + mobile number, or bank + account number,
// plus the informational callout — here tinted with the business green brand.

enum _BizPayMethod { ewallet, bank }

extension _BizPayMethodInfo on _BizPayMethod {
  String get label => switch (this) {
    _BizPayMethod.ewallet => 'E-wallet',
    _BizPayMethod.bank => 'Bank',
  };

  String get description => switch (this) {
    _BizPayMethod.ewallet => 'GCash or Maya',
    _BizPayMethod.bank => 'Local bank account',
  };

  IconData get icon => switch (this) {
    _BizPayMethod.ewallet => Icons.account_balance_wallet_rounded,
    _BizPayMethod.bank => Icons.account_balance_rounded,
  };

  Color get color => switch (this) {
    _BizPayMethod.ewallet => const Color(0xFF1ABC4F),
    _BizPayMethod.bank => const Color(0xFF334155),
  };
}

enum _BizEWallet { gcash, maya }

extension _BizEWalletInfo on _BizEWallet {
  String get label => switch (this) {
    _BizEWallet.gcash => 'GCash',
    _BizEWallet.maya => 'Maya',
  };

  Color get color => switch (this) {
    _BizEWallet.gcash => const Color(0xFF1ABC4F),
    _BizEWallet.maya => const Color(0xFF2563EB),
  };
}

class _PaymentStep extends StatelessWidget {
  const _PaymentStep({
    required this.method,
    required this.eWallet,
    required this.bankName,
    required this.account,
    required this.banks,
    required this.onChangeMethod,
    required this.onChangeEWallet,
    required this.onChangeBank,
    required this.onChanged,
  });

  final _BizPayMethod method;
  final _BizEWallet eWallet;
  final String? bankName;
  final TextEditingController account;
  final List<String> banks;
  final void Function(_BizPayMethod) onChangeMethod;
  final void Function(_BizEWallet) onChangeEWallet;
  final ValueChanged<String> onChangeBank;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIcon(icon: Icons.credit_card_rounded),
        const SizedBox(height: 12),
        _StepCaption('Set up how you fund worker payments'),
        const SizedBox(height: 22),
        const _FieldLabel('Payout Method'),
        Row(
          children: [
            for (final m in _BizPayMethod.values) ...[
              Expanded(
                child: _BizPayMethodCard(
                  method: m,
                  selected: method == m,
                  onTap: () => onChangeMethod(m),
                ),
              ),
              if (m != _BizPayMethod.values.last) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 18),
        if (method == _BizPayMethod.ewallet) ...[
          const _FieldLabel('E-wallet Provider'),
          Row(
            children: [
              for (final k in _BizEWallet.values) ...[
                Expanded(
                  child: _BizEWalletCard(
                    kind: k,
                    selected: eWallet == k,
                    onTap: () => onChangeEWallet(k),
                  ),
                ),
                if (k != _BizEWallet.values.last) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _FieldLabel('${eWallet.label} Number'),
          _PaymentPhoneField(controller: account, onChanged: onChanged),
        ] else ...[
          const _FieldLabel('Bank'),
          _BankSelectField(
            banks: banks,
            value: bankName,
            onChanged: onChangeBank,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('Account Number'),
          _PaymentBankAccountField(
            controller: account,
            enabled: bankName != null,
            onChanged: onChanged,
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: _brandGreen.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_rounded, size: 16, color: _brandGreen),
                  const SizedBox(width: 6),
                  Text(
                    'Secure & Fast Payouts',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: _brandGreenDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Earnings are processed within 24 hours after shift completion. '
                'Withdrawals are free.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.4,
                  color: _brandGreenDark.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BizPayMethodCard extends StatelessWidget {
  const _BizPayMethodCard({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final _BizPayMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _brandGreen.withValues(alpha: 0.06) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _brandGreen : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(method.icon, color: method.color, size: 26),
              const SizedBox(height: 6),
              Text(
                method.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                method.description,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BizEWalletCard extends StatelessWidget {
  const _BizEWalletCard({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final _BizEWallet kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kind.color.withValues(alpha: 0.10) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kind.color : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: kind.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: kind.color,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                kind.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: selected ? kind.color : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// PH mobile field — identical behavior to worker `_PhoneField`.
class _PaymentPhoneField extends StatelessWidget {
  const _PaymentPhoneField({required this.controller, required this.onChanged});

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

class _PaymentBankAccountField extends StatelessWidget {
  const _PaymentBankAccountField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final raw = controller.text;
    String? errorText;
    if (!enabled) {
      errorText = null;
    } else if (raw.isNotEmpty) {
      if (raw.length < 10) {
        errorText = 'Account number must be 10–19 digits (${raw.length}/10)';
      } else if (raw.length > 19) {
        errorText = 'Maximum 19 digits';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: enabled ? 1.0 : 0.55,
          child: IgnorePointer(
            ignoring: !enabled,
            child: _RoundedField(
              controller: controller,
              hint: enabled ? '1234567890' : 'Pick a bank first',
              keyboardType: TextInputType.number,
              maxLength: 19,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(19),
              ],
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          errorText ?? 'Digits only. Most PH banks use 10–16 digits.',
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: errorText != null ? FontWeight.w700 : FontWeight.w600,
            color: errorText != null
                ? const Color(0xFFEF4444)
                : const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}

/// Dropdown-style row that opens a **height-capped** modal sheet instead of
/// `DropdownButton`'s overlay — on some platforms that overlay expands to
/// nearly full-screen height and hides the header / Continue button.
class _BankSelectField extends StatelessWidget {
  const _BankSelectField({
    required this.banks,
    required this.value,
    required this.onChanged,
  });

  final List<String> banks;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (ctx) => _BankPickerSheet(banks: banks, selected: value),
          );
          if (picked != null) onChanged(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasValue ? value! : 'Select your bank',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: hasValue ? FontWeight.w700 : FontWeight.w600,
                    color: hasValue
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF94A3B8),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankPickerSheet extends StatefulWidget {
  const _BankPickerSheet({required this.banks, required this.selected});

  final List<String> banks;
  final String? selected;

  @override
  State<_BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<_BankPickerSheet> {
  late final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.banks
        : widget.banks.where((o) => o.toLowerCase().contains(q)).toList();

    // Cap sheet height so the payment screen header & Continue stay visible.
    final screenH = MediaQuery.sizeOf(context).height;
    final maxSheetH = (screenH * 0.55).clamp(320.0, 520.0);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: maxSheetH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select bank',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFB6BFCB),
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: _brandGreen,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No results',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 2),
                      itemBuilder: (context, i) {
                        final option = filtered[i];
                        final isSelected = option == widget.selected;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          tileColor: isSelected
                              ? _brandGreen.withValues(alpha: 0.08)
                              : null,
                          title: Text(
                            option,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                              color: isSelected
                                  ? _brandGreen
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: _brandGreen,
                                  size: 20,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// ---------- Step 6: Review ----------

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.email,
    required this.kind,
    required this.businessName,
    required this.paymentSummary,
  });

  final String email;
  final _BusinessKind kind;
  final String businessName;
  final String paymentSummary;

  /// Per-kind label for the "business name" review row, e.g. "Trade Name"
  /// for sole props vs "Corporate Name" for corporations.
  String get _businessNameLabel {
    switch (kind) {
      case _BusinessKind.soleProprietorship:
        return 'Trade Name';
      case _BusinessKind.partnership:
        return 'Partnership';
      case _BusinessKind.corporation:
        return 'Corporate Name';
    }
  }

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
        _StepCaption('Review your business information'),
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
              _ReviewRow(label: 'Business Type', value: kind.label),
              const _Divider(),
              _ReviewRow(
                label: _businessNameLabel,
                value: businessName.isEmpty ? '—' : businessName,
              ),
              const _Divider(),
              _ReviewRow(label: 'Payout', value: paymentSummary),
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
                        color: const Color(0xFFB45309),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your business documents will be reviewed by our admin team within 1–2 business days.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.4,
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
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF64748B),
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
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
  const _ApplicationSubmittedView({
    required this.email,
    required this.companyName,
  });

  final String email;
  final String companyName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _mintBg,
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
                  colors: [_brandGreen, _brandGreenDark],
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
                    'Our admin team is reviewing your business',
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
                                  "We'll notify you",
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "You'll receive a notification once your business is verified. This usually takes 1–2 business days.",
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
                    if (email.isNotEmpty || companyName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          'Reviewing ${companyName.isEmpty ? email : companyName}'
                          '${companyName.isNotEmpty && email.isNotEmpty ? ' · $email' : ''}',
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

// ---------- Shared chrome ----------

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
          color: _brandGreen.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: _brandGreen, size: 30),
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

class _RoundedField extends StatelessWidget {
  const _RoundedField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: 1,
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
        counterText: maxLength != null ? '' : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _brandGreen, width: 1.4),
        ),
      ),
    );
  }
}

class _CascadeIn extends StatelessWidget {
  const _CascadeIn({required this.direction, required this.child});

  final int direction;
  final Widget child;

  static const _stepMs = 60;
  static const _maxStagger = 9;

  @override
  Widget build(BuildContext context) {
    final beginX = 0.06 * direction.toDouble();
    if (child is Column) {
      final col = child as Column;
      final children = <Widget>[];
      for (var i = 0; i < col.children.length; i++) {
        final c = col.children[i];
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

import 'package:flutter/foundation.dart';

import '../../domain/enums.dart';
import '../auth/mock_auth_service.dart';
import '../storage/kv_store.dart';
import 'session_models.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required KvStore store,
    required MockAuthService auth,
  })  : _store = store,
        _auth = auth,
        _state = const SessionState(
          stage: AuthStage.needsGettingStarted,
          role: null,
          email: null,
          accountStatus: null,
        );

  static const _kHasSeenGettingStarted = 'agapshift.hasSeenGettingStarted';
  static const _kRole = 'agapshift.role';
  static const _kEmail = 'agapshift.email';
  static const _kOnboardingDone = 'agapshift.onboardingDone';
  static const _kAccountStatus = 'agapshift.accountStatus';

  final KvStore _store;
  final MockAuthService _auth;

  SessionState _state;
  SessionState get state => _state;

  Future<void> load() async {
    final hasSeen = (await _store.getString(_kHasSeenGettingStarted)) == '1';
    final roleRaw = await _store.getString(_kRole);
    final email = await _store.getString(_kEmail);
    final onboardingDone = (await _store.getString(_kOnboardingDone)) == '1';
    final accountStatusRaw = await _store.getString(_kAccountStatus);

    UserRole? role;
    if (roleRaw == 'worker') role = UserRole.worker;
    if (roleRaw == 'business') role = UserRole.business;

    AccountStatus? accountStatus;
    switch (accountStatusRaw) {
      case 'pendingVerification':
        accountStatus = AccountStatus.pendingVerification;
      case 'verified':
        accountStatus = AccountStatus.verified;
      case 'rejected':
        accountStatus = AccountStatus.rejected;
      case 'suspended':
        accountStatus = AccountStatus.suspended;
      default:
        accountStatus = null;
    }

    final stage = !hasSeen
        ? AuthStage.needsGettingStarted
        : role == null
            ? AuthStage.needsRole
            : (email == null || email.isEmpty)
                ? AuthStage.needsEmail
                : onboardingDone
                    ? AuthStage.needsOtp
                    : AuthStage.needsOtp;

    // After OTP verification, we route to onboarding if not done.
    _state = SessionState(
      stage: stage,
      role: role,
      email: email,
      accountStatus: accountStatus,
    );
    notifyListeners();
  }

  Future<void> completeGettingStarted() async {
    await _store.setString(_kHasSeenGettingStarted, '1');
    _state = _state.copyWith(stage: AuthStage.needsRole);
    notifyListeners();
  }

  Future<void> setRole(UserRole role) async {
    await _store.setString(_kRole, role == UserRole.worker ? 'worker' : 'business');
    _state = _state.copyWith(stage: AuthStage.needsEmail, role: role);
    notifyListeners();
  }

  Future<void> submitEmail(String email) async {
    await _store.setString(_kEmail, email);
    await _auth.sendOtp(email: email);
    _state = _state.copyWith(stage: AuthStage.needsOtp, email: email);
    notifyListeners();
  }

  Future<bool> verifyOtp(String code) async {
    final email = _state.email;
    if (email == null || email.isEmpty) return false;
    final ok = await _auth.verifyOtp(email: email, code: code);
    if (!ok) return false;
    final onboardingDone = (await _store.getString(_kOnboardingDone)) == '1';
    _state = _state.copyWith(
      stage: onboardingDone ? AuthStage.authenticated : AuthStage.needsOnboarding,
      accountStatus: _state.accountStatus ?? AccountStatus.pendingVerification,
    );
    notifyListeners();
    return true;
  }

  Future<void> completeOnboardingAndSubmitForReview() async {
    await _store.setString(_kOnboardingDone, '1');
    await _store.setString(_kAccountStatus, 'pendingVerification');
    _state = _state.copyWith(
      stage: AuthStage.authenticated,
      accountStatus: AccountStatus.pendingVerification,
    );
    notifyListeners();
  }

  Future<void> setAccountStatus(AccountStatus status) async {
    await _store.setString(_kAccountStatus, status.name);
    _state = _state.copyWith(accountStatus: status);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _store.remove(_kEmail);
    _state = _state.copyWith(stage: AuthStage.needsEmail, email: null, accountStatus: null);
    notifyListeners();
  }

  Future<void> resetAll() async {
    await _store.remove(_kHasSeenGettingStarted);
    await _store.remove(_kRole);
    await _store.remove(_kEmail);
    await _store.remove(_kOnboardingDone);
    await _store.remove(_kAccountStatus);
    _state = const SessionState(
      stage: AuthStage.needsGettingStarted,
      role: null,
      email: null,
      accountStatus: null,
    );
    notifyListeners();
  }
}


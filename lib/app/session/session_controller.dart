import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/business_identity.dart';
import '../../domain/enums.dart';
import '../../domain/worker_identity.dart';
import '../auth/mock_auth_service.dart';
import '../storage/kv_store.dart';
import '../supabase/supabase_config.dart';
import 'session_models.dart';

class SessionController extends ChangeNotifier {
  SessionController({required KvStore store, required MockAuthService auth})
    : _store = store,
      _auth = auth,
      _state = const SessionState(
        stage: AuthStage.needsGettingStarted,
        role: null,
        email: null,
        accountStatus: null,
        businessIdentity: null,
        workerIdentity: null,
      );

  static const _kHasSeenGettingStarted = 'agapshift.hasSeenGettingStarted';
  static const _kRole = 'agapshift.role';
  static const _kEmail = 'agapshift.email';
  static const _kOnboardingDone = 'agapshift.onboardingDone';
  static const _kAccountStatus = 'agapshift.accountStatus';
  /// JSON string of [profiles.identity_snapshot] (business or worker flow).
  static const _kIdentitySnapshotJson = 'agapshift.profileIdentitySnapshotJson';
  // Pipe-separated mock list of registered account emails — lets us check
  // "does this email have an account?" entirely in KV.
  static const _kAccounts = 'agapshift.accounts';
  /// Set when the user taps **Sign Up** on the login screen (role before account).
  /// While set, onboarding must not skip "Create Account" even if a Supabase
  /// session exists (e.g. stale dev login).
  static const _kRegistrationRoleFirst = 'agapshift.registrationRoleFirst';

  final KvStore _store;
  // Kept for compatibility (e.g. demo OTP verification inside onboarding); the
  // session no longer routes through OTP itself.
  // ignore: unused_field
  final MockAuthService _auth;

  SessionState _state;
  SessionState get state => _state;

  /// Register once (e.g. from [main] bootstrap). Session restore on cold start
  /// can finish after the first [load]; this merges `profiles` when auth appears.
  void bindSupabaseAuthSync() {
    if (!SupabaseConfig.isConfigured) return;
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          unawaited(_applySupabaseSessionToLocal());
        default:
          break;
      }
    });
  }

  Future<void> _applySupabaseSessionToLocal() async {
    if (!SupabaseConfig.isConfigured) return;
    if (Supabase.instance.client.auth.currentSession == null) return;
    try {
      final supaEmail = Supabase.instance.client.auth.currentUser?.email
          ?.trim()
          .toLowerCase();
      if (supaEmail != null && supaEmail.isNotEmpty) {
        await _store.setString(_kEmail, supaEmail);
        await _store.setString(_kHasSeenGettingStarted, '1');
      }
      await _mergeProfileRowIntoKv();
      await _rebuildStateFromKv();
    } catch (_) {}
  }

  /// Re-fetch `profiles` and rebuild auth stage. Call when onboarding opens so a
  /// late auth/session restore or SQL-updated `onboarding_done` sends users to
  /// the dashboard instead of staying on “Create Account”.
  Future<void> refreshFromSupabaseProfile() async {
    await _applySupabaseSessionToLocal();
  }

  Future<void> load() async {
    if (SupabaseConfig.isConfigured) {
      try {
        final authSession = Supabase.instance.client.auth.currentSession;
        if (authSession != null) {
          final supaEmail = authSession.user.email?.trim().toLowerCase();
          if (supaEmail != null && supaEmail.isNotEmpty) {
            await _store.setString(_kEmail, supaEmail);
            await _store.setString(_kHasSeenGettingStarted, '1');
          }
        }
        await _mergeProfileRowIntoKv();
      } catch (_) {}
    }
    await _rebuildStateFromKv();
  }

  Future<void> _rebuildStateFromKv() async {
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

    BusinessIdentityDisplay? businessIdentity;
    WorkerIdentityDisplay? workerIdentity;
    final snapRaw = await _store.getString(_kIdentitySnapshotJson);
    if (snapRaw != null && snapRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(snapRaw);
        businessIdentity =
            businessIdentityFromProfileIdentitySnapshot(decoded);
        workerIdentity = workerIdentityFromProfileIdentitySnapshot(decoded);
      } catch (_) {}
    }

    // Sign-up flow: "Sign Up" on the login screen → role first, then
    // onboarding (email / account is collected there). So we can have a
    // chosen [role] in KV with no [email] yet; that must be needsOnboarding,
    // not needsLogin.
    AuthStage stage;
    if (!hasSeen) {
      stage = AuthStage.needsGettingStarted;
    } else if (email == null || email.isEmpty) {
      if (role == null) {
        stage = AuthStage.needsLogin;
      } else {
        stage = AuthStage.needsOnboarding;
      }
    } else if (role == null) {
      stage = AuthStage.needsRole;
    } else if (!onboardingDone) {
      stage = AuthStage.needsOnboarding;
    } else {
      stage = AuthStage.authenticated;
    }

    _state = SessionState(
      stage: stage,
      role: role,
      email: email,
      accountStatus: accountStatus,
      businessIdentity: businessIdentity,
      workerIdentity: workerIdentity,
    );
    notifyListeners();
  }

  /// Pulls `public.profiles` into local KV (remote role/status; onboarding only
  /// flips to done when the server says so).
  Future<void> _mergeProfileRowIntoKv() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return;

      final role = row['role'] as String?;
      if (role == 'worker') {
        await _store.setString(_kRole, 'worker');
      } else if (role == 'business') {
        await _store.setString(_kRole, 'business');
      }
      if (row['onboarding_done'] == true) {
        await _store.setString(_kOnboardingDone, '1');
      }
      final st = row['account_status'] as String?;
      if (st != null && st.isNotEmpty) {
        await _store.setString(_kAccountStatus, st);
      }
      final snap = row['identity_snapshot'];
      if (snap != null) {
        await _store.setString(_kIdentitySnapshotJson, jsonEncode(snap));
      } else {
        await _store.remove(_kIdentitySnapshotJson);
      }
    } catch (_) {}
  }

  /// Partial UPDATE — omitting `role` leaves the database column unchanged.
  /// Never send JSON null for `role`; that was wiping fixes done in SQL / other sessions.
  Future<void> _pushProfileToSupabase() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final roleRaw = await _store.getString(_kRole);
      final onboardingDone = (await _store.getString(_kOnboardingDone)) == '1';
      final statusRaw = await _store.getString(_kAccountStatus);

      final payload = <String, dynamic>{
        'id': user.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'onboarding_done': onboardingDone,
      };
      if (roleRaw == 'worker' || roleRaw == 'business') {
        payload['role'] = roleRaw;
      }
      if (statusRaw != null && statusRaw.isNotEmpty) {
        payload['account_status'] = statusRaw;
      }
      final em = user.email?.trim();
      if (em != null && em.isNotEmpty) {
        payload['email'] = em;
      }

      final uid = user.id;
      final patch = Map<String, dynamic>.from(payload)
        ..remove('id')
        // Extra guard: Postgres UPDATE must not receive null for optional columns.
        ..removeWhere((_, v) => v == null);

      await Supabase.instance.client.from('profiles').update(patch).eq('id', uid);
    } catch (_) {}
  }

  // ---------- Mock account-existence check ----------

  Future<Set<String>> _loadAccounts() async {
    final raw = (await _store.getString(_kAccounts)) ?? '';
    if (raw.isEmpty) return <String>{};
    return raw.split('|').where((e) => e.isNotEmpty).toSet();
  }

  Future<void> _saveAccounts(Set<String> accounts) async {
    await _store.setString(_kAccounts, accounts.join('|'));
  }

  Future<bool> hasAccount(String email) async {
    final accounts = await _loadAccounts();
    return accounts.contains(email.trim().toLowerCase());
  }

  /// After a successful sign-in: `true` if a `profiles` row exists for
  /// [auth.uid()], `false` if the query succeeded and there is no row,
  /// `null` if the check failed (network/RLS).
  Future<bool?> _profileRowExistsForCurrentUser() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return false;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('id', uid)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return null;
    }
  }

  /// Whether [public.profiles] has a row for this email (Supabase). Used after a
  /// failed password attempt: no row → suggest sign-up; row exists → wrong password.
  /// Returns `null` if the check could not run (fall back to generic error).
  Future<bool?> _profileExistsForEmailSupabase(String email) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'profile_exists_for_email',
        params: <String, dynamic>{'p_email': email},
      );
      if (result is bool) return result;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Persist that this email has an account (called when sign-up completes).
  Future<void> registerEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    final accounts = await _loadAccounts();
    accounts.add(normalized);
    await _saveAccounts(accounts);
    await _store.setString(_kEmail, normalized);
    await _rebuildStateFromKv();
  }

  // ---------- Stage transitions ----------

  Future<void> completeGettingStarted() async {
    await _store.setString(_kHasSeenGettingStarted, '1');
    _state = _state.copyWith(stage: AuthStage.needsLogin);
    notifyListeners();
  }

  /// Login: [SupabaseConfig] + initialized Supabase → email/password via
  /// Supabase Auth; otherwise mock KV accounts.
  Future<LoginResult> attemptLogin({
    required String email,
    required String password,
  }) async {
    if (password.trim().isEmpty) return LoginResult.invalidCredentials;

    if (SupabaseConfig.isConfigured) {
      try {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
      } on AuthException {
        final exists = await _profileExistsForEmailSupabase(email.trim());
        if (exists == false) {
          return LoginResult.notFound;
        }
        return LoginResult.invalidCredentials;
      } catch (_) {
        return LoginResult.unexpectedError;
      }

      final profileRow = await _profileRowExistsForCurrentUser();
      if (profileRow == false) {
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        return LoginResult.notFound;
      }
      if (profileRow == null) {
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        return LoginResult.unexpectedError;
      }

      await _persistSessionAfterAuth(email.trim().toLowerCase());
      return LoginResult.success;
    }

    final exists = await hasAccount(email);
    if (!exists) return LoginResult.notFound;
    await _persistSessionAfterAuth(email.trim().toLowerCase());
    return LoginResult.success;
  }

  /// Supabase sign-up after onboarding "Create Account" (step 0). Mock/offline
  /// builds return [SignUpResult.skipped]. If the email is already registered,
  /// tries [signInWithPassword] with the same password (covers returning users).
  Future<SignUpResult> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (!SupabaseConfig.isConfigured) return SignUpResult.skipped;

    final trimmed = email.trim();
    final normalized = trimmed.toLowerCase();

    try {
      await Supabase.instance.client.auth.signUp(
        email: trimmed,
        password: password,
      );
      await _syncEmailAfterSupabaseSignUp(normalized);
      return SignUpResult.success;
    } on AuthException catch (e) {
      if (_duplicateRegistrationMessage(e)) {
        try {
          await Supabase.instance.client.auth.signInWithPassword(
            email: trimmed,
            password: password,
          );
          await _syncEmailAfterSupabaseSignUp(normalized);
          return SignUpResult.success;
        } on AuthException {
          return SignUpResult.emailAlreadyRegistered;
        } catch (_) {
          return SignUpResult.unexpectedError;
        }
      }
      final m = e.message.toLowerCase();
      if (m.contains('password')) return SignUpResult.weakPassword;
      return SignUpResult.unexpectedError;
    } catch (_) {
      return SignUpResult.unexpectedError;
    }
  }

  bool _duplicateRegistrationMessage(AuthException e) {
    final m = e.message.toLowerCase();
    return m.contains('already registered') ||
        m.contains('already been registered') ||
        m.contains('user already');
  }

  Future<void> _syncEmailAfterSupabaseSignUp(String normalized) async {
    await _store.setString(_kEmail, normalized);
    if (SupabaseConfig.isConfigured) {
      await _mergeProfileRowIntoKv();
      await _pushProfileToSupabase();
    }
    await _rebuildStateFromKv();
  }

  Future<void> _persistSessionAfterAuth(String normalizedEmail) async {
    await _store.remove(_kRegistrationRoleFirst);
    await _store.setString(_kEmail, normalizedEmail);
    if (SupabaseConfig.isConfigured) {
      // Pull profile only. Do not upsert here: PostgREST upsert can still clear
      // columns like `role` when the payload omits them / merges badly after
      // sign-out cleared local KV — that was wiping `profiles.role` on login.
      await _mergeProfileRowIntoKv();
    }
    await _rebuildStateFromKv();
  }

  /// User tapped "Sign Up" on the login screen — proceed to role selection.
  Future<void> startSignUp() async {
    await _store.setString(_kRegistrationRoleFirst, '1');
    _state = _state.copyWith(stage: AuthStage.needsRole, role: null);
    notifyListeners();
  }

  /// After Create Account (step 0) succeeds — allow skip on future opens when session exists.
  Future<void> markOnboardingAccountStepFinished() async {
    await _store.remove(_kRegistrationRoleFirst);
  }

  /// Whether onboarding may auto-advance past Create Account for returning users.
  Future<bool> shouldSkipOnboardingCreateAccountStep() async {
    if ((await _store.getString(_kRegistrationRoleFirst)) == '1') return false;
    if (!SupabaseConfig.isConfigured) return false;
    if (Supabase.instance.client.auth.currentSession == null) return false;
    final email = state.email;
    if (email == null || email.isEmpty) return false;
    return true;
  }

  Future<void> setRole(UserRole role) async {
    await _store.setString(
      _kRole,
      role == UserRole.worker ? 'worker' : 'business',
    );
    if (SupabaseConfig.isConfigured) {
      await _pushProfileToSupabase();
    }
    await _rebuildStateFromKv();
  }

  /// Reverse navigation from the role-selection screen back to login.
  /// Used by the in-screen back button since `RoleSelectionScreen` is mounted
  /// directly by `SessionGate` rather than pushed onto a navigator stack.
  Future<void> goBackToLogin() async {
    await _store.remove(_kRegistrationRoleFirst);
    _state = _state.copyWith(stage: AuthStage.needsLogin, role: null);
    notifyListeners();
  }

  /// Reverse navigation from onboarding step 1 back to role selection. We
  /// clear the persisted role so a future cold start lands the user on the
  /// role picker again instead of bouncing straight back into onboarding.
  ///
  /// Does **not** write `role = null` to Supabase — that was clearing roles you
  /// fixed in the SQL editor while the app stayed open; next merge/token refresh
  /// would re-fetch the real role from the server anyway.
  Future<void> goBackToRoleSelection() async {
    await _store.remove(_kRole);
    await _rebuildStateFromKv();
  }

  /// Called after the multi-step registration form. Marks onboarding done and
  /// drops the user into the dashboard with limited (pending) access.
  ///
  /// [completedAsRole] is required so role is always persisted even if KV was
  /// cleared mid-flow (e.g. back navigation) or server merge is stale.
  /// Local state is updated **before** Supabase sync so a failed network/RLS
  /// update does not trap the user in onboarding.
  Future<void> completeOnboardingAndSubmitForReview(UserRole completedAsRole) async {
    await _store.setString(
      _kRole,
      completedAsRole == UserRole.worker ? 'worker' : 'business',
    );
    await _store.setString(_kOnboardingDone, '1');
    await _store.setString(_kAccountStatus, 'pendingVerification');
    await _rebuildStateFromKv();

    if (SupabaseConfig.isConfigured) {
      try {
        await _pushProfileToSupabase();
        await _mergeProfileRowIntoKv();
        await _rebuildStateFromKv();
      } catch (e, st) {
        assert(() {
          debugPrint('completeOnboarding Supabase sync failed: $e\n$st');
          return true;
        }());
      }
    }
  }

  Future<void> setAccountStatus(AccountStatus status) async {
    await _store.setString(_kAccountStatus, status.name);
    if (SupabaseConfig.isConfigured) {
      await _pushProfileToSupabase();
    }
    await _rebuildStateFromKv();
  }

  Future<void> signOut() async {
    if (SupabaseConfig.isConfigured) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    }
    await _store.remove(_kEmail);
    await _store.remove(_kRole);
    await _store.remove(_kOnboardingDone);
    await _store.remove(_kAccountStatus);
    await _store.remove(_kIdentitySnapshotJson);
    await _store.remove(_kRegistrationRoleFirst);
    await _rebuildStateFromKv();
  }

  Future<void> resetAll() async {
    if (SupabaseConfig.isConfigured) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    }
    await _store.remove(_kHasSeenGettingStarted);
    await _store.remove(_kRole);
    await _store.remove(_kEmail);
    await _store.remove(_kOnboardingDone);
    await _store.remove(_kAccountStatus);
    await _store.remove(_kRegistrationRoleFirst);
    await _store.remove(_kAccounts);
    await _store.remove(_kIdentitySnapshotJson);
    _state = const SessionState(
      stage: AuthStage.needsGettingStarted,
      role: null,
      email: null,
      accountStatus: null,
      businessIdentity: null,
      workerIdentity: null,
    );
    notifyListeners();
  }
}

import '../../domain/business_identity.dart';
import '../../domain/enums.dart';
import '../../domain/worker_identity.dart';

/// New high-level flow:
/// needsGettingStarted → needsLogin → (login OK) authenticated
///                     │            └─ no role     → needsRole → needsOnboarding → authenticated
///                     └─ Sign Up tapped → needsRole → needsOnboarding → authenticated
enum AuthStage {
  needsGettingStarted,
  needsLogin,
  needsRole,
  needsOnboarding,
  authenticated,
}

class SessionState {
  const SessionState({
    required this.stage,
    required this.role,
    required this.email,
    required this.accountStatus,
    this.businessIdentity,
    this.workerIdentity,
  });

  final AuthStage stage;
  final UserRole? role;
  final String? email;
  final AccountStatus? accountStatus;

  /// Cached from [profiles.identity_snapshot] (KV + merge) so business profile UI
  /// can paint without waiting on a second network round-trip.
  final BusinessIdentityDisplay? businessIdentity;

  /// Cached worker name/bio/skills from [profiles.identity_snapshot] when [flow] is `worker`.
  final WorkerIdentityDisplay? workerIdentity;

  SessionState copyWith({
    AuthStage? stage,
    UserRole? role,
    String? email,
    AccountStatus? accountStatus,
    BusinessIdentityDisplay? businessIdentity,
    WorkerIdentityDisplay? workerIdentity,
  }) {
    return SessionState(
      stage: stage ?? this.stage,
      role: role ?? this.role,
      email: email ?? this.email,
      accountStatus: accountStatus ?? this.accountStatus,
      businessIdentity: businessIdentity ?? this.businessIdentity,
      workerIdentity: workerIdentity ?? this.workerIdentity,
    );
  }
}

/// Result of a login attempt (mock KV or Supabase Auth).
enum LoginResult {
  success,
  /// No app registration: mock list miss, failed auth + no `profiles` email, or
  /// auth succeeded but no `profiles` row for this user (show sign-up alert).
  notFound,
  /// Wrong password, invalid email format, or unknown user (Supabase).
  invalidCredentials,
  /// Signed-in user is `profiles.role = admin` (staff). Use the web admin only.
  staffUseWebAdmin,
  unexpectedError,
}

/// Result of Supabase sign-up from onboarding (mock builds skip this).
enum SignUpResult {
  /// Local/mock mode — no network sign-up.
  skipped,
  success,
  /// Email taken and password did not sign in (wrong password or OAuth-only user).
  emailAlreadyRegistered,
  weakPassword,
  unexpectedError,
}

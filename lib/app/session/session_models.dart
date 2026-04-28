import '../../domain/enums.dart';

enum AuthStage {
  needsGettingStarted,
  needsRole,
  needsEmail,
  needsOtp,
  needsOnboarding,
  authenticated,
}

class SessionState {
  const SessionState({
    required this.stage,
    required this.role,
    required this.email,
    required this.accountStatus,
  });

  final AuthStage stage;
  final UserRole? role;
  final String? email;
  final AccountStatus? accountStatus;

  SessionState copyWith({
    AuthStage? stage,
    UserRole? role,
    String? email,
    AccountStatus? accountStatus,
  }) {
    return SessionState(
      stage: stage ?? this.stage,
      role: role ?? this.role,
      email: email ?? this.email,
      accountStatus: accountStatus ?? this.accountStatus,
    );
  }
}


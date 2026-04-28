import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../marketplace/marketplace_scope.dart';
import '../session/session_controller.dart';
import '../session/session_models.dart';
import 'screens/auth/getting_started_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/role_selection_screen.dart';
import 'screens/auth/sign_in_email_screen.dart';
import 'screens/dashboard/business_dashboard_shell.dart';
import 'screens/dashboard/worker_dashboard_shell.dart';
import 'screens/onboarding/business_onboarding_screen.dart';
import 'screens/onboarding/worker_onboarding_screen.dart';
import 'screens/status/verification_status_screen.dart';

class SessionGate extends StatelessWidget {
  const SessionGate({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final state = session.state;
        switch (state.stage) {
          case AuthStage.needsGettingStarted:
            return GettingStartedScreen(
              onGetStarted: session.completeGettingStarted,
            );
          case AuthStage.needsRole:
            return RoleSelectionScreen(
              onSelectRole: session.setRole,
            );
          case AuthStage.needsEmail:
            return SignInEmailScreen(
              role: state.role,
              onSubmit: session.submitEmail,
            );
          case AuthStage.needsOtp:
            return OtpScreen(
              email: state.email ?? '',
              onVerify: session.verifyOtp,
              onBack: session.signOut,
              onResend: () async {
                final email = state.email;
                if (email != null && email.isNotEmpty) {
                  await session.submitEmail(email);
                }
              },
            );
          case AuthStage.needsOnboarding:
            final role = state.role;
            if (role == UserRole.business) {
              return BusinessOnboardingScreen(
                onSubmit: session.completeOnboardingAndSubmitForReview,
              );
            }
            return WorkerOnboardingScreen(
              onSubmit: session.completeOnboardingAndSubmitForReview,
            );
          case AuthStage.authenticated:
            final role = state.role;
            final status = state.accountStatus ?? AccountStatus.pendingVerification;
            if (status != AccountStatus.verified) {
              return VerificationStatusScreen(
                status: status,
                onReset: session.resetAll,
                onDemoMarkVerified: () => session.setAccountStatus(AccountStatus.verified),
              );
            }
            final marketplace = MarketplaceScope.of(context);
            if (role == UserRole.business) {
              return BusinessDashboardShell(
                onSignOut: session.resetAll,
                onDebugSetStatus: session.setAccountStatus,
                repo: marketplace.repo,
                notifications: marketplace.notifications,
                payments: marketplace.payments,
                shift: marketplace.shift,
                ratings: marketplace.ratings,
                session: marketplace.session,
              );
            }
            return WorkerDashboardShell(
              onSignOut: session.resetAll,
              onDebugSetStatus: session.setAccountStatus,
              repo: marketplace.repo,
              notifications: marketplace.notifications,
              payments: marketplace.payments,
              shift: marketplace.shift,
              ratings: marketplace.ratings,
              session: marketplace.session,
            );
        }
      },
    );
  }
}


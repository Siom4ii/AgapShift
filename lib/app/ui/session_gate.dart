import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../marketplace/marketplace_scope.dart';
import '../session/session_controller.dart';
import '../session/session_models.dart';
import 'screens/auth/getting_started_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/role_selection_screen.dart';
import 'screens/dashboard/business_dashboard_shell.dart';
import 'screens/dashboard/worker_dashboard_shell.dart';
import 'screens/onboarding/business_onboarding_screen.dart';
import 'screens/onboarding/worker_onboarding_screen.dart';
import 'screens/status/verification_status_screen.dart';
import 'widgets/logout_confirmation.dart';

class SessionGate extends StatelessWidget {
  const SessionGate({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final state = session.state;

        Future<void> guardedSignOut() async {
          if (!context.mounted) return;
          final ok = await confirmLogout(context);
          if (ok && context.mounted) await session.signOut();
        }

        switch (state.stage) {
          case AuthStage.needsGettingStarted:
            return GettingStartedScreen(
              onGetStarted: session.completeGettingStarted,
            );
          case AuthStage.needsLogin:
            return LoginScreen(
              onLogin: ({required email, required password}) =>
                  session.attemptLogin(email: email, password: password),
              onTapSignUp: session.startSignUp,
            );
          case AuthStage.needsRole:
            return RoleSelectionScreen(
              onSelectRole: session.setRole,
              onBack: session.goBackToLogin,
            );
          case AuthStage.needsOnboarding:
            final role = state.role;
            if (role == UserRole.business) {
              return BusinessOnboardingScreen(
                onSubmit: () => session.completeOnboardingAndSubmitForReview(
                  UserRole.business,
                ),
                onBack: session.goBackToRoleSelection,
              );
            }
            return WorkerOnboardingScreen(
              onSubmit: () => session.completeOnboardingAndSubmitForReview(
                UserRole.worker,
              ),
              onBack: session.goBackToRoleSelection,
            );
          case AuthStage.authenticated:
            final role = state.role;
            final status =
                state.accountStatus ?? AccountStatus.pendingVerification;
            // Hard-gate only the truly-blocked statuses; for `pendingVerification`
            // and `rejected` the user is allowed into the dashboard with a
            // limited-access banner + locked actions.
            if (status == AccountStatus.suspended) {
              return VerificationStatusScreen(
                status: status,
                onReset: session.resetAll,
              );
            }
            final marketplace = MarketplaceScope.of(context);
            if (role == UserRole.business) {
              return BusinessDashboardShell(
                onSignOut: guardedSignOut,
                repo: marketplace.repo,
                notifications: marketplace.notifications,
                payments: marketplace.payments,
                shift: marketplace.shift,
                ratings: marketplace.ratings,
                session: marketplace.session,
              );
            }
            return WorkerDashboardShell(
              onSignOut: guardedSignOut,
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

import 'package:flutter/material.dart';

import '../../../marketplace/marketplace_repository.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../payments/mock_payments_repository.dart';
import '../../../session/session_controller.dart';
import '../../../shift/mock_shift_repository.dart';
import '../../../ratings/mock_ratings_repository.dart';
import '../marketplace/business_create_gig_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/business_profile_screen.dart';
import '../wallet/business_wallet_screen.dart';
import '../../widgets/business_shell_bottom_nav.dart';
import '../../widgets/locked_action.dart';
import '../../widgets/shell_tab_transition.dart';
import '../../widgets/verification_banner.dart';
import 'business_find_workers_screen.dart';
import 'business_home_screen.dart';

class BusinessDashboardShell extends StatefulWidget {
  const BusinessDashboardShell({
    super.key,
    required this.onSignOut,
    required this.repo,
    required this.notifications,
    required this.payments,
    required this.shift,
    required this.ratings,
    required this.session,
  });

  final Future<void> Function() onSignOut;
  final MarketplaceRepository repo;
  final MockNotificationRepository notifications;
  final MockPaymentsRepository payments;
  final MockShiftRepository shift;
  final MockRatingsRepository ratings;
  final SessionController session;

  @override
  State<BusinessDashboardShell> createState() => _BusinessDashboardShellState();
}

class _BusinessDashboardShellState extends State<BusinessDashboardShell> {
  /// 0 Home, 1 Workers, 2 Wallet, 3 Profile
  int _contentIndex = 0;
  bool _verificationPopupShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _verificationPopupShown) return;
      _verificationPopupShown = true;
      await showVerificationReviewDialog(context, session: widget.session);
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
          repo: widget.notifications,
          session: widget.session,
        ),
      ),
    );
  }

  Future<void> _openPostJob() async {
    if (!canPerformVerifiedAction(widget.session)) {
      await showLockedFeatureDialog(
        context,
        session: widget.session,
        featureName: 'Posting jobs',
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BusinessCreateGigScreen(
          repo: widget.repo,
          session: widget.session,
          onCreated: () async {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            setState(() => _contentIndex = 0);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = switch (_contentIndex) {
      0 => BusinessHomeScreen(
        repo: widget.repo,
        session: widget.session,
        notifications: widget.notifications,
        payments: widget.payments,
        onPostJob: _openPostJob,
        onFindWorkers: () => setState(() => _contentIndex = 1),
        onOpenWallet: () => setState(() => _contentIndex = 2),
        onOpenNotifications: _openNotifications,
      ),
      1 => BusinessFindWorkersScreen(onOpenNotifications: _openNotifications),
      2 => BusinessWalletScreen(onOpenNotifications: _openNotifications),
      _ => BusinessProfileScreen(
        session: widget.session,
        marketRepo: widget.repo,
        ratings: widget.ratings,
        embedded: true,
        showFollowFab: false,
        onLogout: widget.onSignOut,
        onOpenNotifications: _openNotifications,
      ),
    };

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: ShellTabTransition(
            tabIndex: _contentIndex,
            child: screen,
          ),
        ),
      ),
      bottomNavigationBar: BusinessShellBottomNav(
        contentIndex: _contentIndex,
        onContentIndex: (i) => setState(() => _contentIndex = i),
        onPostJob: _openPostJob,
      ),
    );
  }
}

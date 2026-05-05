import 'package:flutter/material.dart';

import '../../../../domain/enums.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../notifications/notification_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../../ratings/mock_ratings_repository.dart';
import '../marketplace/worker_gigs_screen.dart';
import '../marketplace/worker_find_jobs_screen.dart';
import '../messages/messages_inbox_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/worker_profile_screen.dart';
import '../shift/worker_shift_screen.dart';
import '../wallet/wallet_screen.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/agap_app_bar.dart';
import '../../widgets/agap_shell_nav.dart';
import '../../widgets/shell_tab_transition.dart';
import '../../widgets/verification_banner.dart';

class WorkerDashboardShell extends StatefulWidget {
  const WorkerDashboardShell({
    super.key,
    required this.onSignOut,
    required this.onDebugSetStatus,
    required this.repo,
    required this.notifications,
    required this.payments,
    required this.shift,
    required this.ratings,
    required this.session,
  });

  final Future<void> Function() onSignOut;
  final Future<void> Function(AccountStatus status) onDebugSetStatus;
  final MarketplaceRepository repo;
  final NotificationRepository notifications;
  final PaymentsRepository payments;
  final ShiftRepository shift;
  final MockRatingsRepository ratings;
  final SessionController session;

  @override
  State<WorkerDashboardShell> createState() => _WorkerDashboardShellState();
}

class _WorkerDashboardShellState extends State<WorkerDashboardShell> {
  int _index = 0;
  bool _verificationPopupShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_verificationPopupShown) {
        _verificationPopupShown = true;
        await showVerificationReviewDialog(context, session: widget.session);
      }
      if (mounted) {
        await _syncNotificationBadge();
      }
    });
  }

  Future<void> _openInbox() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MessagesInboxScreen(),
      ),
    );
  }

  /// Kept for [WorkerFindJobsScreen.onNotificationsFlowDone] / profile flows;
  /// the shell app bar no longer shows a notification badge.
  Future<void> _syncNotificationBadge() async {}

  @override
  Widget build(BuildContext context) {
    final screen = switch (_index) {
      0 => WorkerGigsScreen(
          repo: widget.repo,
          notifications: widget.notifications,
          session: widget.session,
        ),
      1 => WorkerFindJobsScreen(
          repo: widget.repo,
          notifications: widget.notifications,
          session: widget.session,
          onNotificationsFlowDone: _syncNotificationBadge,
        ),
      2 => WorkerShiftScreen(
          marketRepo: widget.repo,
          shiftRepo: widget.shift,
          payments: widget.payments,
          session: widget.session,
          showAppBar: false,
        ),
      3 => WalletScreen(payments: widget.payments, session: widget.session, embedded: true),
      _ => WorkerProfileScreen(
          session: widget.session,
          shiftRepo: widget.shift,
          ratings: widget.ratings,
          marketRepo: widget.repo,
          payments: widget.payments,
          embedded: true,
          onOpenMessages: _openInbox,
          onOpenNotifications: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NotificationsScreen(
                  repo: widget.notifications,
                  session: widget.session,
                ),
              ),
            );
            if (mounted) {
              await _syncNotificationBadge();
            }
          },
          onLogout: widget.onSignOut,
        ),
    };

    return Scaffold(
      backgroundColor: AgapColors.pageBackground,
      appBar: _index == 4
          ? null
          : AgapAppBar(
        onSearchTap: null,
        onInboxTap: _openInbox,
        inboxUnreadCount: 0,
        onNotificationTap: null,
        notificationUnreadCount: 0,
        extraActions: const [],
      ),
      body: ShellTabTransition(
        tabIndex: _index,
        child: screen,
      ),
      bottomNavigationBar: AgapShellNavBar(
        selectedIndex: _index,
        onSelect: (i) {
          setState(() => _index = i);
          _syncNotificationBadge();
        },
        destinations: const [
          AgapShellDestination(
            icon: Icons.map_outlined,
            selectedIcon: Icons.map_rounded,
            label: 'Home',
          ),
          AgapShellDestination(
            icon: Icons.search_rounded,
            selectedIcon: Icons.search_rounded,
            label: 'Find Jobs',
          ),
          AgapShellDestination(
            icon: Icons.event_note_outlined,
            selectedIcon: Icons.event_note_rounded,
            label: 'My Shift',
          ),
          AgapShellDestination(
            icon: Icons.account_balance_wallet_outlined,
            selectedIcon: Icons.account_balance_wallet_rounded,
            label: 'Wallet',
          ),
          AgapShellDestination(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

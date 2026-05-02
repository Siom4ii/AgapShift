import 'package:flutter/material.dart';

import '../../../../domain/enums.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../payments/mock_payments_repository.dart';
import '../../../session/session_controller.dart';
import '../../../shift/mock_shift_repository.dart';
import '../../../ratings/mock_ratings_repository.dart';
import '../marketplace/worker_gigs_screen.dart';
import '../marketplace/worker_find_jobs_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/worker_profile_screen.dart';
import '../shift/worker_shift_screen.dart';
import '../wallet/wallet_screen.dart';
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
  final MockNotificationRepository notifications;
  final MockPaymentsRepository payments;
  final MockShiftRepository shift;
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
    // Show the "under review" popup once per shell mount for unverified users.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _verificationPopupShown) return;
      _verificationPopupShown = true;
      await showVerificationReviewDialog(context, session: widget.session);
    });
  }

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
          embedded: true,
        ),
    };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AgapAppBar(
        avatar: agapRoleAvatar(isBusiness: false),
        onSearchTap: null,
        onNotificationTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NotificationsScreen(
                repo: widget.notifications,
                session: widget.session,
              ),
            ),
          );
        },
        extraActions: [
          PopupMenuButton<AccountStatus>(
            tooltip: 'Debug status',
            onSelected: (s) async => widget.onDebugSetStatus(s),
            itemBuilder: (context) => const [
              PopupMenuItem(value: AccountStatus.verified, child: Text('Set Verified')),
              PopupMenuItem(value: AccountStatus.pendingVerification, child: Text('Set Pending')),
              PopupMenuItem(value: AccountStatus.rejected, child: Text('Set Rejected')),
              PopupMenuItem(value: AccountStatus.suspended, child: Text('Set Suspended')),
            ],
          ),
          PopupMenuButton<_UserMenu>(
            tooltip: 'Menu',
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _UserMenu.logout,
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded),
                    SizedBox(width: 10),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
            onSelected: (v) async {
              if (v == _UserMenu.logout) await widget.onSignOut();
            },
          ),
        ],
      ),
      body: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: ShellTabTransition(
          tabIndex: _index,
          child: screen,
        ),
      ),
      bottomNavigationBar: AgapShellNavBar(
        selectedIndex: _index,
        onSelect: (i) => setState(() => _index = i),
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

enum _UserMenu { logout }

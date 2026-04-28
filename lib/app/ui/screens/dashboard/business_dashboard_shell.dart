import 'package:flutter/material.dart';

import '../../../../domain/enums.dart';
import '../../../marketplace/mock_marketplace_repository.dart';
import '../../../notifications/mock_notification_repository.dart';
import '../../../payments/mock_payments_repository.dart';
import '../../../ratings/mock_ratings_repository.dart';
import '../../../session/session_controller.dart';
import '../../../shift/mock_shift_repository.dart';
import '../marketplace/business_create_gig_screen.dart';
import '../marketplace/business_gigs_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/business_profile_screen.dart';

class BusinessDashboardShell extends StatefulWidget {
  const BusinessDashboardShell({
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
  final MockMarketplaceRepository repo;
  final MockNotificationRepository notifications;
  final MockPaymentsRepository payments;
  final MockShiftRepository shift;
  final MockRatingsRepository ratings;
  final SessionController session;

  @override
  State<BusinessDashboardShell> createState() => _BusinessDashboardShellState();
}

class _BusinessDashboardShellState extends State<BusinessDashboardShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screen = switch (_index) {
      0 => BusinessCreateGigScreen(
          repo: widget.repo,
          session: widget.session,
          onCreated: () async => setState(() => _index = 1),
        ),
      1 => BusinessGigsScreen(
          repo: widget.repo,
          notifications: widget.notifications,
          payments: widget.payments,
          shiftRepo: widget.shift,
          session: widget.session,
        ),
      2 => const _Placeholder(title: 'Workers', body: 'Nearby worker discovery comes next.'),
      _ => BusinessProfileScreen(
          session: widget.session,
          marketRepo: widget.repo,
          ratings: widget.ratings,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business'),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NotificationsScreen(
                    repo: widget.notifications,
                    session: widget.session,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.notifications_outlined),
          ),
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
      body: screen,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add_box_outlined), label: 'Post'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Gigs'),
          NavigationDestination(icon: Icon(Icons.people_alt_outlined), label: 'Workers'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

enum _UserMenu { logout }

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}


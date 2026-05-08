import 'package:flutter/material.dart';

import '../../../marketplace/marketplace_repository.dart';
import '../../../notifications/notification_repository.dart';
import '../../../payments/payments_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../shift/shift_repository.dart';
import '../../../ratings/ratings_repository.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../marketplace/business_create_gig_screen.dart';
import '../messages/messages_inbox_screen.dart';
import '../notifications/notifications_screen.dart';
import '../profile/business_profile_screen.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/business_shell_bottom_nav.dart';
import '../../widgets/success_feedback.dart';
import '../../widgets/locked_action.dart';
import '../../widgets/shell_tab_transition.dart';
import '../../widgets/verification_banner.dart';
import 'business_find_workers_screen.dart';
import 'business_home_screen.dart';
import '../marketplace/business_gigs_screen.dart';

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
  final NotificationRepository notifications;
  final PaymentsRepository payments;
  final ShiftRepository shift;
  final RatingsRepository ratings;
  final SessionController session;

  @override
  State<BusinessDashboardShell> createState() => _BusinessDashboardShellState();
}

class _BusinessDashboardShellState extends State<BusinessDashboardShell> {
  /// 0 Home, 1 Listings, 2 Workers, 3 Profile
  int _contentIndex = 0;
  bool _verificationPopupShown = false;
  int _notifUnread = 0;
  int _inboxUnread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      if (!_verificationPopupShown) {
        _verificationPopupShown = true;
        await showVerificationReviewDialog(context, session: widget.session);
        if (!mounted) return;
        await showVerifiedCongratsDialog(context, session: widget.session);
      }
      if (mounted) {
        await _syncNotificationBadge();
        await _syncInboxBadge();
      }
    });
  }

  Future<void> _syncNotificationBadge() async {
    final uid = appActorId(widget.session, mockFallback: '');
    if (uid.isEmpty) {
      if (mounted) {
        setState(() => _notifUnread = 0);
      }
      return;
    }
    try {
      final notifs = await widget.notifications.listForUser(uid);
      final unread = notifs.where((n) => n.readAt == null).length;
      if (mounted) {
        setState(() => _notifUnread = unread);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notifUnread = 0);
      }
    }
  }

  Future<void> _syncInboxBadge() async {
    try {
      final scope = MarketplaceScope.tryOf(context);
      final n = await scope?.messaging.unreadCount();
      if (mounted) setState(() => _inboxUnread = n ?? 0);
    } catch (_) {
      if (mounted) setState(() => _inboxUnread = 0);
    }
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
    if (mounted) {
      await _syncNotificationBadge();
    }
  }

  Future<void> _openInbox() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MessagesInboxScreen(),
      ),
    );
    if (mounted) {
      await _syncInboxBadge();
    }
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
            if (!mounted) return;
            showSuccessSnackBar(context, 'Job posted successfully');
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
        shiftRepo: widget.shift,
        notifications: widget.notifications,
        payments: widget.payments,
        ratings: widget.ratings,
        onPostJob: _openPostJob,
        onFindWorkers: () => setState(() => _contentIndex = 1),
        onOpenNotifications: _openNotifications,
        onOpenInbox: _openInbox,
        notificationUnreadCount: _notifUnread,
        inboxUnreadCount: _inboxUnread,
      ),
      1 => BusinessGigsScreen(
        repo: widget.repo,
        notifications: widget.notifications,
        payments: widget.payments,
        ratings: widget.ratings,
        session: widget.session,
        shiftRepo: widget.shift,
        embedded: true,
      ),
      2 => BusinessFindWorkersScreen(
        repo: widget.repo,
        session: widget.session,
        ratings: widget.ratings,
        shiftRepo: widget.shift,
        notifications: widget.notifications,
        payments: widget.payments,
        onOpenNotifications: _openNotifications,
        onOpenInbox: _openInbox,
        notificationUnreadCount: _notifUnread,
        inboxUnreadCount: _inboxUnread,
      ),
      _ => BusinessProfileScreen(
        session: widget.session,
        marketRepo: widget.repo,
        ratings: widget.ratings,
        payments: widget.payments,
        embedded: true,
        showFollowFab: false,
        onLogout: widget.onSignOut,
        onOpenNotifications: _openNotifications,
        onOpenInbox: _openInbox,
        notificationUnreadCount: _notifUnread,
        inboxUnreadCount: _inboxUnread,
      ),
    };

    return Scaffold(
      backgroundColor: AgapColors.pageBackground,
      body: SafeArea(
        bottom: false,
        child: ShellTabTransition(
          tabIndex: _contentIndex,
          child: screen,
        ),
      ),
      bottomNavigationBar: BusinessShellBottomNav(
        contentIndex: _contentIndex,
        onContentIndex: (i) {
          setState(() => _contentIndex = i);
          _syncNotificationBadge();
        },
        onPostJob: _openPostJob,
      ),
    );
  }
}

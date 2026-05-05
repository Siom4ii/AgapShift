import 'package:flutter/material.dart';

import '../branding/agap_logo_assets.dart';
import '../theme/agap_colors.dart';

class AgapAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AgapAppBar({
    super.key,
    this.avatar,
    this.onSearchTap,
    this.onInboxTap,
    this.inboxUnreadCount = 0,
    this.onNotificationTap,
    this.notificationUnreadCount = 0,
    this.extraActions = const [],
  });

  /// Optional leading badge (e.g. role). Omit for a cleaner bar with only wordmark + actions.
  final Widget? avatar;
  final VoidCallback? onSearchTap;
  final VoidCallback? onInboxTap;
  /// Shown on the messages icon when &gt; 0.
  final int inboxUnreadCount;
  final VoidCallback? onNotificationTap;
  /// Shown on the notification icon when &gt; 0 (same count as in-app badges).
  final int notificationUnreadCount;
  final List<Widget> extraActions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (avatar != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4),
                    child: avatar!,
                  ),
                Expanded(
                  child: Center(
                    child: AgapLogoWordmarkChip(height: 22),
                  ),
                ),
                if (onSearchTap != null)
                  IconButton(
                    tooltip: 'Search',
                    onPressed: onSearchTap,
                    icon: Icon(Icons.search_rounded, color: Colors.grey.shade800),
                  ),
                if (onInboxTap != null)
                  Badge(
                    isLabelVisible: inboxUnreadCount > 0,
                    backgroundColor: const Color(0xFFEF4444),
                    textColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    label: Text(
                      inboxUnreadCount > 99 ? '99+' : '$inboxUnreadCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: IconButton(
                      tooltip: 'Messages',
                      onPressed: onInboxTap,
                      icon: Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: AgapColors.primaryBright,
                      ),
                    ),
                  ),
                if (onNotificationTap != null)
                  Badge(
                    isLabelVisible: notificationUnreadCount > 0,
                    backgroundColor: const Color(0xFFEF4444),
                    textColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    label: Text(
                      notificationUnreadCount > 99
                          ? '99+'
                          : '$notificationUnreadCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: IconButton(
                      tooltip: 'Notifications',
                      onPressed: onNotificationTap,
                      icon: Icon(
                        Icons.notifications_outlined,
                        color: AgapColors.primaryBright,
                      ),
                    ),
                  ),
                ...extraActions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

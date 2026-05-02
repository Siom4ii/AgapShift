import 'package:flutter/material.dart';

import '../branding/agap_logo_assets.dart';
import '../theme/agap_colors.dart';

class AgapAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AgapAppBar({
    super.key,
    required this.avatar,
    this.onSearchTap,
    this.onNotificationTap,
    this.extraActions = const [],
  });

  final Widget avatar;
  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationTap;
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
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4),
                  child: avatar,
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
                if (onNotificationTap != null)
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: onNotificationTap,
                    icon: Icon(Icons.notifications_outlined, color: AgapColors.primaryBright),
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

Widget agapRoleAvatar({required bool isBusiness}) {
  return CircleAvatar(
    radius: 20,
    backgroundColor: AgapColors.mintSurface,
    child: Icon(
      isBusiness ? Icons.storefront_rounded : Icons.engineering_rounded,
      color: isBusiness ? AgapColors.primary : Colors.deepOrange.shade700,
      size: 22,
    ),
  );
}

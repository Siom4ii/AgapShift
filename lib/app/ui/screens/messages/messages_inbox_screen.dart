import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../domain/enums.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../messaging/messaging_models.dart';
import '../../../profile/worker_display_names.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';
import 'message_thread_screen.dart';

String _formatActivityTime(DateTime utc) {
  final t = utc.toLocal();
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inSeconds < 45) return 'Now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24 &&
      t.day == now.day &&
      t.month == now.month &&
      t.year == now.year) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  if (diff.inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(t.weekday - 1) % 7];
  }
  if (t.year == now.year) return '${t.month}/${t.day}';
  return '${t.month}/${t.day}/${t.year}';
}

String _initialsForPeer(DmConversationSummary c) {
  final name = c.otherDisplayName.trim();
  // UUID suffix fallback from repo (unicode … or ASCII ...).
  if (name.isEmpty || name.startsWith('…') || name.startsWith('...')) {
    return initialsFromWorkerId(c.otherUserId);
  }
  return applicantInitialsFromName(name, c.otherUserId);
}

class MessagesInboxScreen extends StatefulWidget {
  const MessagesInboxScreen({super.key});

  @override
  State<MessagesInboxScreen> createState() => _MessagesInboxScreenState();
}

class _MessagesInboxScreenState extends State<MessagesInboxScreen> {
  List<DmConversationSummary> _items = const [];
  bool _loading = true;
  String? _error;

  bool get _isBusiness {
    final scope = MarketplaceScope.tryOf(context);
    return scope?.session.state.role == UserRole.business;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scope = MarketplaceScope.of(context);
      final list = await scope.messaging.listConversations();
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final isBusiness = _isBusiness;
    final accent =
        isBusiness ? AgapColors.businessGreen : AgapColors.primaryBright;
    final accentSoft =
        isBusiness ? AgapColors.businessMint : AgapColors.mintSurface;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellChromeBackground(
        kind: isBusiness ? ShellChromeKind.business : ShellChromeKind.worker,
        child: RefreshIndicator(
          color: accent,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                floating: true,
                pinned: true,
                toolbarHeight: 72,
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0.5,
                shadowColor: Colors.black.withValues(alpha: 0.06),
                centerTitle: false,
                titleSpacing: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                title: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Messages',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          height: 1.1,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Recent conversations',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          height: 1.2,
                          color: AgapColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              else if (_items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                accentSoft.withValues(alpha: 0.95),
                                accent.withValues(alpha: 0.22),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.18),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.chat_bubble_rounded,
                            size: 44,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'No conversations yet',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isBusiness
                              ? 'Message a worker from Find Workers — their name will show here once you connect.'
                              : 'When a business messages you, the thread will appear here with their business name.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      '${_items.length} conversation${_items.length == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AgapColors.textMuted,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final c = _items[i];
                      final initials = _initialsForPeer(c);
                      final timeLabel = _formatActivityTime(c.updatedAt);
                      return _InboxConversationCard(
                        accent: accent,
                        accentSoft: accentSoft,
                        title: c.otherDisplayName,
                        preview: c.lastPreview,
                        timeLabel: timeLabel,
                        initials: initials,
                        onTap: () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => MessageThreadScreen(
                                conversationId: c.conversationId,
                                title: c.otherDisplayName,
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxConversationCard extends StatelessWidget {
  const _InboxConversationCard({
    required this.accent,
    required this.accentSoft,
    required this.title,
    required this.preview,
    required this.timeLabel,
    required this.initials,
    required this.onTap,
  });

  final Color accent;
  final Color accentSoft;
  final String title;
  final String preview;
  final String timeLabel;
  final String initials;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPreview = preview.trim().isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE8ECF0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent,
                        Color.lerp(accent, accentSoft, 0.45) ?? accentSoft,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(2.5),
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Text(
                      initials,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: accent,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                height: 1.25,
                                color: const Color(0xFF111827),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeLabel,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AgapColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 14,
                            color: AgapColors.textMuted.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              hasPreview ? preview : 'No messages yet',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: hasPreview
                                    ? const Color(0xFF6B7280)
                                    : AgapColors.textMuted.withValues(
                                        alpha: 0.85,
                                      ),
                                fontStyle: hasPreview
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AgapColors.textMuted.withValues(alpha: 0.7),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

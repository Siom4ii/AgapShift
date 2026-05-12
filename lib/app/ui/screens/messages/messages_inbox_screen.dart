import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/enums.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../messaging/messaging_models.dart';
import '../../../profile/worker_display_names.dart';
import '../../../session/app_actor_id.dart';
import '../../../supabase/supabase_config.dart';
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

String _previewLine(DmConversationSummary c, String myUserId) {
  final raw = c.lastPreview.trim();
  if (raw.isEmpty) return 'No messages yet';
  final sid = c.lastMessageSenderId;
  if (sid == null || myUserId.isEmpty) return raw;
  final fromYou = sid == myUserId;
  final prefix = fromYou ? 'You' : _shortDisplayName(c.otherDisplayName);
  return '$prefix: $raw';
}

String _shortDisplayName(String name) {
  final t = name.trim();
  if (t.length <= 22) return t;
  return '${t.substring(0, 20)}…';
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
  Map<String, bool> _verifiedByUserId = const {};

  bool get _isBusiness {
    final scope = MarketplaceScope.tryOf(context);
    return scope?.session.state.role == UserRole.business;
  }

  String _myUserId(BuildContext context) {
    if (SupabaseConfig.isConfigured) {
      return Supabase.instance.client.auth.currentUser?.id ?? '';
    }
    final scope = MarketplaceScope.tryOf(context);
    if (scope == null) return '';
    return appActorId(scope.session, mockFallback: 'me');
  }

  Future<void> _loadPeerVerified(Set<String> ids) async {
    if (!SupabaseConfig.isConfigured || ids.isEmpty) {
      if (mounted) setState(() => _verifiedByUserId = const {});
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, account_status')
          .inFilter('id', ids.toList());
      final map = <String, bool>{for (final id in ids) id: false};
      for (final raw in rows as List<dynamic>) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = m['id'] as String?;
        if (id == null) continue;
        map[id] =
            (m['account_status'] as String?) == AccountStatus.verified.name;
      }
      if (!mounted) return;
      setState(() => _verifiedByUserId = map);
    } catch (_) {
      if (mounted) setState(() => _verifiedByUserId = const {});
    }
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
      unawaited(_loadPeerVerified(list.map((e) => e.otherUserId).toSet()));
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverList.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final c = _items[i];
                      final initials = _initialsForPeer(c);
                      final timeLabel = _formatActivityTime(c.updatedAt);
                      final myId = _myUserId(context);
                      final previewLine = _previewLine(c, myId);
                      final verified =
                          _verifiedByUserId[c.otherUserId] ?? false;
                      return _InboxConversationCard(
                        accent: accent,
                        accentSoft: accentSoft,
                        title: c.otherDisplayName,
                        previewLine: previewLine,
                        timeLabel: timeLabel,
                        initials: initials,
                        peerVerified: verified,
                        unreadCount: c.unreadCount,
                        onTap: () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => MessageThreadScreen(
                                conversationId: c.conversationId,
                                title: c.otherDisplayName,
                                peerUserId: c.otherUserId,
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                    child: _InboxBottomTipsCard(
                      accent: accent,
                      accentSoft: accentSoft,
                      isBusiness: isBusiness,
                    ),
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
    required this.previewLine,
    required this.timeLabel,
    required this.initials,
    required this.peerVerified,
    required this.unreadCount,
    required this.onTap,
  });

  final Color accent;
  final Color accentSoft;
  final String title;
  final String previewLine;
  final String timeLabel;
  final String initials;
  final bool peerVerified;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emptyPreview = previewLine == 'No messages yet';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: accent.withValues(alpha: 0.08),
        highlightColor: accent.withValues(alpha: 0.04),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE2E6EB),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
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
                    if (unreadCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
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
                            child: Row(
                              children: [
                                Flexible(
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
                                if (peerVerified) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.verified_rounded,
                                    size: 18,
                                    color: accent,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            timeLabel,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AgapColors.textMuted.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        previewLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: emptyPreview
                              ? AgapColors.textMuted.withValues(alpha: 0.8)
                              : const Color(0xFF6B7280),
                          fontStyle: emptyPreview
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AgapColors.textMuted.withValues(alpha: 0.65),
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

class _InboxBottomTipsCard extends StatelessWidget {
  const _InboxBottomTipsCard({
    required this.accent,
    required this.accentSoft,
    required this.isBusiness,
  });

  final Color accent;
  final Color accentSoft;
  final bool isBusiness;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Color.lerp(Colors.white, accentSoft, 0.35)!,
          ],
        ),
        border: Border.all(color: const Color(0xFFE2E6EB)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_outlined, color: accent, size: 22),
              const SizedBox(width: 8),
              Text(
                'Messaging tips',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: const Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _tipRow(
            'Keep job details and pay expectations clear in writing.',
          ),
          const SizedBox(height: 8),
          _tipRow(
            isBusiness
                ? 'Workers see a stronger preview when messages stay professional.'
                : 'Use quick replies during a shift so employers know your status.',
          ),
          const SizedBox(height: 8),
          _tipRow(
            'Use ⋮ in a chat for safety options, reporting, and help.',
          ),
        ],
      ),
    );
  }

  Widget _tipRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(Icons.check_circle_rounded, size: 16, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: AgapColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

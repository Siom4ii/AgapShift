import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/enums.dart';
import '../../../marketplace/marketplace_scope.dart';
import '../../../messaging/messaging_models.dart';
import '../../../messaging/messaging_repository.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../../widgets/shell_screen_polish.dart';

String _initialsFromTitle(String title) {
  final t = title.trim();
  if (t.isEmpty) return '?';
  final parts = t.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  if (parts.isNotEmpty && parts.first.length >= 2) {
    return parts.first.substring(0, 2).toUpperCase();
  }
  return parts.first[0].toUpperCase();
}

String _formatBubbleTime(DateTime utc) {
  final t = utc.toLocal();
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _dateDividerLabel(DateTime localDay) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (localDay == today) return 'Today';
  final y = today.subtract(const Duration(days: 1));
  if (localDay == y) return 'Yesterday';
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[localDay.month - 1]} ${localDay.day}, ${localDay.year}';
}

bool _sameLocalDay(DateTime a, DateTime b) {
  final al = a.toLocal();
  final bl = b.toLocal();
  return al.year == bl.year && al.month == bl.month && al.day == bl.day;
}

class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.peerUserId,
  });

  final String conversationId;
  final String title;

  /// Other participant (for trust badges / future shift context). Optional for older call sites.
  final String? peerUserId;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<List<DmMessage>>? _sub;
  List<DmMessage> _messages = const [];
  String? _error;
  MessagingRepository? _repo;
  SessionController? _session;
  bool _isBusiness = false;
  bool _peerVerified = false;

  String get _senderMe {
    if (SupabaseConfig.isConfigured) {
      return Supabase.instance.client.auth.currentUser?.id ?? '';
    }
    final s = _session;
    if (s == null) return '';
    return appActorId(s, mockFallback: 'me');
  }

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = MarketplaceScope.of(context);
      setState(() {
        _repo = scope.messaging;
        _session = scope.session;
        _isBusiness = scope.session.state.role == UserRole.business;
      });
      unawaited(_loadPeerVerified());
      _listen();
    });
  }

  Future<void> _loadPeerVerified() async {
    final pid = widget.peerUserId?.trim();
    if (pid == null || pid.isEmpty || !SupabaseConfig.isConfigured) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('account_status')
          .eq('id', pid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _peerVerified =
            (row?['account_status'] as String?) == AccountStatus.verified.name;
      });
    } catch (_) {
      // RLS or offline — omit badge.
    }
  }

  void _listen() {
    final r = _repo;
    if (r == null) return;
    _sub?.cancel();
    _sub = r.watchMessages(widget.conversationId).listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _messages = list;
          _error = null;
        });
        _scrollToEnd();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _error = '$e');
      },
    );
  }

  void _scrollToEnd({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      final target = pos.maxScrollExtent;
      if (!animated || (target - pos.pixels).abs() < 4) {
        pos.jumpTo(target);
        return;
      }
      try {
        await _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {
        pos.jumpTo(target);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    final r = _repo;
    if (r != null) {
      unawaited(r.markConversationRead(widget.conversationId));
    }
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final r = _repo;
    if (r == null) return;
    final body = _text.text.trim();
    if (body.isEmpty) return;
    _text.clear();
    try {
      await r.sendMessage(
        conversationId: widget.conversationId,
        body: body,
      );
      if (mounted) _scrollToEnd(animated: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send: $e')),
      );
    }
  }

  List<_ThreadVisual> _buildThreadEntries() {
    final msgs = _messages;
    if (msgs.isEmpty) return const [];
    final out = <_ThreadVisual>[];
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final prevMsg = i > 0 ? msgs[i - 1] : null;
      final needsDate =
          prevMsg == null || !_sameLocalDay(prevMsg.createdAt, m.createdAt);
      if (needsDate) {
        final local = m.createdAt.toLocal();
        final day = DateTime(local.year, local.month, local.day);
        out.add(_ThreadDateVisual(_dateDividerLabel(day)));
      }
      final prev = i > 0 ? msgs[i - 1] : null;
      final next = i < msgs.length - 1 ? msgs[i + 1] : null;
      final sameAsPrev = prev != null &&
          prev.senderId == m.senderId &&
          _sameLocalDay(prev.createdAt, m.createdAt);
      final sameAsNext = next != null &&
          next.senderId == m.senderId &&
          _sameLocalDay(m.createdAt, next.createdAt);
      out.add(
        _ThreadMsgVisual(
          index: i,
          msg: m,
          sameAsPrev: sameAsPrev,
          sameAsNext: sameAsNext,
        ),
      );
    }
    return out;
  }

  bool _peerHasRepliedAfter(int myMessageIndex) {
    for (var j = myMessageIndex + 1; j < _messages.length; j++) {
      if (_messages[j].senderId != _senderMe) return true;
    }
    return false;
  }

  Future<void> _sendPreset(String preset) async {
    final r = _repo;
    if (r == null) return;
    final text = preset.trim();
    if (text.isEmpty) return;
    try {
      await r.sendMessage(
        conversationId: widget.conversationId,
        body: text,
      );
      if (mounted) _scrollToEnd(animated: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send: $e')),
      );
    }
  }

  void _showThreadToolsMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: const Icon(Icons.work_outline_rounded),
                  title: Text(
                    'View shift / job',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Opens when this chat is linked to a job.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AgapColors.textMuted,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Shift shortcuts will appear when a job is linked to this thread.',
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.phone_in_talk_outlined),
                  title: Text(
                    'Call',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Phone numbers are not shared in chat yet — use the contact options on the job.',
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.flag_outlined, color: Colors.orange.shade800),
                  title: Text(
                    'Report a concern',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Thanks — please also use Profile → Help if you need urgent support.',
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: Text(
                    'Help & safety',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'For emergencies, use your local emergency number. In-app help is coming soon.',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final accent =
        _isBusiness ? AgapColors.businessGreen : AgapColors.primaryBright;
    final accentDeep =
        _isBusiness ? AgapColors.businessGreenDeep : AgapColors.primary;
    final accentSoft =
        _isBusiness ? AgapColors.businessMint : AgapColors.mintSurface;
    final canSend = _text.text.trim().isNotEmpty;
    final initials = _initialsFromTitle(widget.title);
    final threadEntries = _buildThreadEntries();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellChromeBackground(
        kind: _isBusiness ? ShellChromeKind.business : ShellChromeKind.worker,
        child: Column(
          children: [
            _ThreadAppBar(
              title: widget.title,
              initials: initials,
              accent: accent,
              accentSoft: accentSoft,
              peerVerified: _peerVerified,
              onBack: () => Navigator.of(context).maybePop(),
              onMore: _showThreadToolsMenu,
            ),
            if (_error != null)
              Material(
                color: const Color(0xFFFFF1F2),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.inter(
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accentSoft.withValues(alpha: 0.42),
                          const Color(0xFFE9ECEF),
                          const Color(0xFFF2F4F6),
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: _ChatBackdropPainter(
                      accent: accent,
                      accentSoft: accentSoft,
                    ),
                    child: const SizedBox.expand(),
                  ),
                  if (_messages.isEmpty)
                    _EmptyThreadHint(accent: accent)
                  else
                    ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      itemCount: threadEntries.length,
                      itemBuilder: (context, i) {
                        final e = threadEntries[i];
                        if (e is _ThreadDateVisual) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 2),
                            child: _ChatDateChip(label: e.label),
                          );
                        }
                        if (e is _ThreadMsgVisual) {
                          final mine = e.msg.senderId == _senderMe;
                          final implicitRead =
                              mine && _peerHasRepliedAfter(e.index);
                          final gapTop = e.sameAsPrev ? 2.0 : 10.0;
                          return Padding(
                            padding: EdgeInsets.only(top: gapTop),
                            child: _MessageBubbleRow(
                              body: e.msg.body,
                              timeLabel: _formatBubbleTime(e.msg.createdAt),
                              mine: mine,
                              accent: accent,
                              accentDeep: accentDeep,
                              showTail: !e.sameAsNext,
                              deliveryRead: implicitRead,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                ],
              ),
            ),
            if (_messages.isNotEmpty)
              _QuickReplyStrip(
                accent: accent,
                onPick: _sendPreset,
              ),
            _ComposerBar(
              controller: _text,
              bottomInset: bottom,
              accent: accent,
              accentSoft: accentSoft,
              canSend: canSend,
              onSend: _send,
              onEmojiTap: () {
                _text.text = '${_text.text}😊';
                _text.selection =
                    TextSelection.collapsed(offset: _text.text.length);
                setState(() {});
              },
              onAttachTap: _showThreadToolsMenu,
            ),
          ],
        ),
      ),
    );
  }
}

sealed class _ThreadVisual {
  const _ThreadVisual._();
}

final class _ThreadDateVisual extends _ThreadVisual {
  const _ThreadDateVisual(this.label) : super._();
  final String label;
}

final class _ThreadMsgVisual extends _ThreadVisual {
  const _ThreadMsgVisual({
    required this.index,
    required this.msg,
    required this.sameAsPrev,
    required this.sameAsNext,
  }) : super._();

  final int index;
  final DmMessage msg;
  final bool sameAsPrev;
  final bool sameAsNext;
}

class _ChatBackdropPainter extends CustomPainter {
  _ChatBackdropPainter({required this.accent, required this.accentSoft});

  final Color accent;
  final Color accentSoft;

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = accentSoft.withValues(alpha: 0.14);
    final brand = Paint()..color = accent.withValues(alpha: 0.04);
    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.06),
      size.width * 0.42,
      brand,
    );
    canvas.drawCircle(
      Offset(size.width * -0.05, size.height * 0.42),
      size.width * 0.48,
      soft,
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.94),
      size.width * 0.36,
      brand,
    );
  }

  @override
  bool shouldRepaint(covariant _ChatBackdropPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.accentSoft != accentSoft;
}

class _ChatDateChip extends StatelessWidget {
  const _ChatDateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AgapColors.textMuted.withValues(alpha: 0.95),
            letterSpacing: 0.25,
          ),
        ),
      ),
    );
  }
}

class _QuickReplyStrip extends StatelessWidget {
  const _QuickReplyStrip({
    required this.accent,
    required this.onPick,
  });

  final Color accent;
  final Future<void> Function(String) onPick;

  static const _presets = <String>[
    'On my way',
    'I have arrived',
    'Thank you!',
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final q in _presets) ...[
                ActionChip(
                  label: Text(
                    q,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: accent.withValues(alpha: 0.1),
                  side: BorderSide(color: accent.withValues(alpha: 0.2)),
                  onPressed: () => onPick(q),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadAppBar extends StatelessWidget {
  const _ThreadAppBar({
    required this.title,
    required this.initials,
    required this.accent,
    required this.accentSoft,
    required this.peerVerified,
    required this.onBack,
    required this.onMore,
  });

  final String title;
  final String initials;
  final Color accent;
  final Color accentSoft;
  final bool peerVerified;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(
              color: Colors.black.withValues(alpha: 0.06),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  color: const Color(0xFF374151),
                  onPressed: onBack,
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent, Color.lerp(accent, accentSoft, 0.4)!],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
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
                        fontSize: 14,
                        color: accent,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                height: 1.2,
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
                      const SizedBox(height: 2),
                      Text(
                        peerVerified
                            ? 'Verified on AgapShift • Direct message'
                            : 'Direct message',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                IconButton(
                  tooltip: 'Chat tools',
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: AgapColors.textMuted.withValues(alpha: 0.9),
                  ),
                  onPressed: onMore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubbleRow extends StatelessWidget {
  const _MessageBubbleRow({
    required this.body,
    required this.timeLabel,
    required this.mine,
    required this.accent,
    required this.accentDeep,
    required this.showTail,
    required this.deliveryRead,
  });

  final String body;
  final String timeLabel;
  final bool mine;
  final Color accent;
  final Color accentDeep;
  final bool showTail;
  final bool deliveryRead;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.82;
    const r = 20.0;
    const tailR = 5.0;

    final borderRadius = mine
        ? BorderRadius.only(
            topLeft: const Radius.circular(r),
            topRight: const Radius.circular(r),
            bottomLeft: const Radius.circular(r),
            bottomRight: Radius.circular(showTail ? tailR : r),
          )
        : BorderRadius.only(
            topLeft: const Radius.circular(r),
            topRight: const Radius.circular(r),
            bottomRight: const Radius.circular(r),
            bottomLeft: Radius.circular(showTail ? tailR : r),
          );

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      decoration: BoxDecoration(
        gradient: mine
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(accent, Colors.white, 0.16)!,
                  Color.lerp(accent, accentDeep, 0.28)!,
                ],
              )
            : null,
        color: mine ? null : const Color(0xFFF7F6F3),
        borderRadius: borderRadius,
        border: mine
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 0.6,
              )
            : Border.all(color: const Color(0xFFE4E1DA)),
        boxShadow: [
          BoxShadow(
            color: mine
                ? accentDeep.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: mine ? 16 : 11,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Text(
        body,
        style: GoogleFonts.inter(
          fontSize: 15,
          height: 1.38,
          fontWeight: FontWeight.w600,
          color: mine ? Colors.white : const Color(0xFF1F2937),
        ),
      ),
    );

    final timeStyle = GoogleFonts.inter(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: mine
          ? Colors.white.withValues(alpha: 0.48)
          : AgapColors.textMuted.withValues(alpha: 0.55),
    );

    final meta = Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(timeLabel, style: timeStyle),
          if (mine) ...[
            const SizedBox(width: 5),
            Icon(
              deliveryRead ? Icons.done_all_rounded : Icons.done_rounded,
              size: 13,
              color: Colors.white.withValues(alpha: deliveryRead ? 0.88 : 0.45),
            ),
          ],
        ],
      ),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          bubble,
          meta,
        ],
      ),
    );
  }
}

class _EmptyThreadHint extends StatelessWidget {
  const _EmptyThreadHint({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.waving_hand_rounded,
                size: 36,
                color: accent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Start the conversation',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to say hello — replies appear here in real time.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: AgapColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.bottomInset,
    required this.accent,
    required this.accentSoft,
    required this.canSend,
    required this.onSend,
    required this.onEmojiTap,
    required this.onAttachTap,
  });

  final TextEditingController controller;
  final double bottomInset;
  final Color accent;
  final Color accentSoft;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onEmojiTap;
  final VoidCallback onAttachTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.07)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomInset),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
                boxShadow: [
                  BoxShadow(
                    color: accentSoft.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Attach & tools',
                    visualDensity: VisualDensity.compact,
                    onPressed: onAttachTap,
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      color: accent.withValues(alpha: 0.88),
                      size: 26,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(4000),
                      ],
                      decoration: InputDecoration(
                        hintText: 'Message…',
                        hintStyle: GoogleFonts.inter(
                          color: AgapColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 12,
                        ),
                      ),
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        height: 1.35,
                        color: const Color(0xFF111827),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Emoji',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEmojiTap,
                    icon: Icon(
                      Icons.mood_outlined,
                      color: AgapColors.textMuted.withValues(alpha: 0.95),
                      size: 24,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4, bottom: 4),
                    child: Material(
                      color: canSend ? accent : accent.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(20),
                      elevation: canSend ? 2 : 0,
                      shadowColor: accent.withValues(alpha: 0.35),
                      child: InkWell(
                        onTap: canSend ? onSend : null,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: Icon(
                            Icons.send_rounded,
                            color: Colors.white
                                .withValues(alpha: canSend ? 1 : 0.72),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

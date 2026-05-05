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

class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final String conversationId;
  final String title;

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
      _listen();
    });
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

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send: $e')),
      );
    }
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
              onBack: () => Navigator.of(context).maybePop(),
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      accentSoft.withValues(alpha: 0.45),
                      const Color(0xFFF4F6F8),
                      const Color(0xFFF4F6F8),
                    ],
                    stops: const [0.0, 0.35, 1.0],
                  ),
                ),
                child: _messages.isEmpty
                    ? _EmptyThreadHint(accent: accent)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final mine = m.senderId == _senderMe;
                          final prev = i > 0 ? _messages[i - 1] : null;
                          final next =
                              i < _messages.length - 1 ? _messages[i + 1] : null;
                          final sameAsPrev = prev?.senderId == m.senderId;
                          final sameAsNext = next?.senderId == m.senderId;
                          final gapTop = sameAsPrev ? 4.0 : 14.0;
                          final showTail = !sameAsNext;

                          return Padding(
                            padding: EdgeInsets.only(top: gapTop),
                            child: _MessageBubbleRow(
                              body: m.body,
                              timeLabel: _formatBubbleTime(m.createdAt),
                              mine: mine,
                              accent: accent,
                              accentDeep: accentDeep,
                              showTail: showTail,
                            ),
                          );
                        },
                      ),
              ),
            ),
            _ComposerBar(
              controller: _text,
              bottomInset: bottom,
              accent: accent,
              canSend: canSend,
              onSend: _send,
            ),
          ],
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
    required this.onBack,
  });

  final String title;
  final String initials;
  final Color accent;
  final Color accentSoft;
  final VoidCallback onBack;

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
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
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
                      Text(
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
                      const SizedBox(height: 2),
                      Text(
                        'Direct message',
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
  });

  final String body;
  final String timeLabel;
  final bool mine;
  final Color accent;
  final Color accentDeep;
  final bool showTail;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.82;
    final r = 18.0;
    final tailR = 5.0;

    final borderRadius = mine
        ? BorderRadius.only(
            topLeft: Radius.circular(r),
            topRight: Radius.circular(r),
            bottomLeft: Radius.circular(r),
            bottomRight: Radius.circular(showTail ? tailR : r),
          )
        : BorderRadius.only(
            topLeft: Radius.circular(r),
            topRight: Radius.circular(r),
            bottomRight: Radius.circular(r),
            bottomLeft: Radius.circular(showTail ? tailR : r),
          );

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      decoration: BoxDecoration(
        color: mine ? accent : Colors.white,
        borderRadius: borderRadius,
        border: mine
            ? null
            : Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: mine
                ? accentDeep.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.07),
            blurRadius: mine ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            body,
            style: GoogleFonts.inter(
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: mine ? Colors.white : const Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timeLabel,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: mine
                  ? Colors.white.withValues(alpha: 0.82)
                  : AgapColors.textMuted,
            ),
          ),
        ],
      ),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
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
    required this.canSend,
    required this.onSend,
  });

  final TextEditingController controller;
  final double bottomInset;
  final Color accent;
  final bool canSend;
  final VoidCallback onSend;

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
            padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + bottomInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
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
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: accent.withValues(alpha: 0.55),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
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
                const SizedBox(width: 10),
                Material(
                  color: canSend ? accent : accent.withValues(alpha: 0.35),
                  shape: const CircleBorder(),
                  elevation: canSend ? 3 : 0,
                  shadowColor: accent.withValues(alpha: 0.45),
                  child: InkWell(
                    onTap: canSend ? onSend : null,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.send_rounded,
                        color: Colors.white.withValues(alpha: canSend ? 1 : 0.75),
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

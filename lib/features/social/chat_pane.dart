import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import 'models/message.dart';
import 'models/pvp_match.dart';
import 'services/message_notifier.dart';
import 'services/messages_service.dart';
import 'social_actions.dart';
import 'social_controller.dart';
import 'widgets/social_kit.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';

/// The right half of the Messenger layout: one friend's conversation, with
/// Visit and Challenge in its header. A friend's open PvP business (a
/// challenge waiting for you, a match running) sits at the end of the thread
/// as a card, because the two happen together — people write first.
///
/// Loads the history on open, then stays live through the controller's message
/// stream; a message that arrived while the socket was down still shows up the
/// next time the chat is opened, because the load reads it.
class ChatPane extends StatefulWidget {
  final SocialController ctrl;
  final SocialFriend friend;

  const ChatPane({super.key, required this.ctrl, required this.friend});

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final _svc = MessagesService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  StreamSubscription<ChatMessage>? _sub;

  List<ChatMessage> _messages = [];
  bool _loading = true;

  SocialController get _ctrl => widget.ctrl;
  String get _friendId => widget.friend.userId;

  @override
  void initState() {
    super.initState();
    MessageNotifier.instance.openChatWith = _friendId;
    _load();
    _sub = _ctrl.messages.listen(_onMessage);
  }

  @override
  void dispose() {
    if (MessageNotifier.instance.openChatWith == _friendId) {
      MessageNotifier.instance.openChatWith = null;
    }
    _sub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool spinner = true}) async {
    if (spinner) setState(() => _loading = true);
    try {
      final msgs = await _svc.loadThread(_friendId);
      await _svc.markThreadRead(_friendId);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      _ctrl.refreshThreads();
      MessageNotifier.instance.refreshUnread();
      _scrollToEnd();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onMessage(ChatMessage msg) {
    final mine =
        (msg.senderId == _ctrl.myId && msg.recipientId == _friendId) ||
        (msg.senderId == _friendId && msg.recipientId == _ctrl.myId);
    if (!mine || !mounted) return;
    if (_messages.any((m) => m.id == msg.id)) return;
    setState(() => _messages = [..._messages, msg]);
    if (msg.recipientId == _ctrl.myId) {
      _svc.markThreadRead(_friendId).then((_) {
        _ctrl.refreshThreads();
        MessageNotifier.instance.refreshUnread();
      });
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty) return;
    _inputCtrl.clear();
    await _svc.sendMessage(_friendId, text);
    // The live stream normally delivers it; this covers a socket that is down.
    await _load(spinner: false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ctrl,
    builder: (context, _) => Column(
      children: [
        _header(),
        Container(height: 1, color: CreamPalette.tan.withValues(alpha: 0.55)),
        Expanded(child: _thread()),
        _composer(),
      ],
    ),
  );

  Widget _header() {
    final stats = _ctrl.stats[_friendId];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          SocialAvatar(widget.friend.name, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.friend.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(
                    size: 14,
                  ).copyWith(color: kBoxInk, fontWeight: FontWeight.w800),
                ),
                if (stats != null)
                  Text(
                    'Rating ${recordLine(stats.rating, stats.wins, stats.losses)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                  ),
              ],
            ),
          ),
          SocialTileButton(
            'Visit',
            icon: Icons.home_outlined,
            onTap: () => visitCity(context, _ctrl, widget.friend),
          ),
          const SizedBox(width: 8),
          SocialTileButton(
            'Challenge',
            icon: Icons.sports_martial_arts,
            onTap: () => challengeFriend(context, _ctrl, widget.friend),
          ),
        ],
      ),
    );
  }

  Widget _thread() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: CreamPalette.gold),
      );
    }
    final cards = _matchCards();
    final children = <Widget>[];
    DateTime? day;
    for (final m in _messages) {
      final d = _dayOf(m.createdAt);
      if (day != d) {
        day = d;
        children.add(_daySeparator(d));
      }
      children.add(_bubble(m));
    }
    if (children.isEmpty && cards.isEmpty) {
      return Center(
        child: Text(
          'No messages yet — say hello to ${widget.friend.name}.',
          textAlign: TextAlign.center,
          style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
        ),
      );
    }
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      children: [...children, ...cards],
    );
  }

  /// The friend's PvP business, as cards at the end of the thread.
  List<Widget> _matchCards() {
    final incoming = _ctrl.incoming.where((m) => m.playerA == _friendId);
    final matches = [
      ..._ctrl.open,
      ..._ctrl.sent,
    ].where((m) => m.otherUserId(_ctrl.myId) == _friendId);
    return [
      for (final m in incoming)
        _matchCard(
          '${widget.friend.name} challenged you',
          actions: [
            SocialGoldButton(
              'Accept',
              height: 28,
              fontSize: 11.5,
              onTap: () => acceptChallenge(context, _ctrl, m),
            ),
            const SizedBox(width: 8),
            SocialTileButton(
              'Decline',
              height: 28,
              fontSize: 11.5,
              onTap: () => _ctrl.declineChallenge(m),
            ),
          ],
        ),
      // Every match with this friend that is under way — a challenge they have
      // not accepted, an accepted lobby, a fight — with where THEY are, a way in
      // at any time, and the way out for good.
      for (final m in matches) _matchOpenCard(m),
    ];
  }

  Widget _matchOpenCard(PvpMatch m) {
    final stage = m.opponentStage(_ctrl.myId);
    final active = m.status == PvpMatchStatus.active;
    final pending = m.status == PvpMatchStatus.pending;
    return _matchCard(
      'vs ${widget.friend.name}',
      chip: StageChip(stage),
      actions: [
        SocialGoldButton(
          active
              ? 'Resume'
              : pending
              ? 'Enter lobby'
              : 'Enter',
          height: 28,
          fontSize: 11.5,
          onTap: () => openMatch(context, _ctrl, m),
        ),
        if (!active) ...[
          const SizedBox(width: 8),
          SocialTileButton(
            pending ? 'Withdraw' : 'Leave',
            height: 28,
            fontSize: 11.5,
            onTap: () async {
              if (await leaveMatchFlow(context, m, widget.friend.name)) {
                await _ctrl.refreshPvp();
              }
            },
          ),
        ],
      ],
    );
  }

  Widget _matchCard(
    String text, {
    Widget? chip,
    required List<Widget> actions,
  }) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: BoxDecoration(
        borderRadius: vr(12),
        color: CreamPalette.gold.withValues(alpha: 0.34),
        border: Border.all(color: CreamPalette.goldDeep),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PixelIcon(
            Icons.sports_martial_arts,
            size: 16,
            color: CreamPalette.accent,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: FoE.label(
              size: 12,
            ).copyWith(color: kBoxInk, fontWeight: FontWeight.w800),
          ),
          if (chip != null) ...[const SizedBox(width: 8), chip],
          const SizedBox(width: 12),
          ...actions,
        ],
      ),
    ),
  );

  Widget _daySeparator(DateTime day) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: CreamPalette.tan.withValues(alpha: 0.18),
          borderRadius: vr(8),
        ),
        child: Text(
          _dayLabel(day),
          style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
        ),
      ),
    ),
  );

  Widget _bubble(ChatMessage m) {
    final mine = m.sentByMe(_ctrl.myId);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 5),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          color: mine ? CreamPalette.gold : null,
          gradient: mine
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [CreamPalette.tileTop, CreamPalette.tileBottom],
                ),
          boxShadow: [
            BoxShadow(
              color: mine ? CreamPalette.goldDeep : CreamPalette.tanShadow,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                m.body,
                style: FoE.label(size: 12.5).copyWith(color: kBoxInk),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              _hhmm(m.createdAt),
              style: FoE.dim(size: 9.5).copyWith(color: kBoxInkFaint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
    child: Row(
      children: [
        Expanded(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: CreamPalette.tan.withValues(alpha: 0.18),
              borderRadius: vr(12),
            ),
            child: TextField(
              controller: _inputCtrl,
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
              style: FoE.label(size: 12.5).copyWith(color: kBoxInk),
              cursorColor: CreamPalette.accent,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: 'Message…',
                hintStyle: FoE.label(size: 12.5).copyWith(color: kBoxInkFaint),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SocialGoldButton(
          'Send',
          height: 36,
          fontSize: 12.5,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          onTap: _send,
        ),
      ],
    ),
  );

  // ── Time ────────────────────────────────────────────────────────────────

  static DateTime _dayOf(DateTime t) {
    final l = t.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  static String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  static const _months = [
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

  static String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${day.day} ${_months[day.month - 1]}';
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import 'chat_pane.dart';
import 'friends_pane.dart';
import 'pvp_pane.dart';
import 'ranking_pane.dart';
import 'services/message_notifier.dart';
import 'social_controller.dart';
import 'widgets/social_kit.dart';

/// What the right-hand card is showing.
enum _Pane { chat, friends, pvp, ranking }

/// The Social hub, laid out like a messenger (user 2026-09-19, picked from ten
/// layouts): on the left your friends as conversations — last line, time and
/// an unread count — with a switch above them for Chats / PvP / Ranking and a
/// button for the friend list itself; on the right the open chat, whose header
/// carries Visit and Challenge. A challenge from the friend you are talking to
/// shows up in the chat as a card, because people write before they fight.
///
/// The friend button (badge = requests waiting) opens [FriendsPane] on the
/// right: search, requests, and every verb for every friend.
class SocialScreen extends StatefulWidget {
  /// Only tests pass one; the screen otherwise owns its own.
  @visibleForTesting
  final SocialController? controller;

  /// Opens on the PvP list — where a "challenged you" banner takes you.
  final bool startOnPvp;

  /// Opens the chat with this friend — where a message banner takes you.
  final String? startChatWith;

  const SocialScreen({
    super.key,
    this.controller,
    this.startOnPvp = false,
    this.startChatWith,
  });

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  late final SocialController _ctrl = widget.controller ?? SocialController();

  late _Pane _pane = widget.startOnPvp ? _Pane.pvp : _Pane.chat;
  late String? _selectedId = widget.startChatWith;

  @override
  void initState() {
    super.initState();
    // While Social is open the banner for new messages stays quiet — the list
    // and the chat show them.
    MessageNotifier.instance.socialOpen = true;
    _ctrl.load();
  }

  @override
  void dispose() {
    MessageNotifier.instance.socialOpen = false;
    MessageNotifier.instance.refreshUnread();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  void _openChat(SocialFriend f) => setState(() {
    _selectedId = f.userId;
    _pane = _Pane.chat;
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ctrl,
    builder: (context, _) => MenuScaffold(
      title: 'Social',
      trailing: _readout(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 320, child: creamCard(child: _left())),
            const SizedBox(width: 10),
            Expanded(child: creamCard(child: _right())),
          ],
        ),
      ),
    ),
  );

  /// "2 unread · 1 challenge" — what is waiting, or how many friends there are
  /// when nothing is.
  Widget _readout() {
    final parts = <String>[
      if (_ctrl.unreadTotal > 0) '${_ctrl.unreadTotal} unread',
      if (_ctrl.incoming.isNotEmpty)
        '${_ctrl.incoming.length} challenge${_ctrl.incoming.length == 1 ? '' : 's'}',
      if (_ctrl.incomingRequests.isNotEmpty)
        '${_ctrl.incomingRequests.length} request${_ctrl.incomingRequests.length == 1 ? '' : 's'}',
    ];
    final text = parts.isEmpty
        ? '${_ctrl.friends.length} friend${_ctrl.friends.length == 1 ? '' : 's'}'
        : parts.join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: CreamPalette.tan.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(text, style: FoE.value(size: 11).copyWith(color: kBoxInk)),
    );
  }

  // ── Left: the switch and the conversations ──────────────────────────────

  Widget _left() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Scales down rather than overflowing if a font runs wide.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(fit: BoxFit.scaleDown, child: _seg()),
              ),
            ),
            const SizedBox(width: 8),
            SocialGlyphButton(
              Icons.people_alt_outlined,
              gold: _pane == _Pane.friends,
              badge: _ctrl.incomingRequests.length,
              tooltip: 'Friends',
              onTap: () => setState(() => _pane = _Pane.friends),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: _list()),
      ],
    ),
  );

  Widget _seg() => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _segItem('Chats', _Pane.chat),
        _segItem('PvP', _Pane.pvp, badge: _ctrl.pvpAttention),
        _segItem('Ranking', _Pane.ranking),
      ],
    ),
  );

  Widget _segItem(String label, _Pane pane, {int badge = 0}) {
    // The friend list is a fourth thing that shares the right card; Chats stays
    // lit while it is open only if nothing else claims it.
    final on = _pane == pane;
    return Pressable(
      onTap: () => setState(() => _pane = pane),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: on
            ? BoxDecoration(
                color: CreamPalette.gold,
                borderRadius: BorderRadius.circular(9),
                boxShadow: const [
                  BoxShadow(color: CreamPalette.goldDeep, offset: Offset(0, 2)),
                ],
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: on ? kBoxInk : kBoxInkSoft,
              ),
            ),
            if (badge > 0) ...[const SizedBox(width: 6), CountBadge(badge)],
          ],
        ),
      ),
    );
  }

  Widget _list() {
    if (_ctrl.loading && _ctrl.friendships.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: CreamPalette.gold),
      );
    }
    if (_ctrl.error != null && _ctrl.friendships.isEmpty) {
      return Center(
        child: Text(
          'Could not load Social.\n${_ctrl.error}',
          textAlign: TextAlign.center,
          style: FoE.label(size: 12).copyWith(color: kBoxInkSoft),
        ),
      );
    }
    final friends = _ctrl.friends;
    if (friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No friends yet.\nTap the friends button to search for one.',
            textAlign: TextAlign.center,
            style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
          ),
        ),
      );
    }
    final selected = _selected(friends)?.userId;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 14, top: 2),
      itemCount: friends.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _threadRow(
        friends[i],
        on: _pane == _Pane.chat && friends[i].userId == selected,
      ),
    );
  }

  /// The friend whose chat is open: the one picked, else the first — which,
  /// with threads sorted newest first, is whoever wrote last. The pick sticks,
  /// so a new message from someone else re-sorting the list does not swap the
  /// chat out from under you.
  SocialFriend? _selected(List<SocialFriend> friends) {
    if (friends.isEmpty) return null;
    final f = friends.firstWhere(
      (f) => f.userId == _selectedId,
      orElse: () => friends.first,
    );
    _selectedId = f.userId;
    return f;
  }

  Widget _threadRow(SocialFriend f, {required bool on}) {
    final t = _ctrl.threads[f.userId];
    return socialRow(
      lit: on,
      height: 52,
      onTap: () => _openChat(f),
      child: Row(
        children: [
          SocialAvatar(f.name, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.label(
                          size: 13,
                        ).copyWith(color: kBoxInk, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (t != null)
                      Text(
                        _when(t.lastMessage.createdAt),
                        style: FoE.dim(size: 9.5).copyWith(color: kBoxInkFaint),
                      ),
                  ],
                ),
                Text(
                  t?.lastMessage.body ?? 'No messages yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(
                    size: 11,
                  ).copyWith(color: t == null ? kBoxInkFaint : kBoxInkSoft),
                ),
              ],
            ),
          ),
          if (t != null && t.unreadCount > 0) ...[
            const SizedBox(width: 8),
            CountBadge(t.unreadCount),
          ],
        ],
      ),
    );
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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

  /// 14:02 today, a weekday within the last week, else "3 Sep".
  static String _when(DateTime t) {
    final l = t.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(l.year, l.month, l.day)).inDays;
    if (days == 0) {
      return '${l.hour.toString().padLeft(2, '0')}:'
          '${l.minute.toString().padLeft(2, '0')}';
    }
    if (days == 1) return 'Yesterday';
    if (days < 7) return _weekdays[l.weekday - 1];
    return '${l.day} ${_months[l.month - 1]}';
  }

  // ── Right: chat, friends, PvP or ranking ────────────────────────────────

  Widget _right() {
    final friends = _ctrl.friends;
    // Without a single friend there is no chat to show — the friend list is
    // the only useful thing, so it opens by itself.
    final pane = _pane == _Pane.chat && friends.isEmpty ? _Pane.friends : _pane;
    switch (pane) {
      case _Pane.chat:
        final f = _selected(friends)!;
        return ChatPane(key: ValueKey(f.userId), ctrl: _ctrl, friend: f);
      case _Pane.friends:
        return FriendsPane(ctrl: _ctrl, onOpenChat: _openChat);
      case _Pane.pvp:
        return PvpPane(ctrl: _ctrl);
      case _Pane.ranking:
        return RankingPane(ctrl: _ctrl);
    }
  }
}

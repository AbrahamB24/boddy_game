import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import 'models/friend.dart';
import 'social_actions.dart';
import 'social_controller.dart';
import 'widgets/social_kit.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';

/// Where friends are made and unmade: search a username and add, answer the
/// requests you received, and the full friend list with every verb (chat,
/// visit, challenge, remove). Opened from the friend button above the chat
/// list; the chat list itself is the everyday way to reach a friend.
class FriendsPane extends StatefulWidget {
  final SocialController ctrl;

  /// Jumps to a friend's chat.
  final ValueChanged<SocialFriend> onOpenChat;

  const FriendsPane({super.key, required this.ctrl, required this.onOpenChat});

  @override
  State<FriendsPane> createState() => _FriendsPaneState();
}

class _FriendsPaneState extends State<FriendsPane> {
  final _searchCtrl = TextEditingController();
  List<FriendSearchResult> _results = [];
  bool _searching = false;

  SocialController get _ctrl => widget.ctrl;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await _ctrl.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(String userId) async {
    await _ctrl.sendRequest(userId);
    await _search(_searchCtrl.text);
  }

  Future<void> _remove(SocialFriend f) async {
    if (await confirmRemoveFriend(context, f.name) && mounted) {
      await _ctrl.remove(f.friendship);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ctrl,
    builder: (context, _) {
      final incoming = _ctrl.incomingRequests;
      final outgoing = _ctrl.outgoingRequests;
      final friends = _ctrl.friends;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        children: [
          _searchBox(),
          if (_searchCtrl.text.trim().length >= 2) ...[
            const SizedBox(height: 10),
            if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: CircularProgressIndicator(color: CreamPalette.gold),
                ),
              )
            else if (_results.isEmpty)
              socialHint('No player found with that name.')
            else
              for (final r in _results) _resultRow(r),
          ],
          if (incoming.isNotEmpty) ...[
            const SizedBox(height: 14),
            socialSection('Friend requests · ${incoming.length}'),
            for (final f in incoming) _incomingRow(f),
          ],
          const SizedBox(height: 14),
          socialSection('Friends · ${friends.length}'),
          if (friends.isEmpty && outgoing.isEmpty)
            socialHint('No friends yet — search for a username above.'),
          for (final f in friends) _friendRow(f),
          for (final f in outgoing) _outgoingRow(f),
        ],
      );
    },
  );

  Widget _searchBox() => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: vr(12),
    ),
    child: Row(
      children: [
        PixelIcon(Icons.search, size: 16, color: kBoxInkFaint),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            onChanged: _search,
            style: FoE.label(size: 12.5).copyWith(color: kBoxInk),
            cursorColor: CreamPalette.accent,
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              hintText: 'Search by username',
              hintStyle: FoE.label(size: 12.5).copyWith(color: kBoxInkFaint),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _rowGap(Widget row) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: row);

  Widget _name(String name, [String? sub]) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FoE.label(
            size: 13,
          ).copyWith(color: kBoxInk, fontWeight: FontWeight.w800),
        ),
        if (sub != null)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
          ),
      ],
    ),
  );

  Widget _tag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: vr(8),
      border: Border.all(color: CreamPalette.tan.withValues(alpha: 0.55)),
    ),
    child: Text(text, style: FoE.dim(size: 10).copyWith(color: kBoxInkFaint)),
  );

  Widget _resultRow(FriendSearchResult r) {
    final f = r.friendship;
    final Widget action;
    if (f == null) {
      action = SocialTileButton(
        'Add',
        icon: Icons.person_add_alt,
        height: 28,
        onTap: () => _add(r.userId),
      );
    } else if (f.status == FriendshipStatus.accepted) {
      action = _tag('Friends');
    } else if (f.awaitingMyResponse(_ctrl.myId)) {
      action = _tag('Respond below');
    } else if (f.sentByMe(_ctrl.myId)) {
      action = _tag('Pending');
    } else {
      action = _tag(f.status.name);
    }
    return _rowGap(
      socialRow(
        child: Row(
          children: [
            SocialAvatar(r.username, size: 30),
            const SizedBox(width: 10),
            _name(r.username),
            action,
          ],
        ),
      ),
    );
  }

  Widget _incomingRow(Friendship f) {
    final name = _ctrl.nameOf(f.otherUserId(_ctrl.myId));
    return _rowGap(
      socialRow(
        warm: true,
        child: Row(
          children: [
            SocialAvatar(name, size: 30),
            const SizedBox(width: 10),
            _name(name, 'wants to be your friend'),
            SocialGoldButton(
              'Accept',
              height: 28,
              onTap: () => _ctrl.accept(f),
            ),
            const SizedBox(width: 8),
            SocialGlyphButton(
              Icons.close,
              size: 28,
              tooltip: 'Decline',
              onTap: () => _ctrl.decline(f),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outgoingRow(Friendship f) {
    final name = _ctrl.nameOf(f.otherUserId(_ctrl.myId));
    return Opacity(
      opacity: 0.75,
      child: _rowGap(
        socialRow(
          child: Row(
            children: [
              SocialAvatar(name, size: 30),
              const SizedBox(width: 10),
              _name(name, 'Request sent'),
              _tag('Pending'),
              const SizedBox(width: 8),
              SocialGlyphButton(
                Icons.close,
                size: 28,
                tooltip: 'Cancel request',
                onTap: () => _ctrl.remove(f),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _friendRow(SocialFriend f) {
    final stats = _ctrl.stats[f.userId];
    final unread = _ctrl.threads[f.userId]?.unreadCount ?? 0;
    return _rowGap(
      socialRow(
        onTap: () => widget.onOpenChat(f),
        child: Row(
          children: [
            SocialAvatar(f.name, size: 30),
            const SizedBox(width: 10),
            _name(
              f.name,
              stats == null
                  ? null
                  : recordLine(stats.rating, stats.wins, stats.losses),
            ),
            SocialGlyphButton(
              Icons.chat_bubble_outline,
              size: 28,
              badge: unread,
              tooltip: 'Chat',
              onTap: () => widget.onOpenChat(f),
            ),
            const SizedBox(width: 8),
            SocialGlyphButton(
              Icons.home_outlined,
              size: 28,
              tooltip: 'Visit city',
              onTap: () async {
                if (await visitCity(context, _ctrl, f)) widget.onOpenChat(f);
              },
            ),
            const SizedBox(width: 8),
            SocialGlyphButton(
              Icons.sports_martial_arts,
              size: 28,
              tooltip: 'Challenge',
              onTap: () => challengeFriend(context, _ctrl, f),
            ),
            const SizedBox(width: 8),
            SocialGlyphButton(
              Icons.close,
              size: 28,
              tooltip: 'Remove friend',
              onTap: () => _remove(f),
            ),
          ],
        ),
      ),
    );
  }
}

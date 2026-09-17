import 'package:flutter/material.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../settlement/widgets/parchment_sheet.dart';
import 'message_thread_screen.dart';
import 'models/friend.dart';
import 'models/message.dart';
import 'services/friends_service.dart';
import 'services/messages_service.dart';

/// The Messages tab of [SocialScreen]: one row per friend you've messaged
/// (latest line + unread count), plus a way to start a thread with any
/// accepted friend who has none yet.
class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final _messagesSvc = MessagesService();
  final _friendsSvc = FriendsService();

  String get _myId => supabase.auth.currentUser!.id;

  bool _loading = true;
  List<MessageThreadSummary> _threads = [];
  List<Friendship> _friendsWithoutThread = [];
  Map<String, String?> _names = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final recent = await _messagesSvc.listRecentMessages();
    final friendships = await _friendsSvc.listFriendships();
    final accepted = friendships
        .where((f) => f.status == FriendshipStatus.accepted)
        .toList();

    final byOther = <String, List<ChatMessage>>{};
    for (final m in recent) {
      final other = m.senderId == _myId ? m.recipientId : m.senderId;
      (byOther[other] ??= []).add(m);
    }
    final otherIds = byOther.keys.toList();
    final names = await _friendsSvc.usernamesFor([
      ...otherIds,
      ...accepted.map((f) => f.otherUserId(_myId)),
    ]);

    final threads = <MessageThreadSummary>[];
    for (final entry in byOther.entries) {
      final msgs = entry.value..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final unread = msgs
          .where((m) => m.recipientId == _myId && m.readAt == null)
          .length;
      threads.add(
        MessageThreadSummary(
          otherUserId: entry.key,
          otherUsername: names[entry.key] ?? '(unknown)',
          lastMessage: msgs.first,
          unreadCount: unread,
        ),
      );
    }
    threads.sort((a, b) => b.lastMessage.createdAt.compareTo(a.lastMessage.createdAt));

    final withoutThread = accepted
        .where((f) => !byOther.containsKey(f.otherUserId(_myId)))
        .toList();

    if (!mounted) return;
    setState(() {
      _threads = threads;
      _friendsWithoutThread = withoutThread;
      _names = names;
      _loading = false;
    });
  }

  Future<void> _open(String otherUserId, String otherUsername) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageThreadScreen(
          otherUserId: otherUserId,
          otherUsername: otherUsername,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_threads.isEmpty && _friendsWithoutThread.isEmpty) {
      return Center(
        child: Text(
          'No messages yet. Add a friend to start chatting.',
          textAlign: TextAlign.center,
          style: FoE.dim(size: 12).copyWith(color: ParchmentSheet.inkFaint),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        for (final t in _threads) _threadRow(t),
        if (_friendsWithoutThread.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(
              'Start a conversation',
              style: FoE.label(size: 12).copyWith(
                color: ParchmentSheet.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final f in _friendsWithoutThread) _newThreadRow(f),
        ],
      ],
    );
  }

  Widget _threadRow(MessageThreadSummary t) => Pressable(
    onTap: () => _open(t.otherUserId, t.otherUsername),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: ParchmentSheet.card,
      child: Row(
        children: [
          Icon(Icons.person_outline, color: ParchmentSheet.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.otherUsername,
                  style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink),
                ),
                Text(
                  t.lastMessage.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(size: 11).copyWith(color: ParchmentSheet.inkFaint),
                ),
              ],
            ),
          ),
          if (t.unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: ShapeDecoration(
                color: FoE.danger,
                shape: FoE.facet(radius: 9),
              ),
              child: Text(
                '${t.unreadCount}',
                style: FoE.dim(size: 10).copyWith(color: Colors.white),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _newThreadRow(Friendship f) {
    final otherId = f.otherUserId(_myId);
    final name = _names[otherId] ?? '(unknown)';
    return Pressable(
      onTap: () => _open(otherId, name),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: ParchmentSheet.card,
        child: Row(
          children: [
            Icon(Icons.chat_bubble_outline, color: ParchmentSheet.inkFaint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import 'models/activity.dart';
import 'models/friend.dart';
import 'models/message.dart';
import 'models/pvp_match.dart';
import 'services/activity_service.dart';
import 'services/friends_service.dart';
import 'services/messages_service.dart';
import 'services/pvp_notifier.dart';
import 'services/pvp_service.dart';

/// One accepted friend, with the friendship row that makes them one.
class SocialFriend {
  final String userId;
  final String name;
  final Friendship friendship;

  const SocialFriend({
    required this.userId,
    required this.name,
    required this.friendship,
  });
}

/// Everything the Social screen shows, loaded once and shared by its panes
/// (Messenger layout, user 2026-09-19): the friend list with its threads, the
/// requests, the PvP challenges and matches, the ratings and the feed.
///
/// The old tabs each loaded their own slice, which was fine while they were
/// four separate drawers. Now the list on the left needs the threads AND the
/// ratings, the seg's badges need the challenge count, and the friend button's
/// badge needs the requests — so one object owns it and the panes ask it.
class SocialController extends ChangeNotifier {
  final _friendsSvc = FriendsService();
  final _messagesSvc = MessagesService();
  final _pvpSvc = PvpService();
  final _activitySvc = ActivityService();

  String get myId => supabase.auth.currentUser!.id;

  bool loading = true;
  String? error;

  List<Friendship> friendships = [];
  Map<String, String?> names = {};
  Map<String, MessageThreadSummary> threads = {};
  Map<String, PvpStats> stats = {};
  List<PvpStats> leaderboard = [];
  List<FriendActivity> feed = [];
  // The PvP matches live in [PvpNotifier] (one watcher for the whole app, so a
  // change shows here the moment it happens); these are its open matches seen
  // from my side.
  final _pvpWatch = PvpNotifier.instance;

  /// Challenges I have not answered.
  List<PvpMatch> get incoming => [
    for (final m in _pvpWatch.openMatches)
      if (m.status == PvpMatchStatus.pending && m.playerB == myId) m,
  ];

  /// My challenges nobody has accepted yet.
  List<PvpMatch> get sent => [
    for (final m in _pvpWatch.openMatches)
      if (m.status == PvpMatchStatus.pending && m.playerA == myId) m,
  ];

  /// Matches both sides agreed to: the lobby, or the fight running.
  List<PvpMatch> get open =>
      [
        for (final m in _pvpWatch.openMatches)
          if (m.status == PvpMatchStatus.accepted ||
              m.status == PvpMatchStatus.active)
            m,
      ]..sort(
        (a, b) => a.status == b.status
            ? b.createdAt.compareTo(a.createdAt)
            : (a.status == PvpMatchStatus.active ? -1 : 1),
      );

  /// What is waiting on me in PvP — the PvP tab's badge.
  int get pvpAttention => _pvpWatch.attention;

  SocialController() {
    _pvpWatch.addListener(_onPvpChanged);
  }

  void _onPvpChanged() => _notify();

  RealtimeChannel? _channel;
  final _messageStream = StreamController<ChatMessage>.broadcast();
  bool _disposed = false;

  /// Every new message that touches me, live — the open chat listens to this
  /// for its own thread, and the list refreshes its summaries from it.
  Stream<ChatMessage> get messages => _messageStream.stream;

  String nameOf(String userId) => names[userId] ?? '(unknown)';

  List<Friendship> get incomingRequests =>
      friendships.where((f) => f.awaitingMyResponse(myId)).toList();
  List<Friendship> get outgoingRequests =>
      friendships.where((f) => f.sentByMe(myId)).toList();

  /// Accepted friends, threads first (newest message on top), the rest by name.
  List<SocialFriend> get friends {
    final list = [
      for (final f in friendships)
        if (f.status == FriendshipStatus.accepted)
          SocialFriend(
            userId: f.otherUserId(myId),
            name: nameOf(f.otherUserId(myId)),
            friendship: f,
          ),
    ];
    list.sort((a, b) {
      final ta = threads[a.userId]?.lastMessage.createdAt;
      final tb = threads[b.userId]?.lastMessage.createdAt;
      if (ta != null && tb != null) return tb.compareTo(ta);
      if (ta != null) return -1;
      if (tb != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  int get unreadTotal =>
      threads.values.fold(0, (sum, t) => sum + t.unreadCount);

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _pvpSvc.expireStale();
      await _loadAll();
      _subscribe();
    } catch (e) {
      error = '$e';
    }
    loading = false;
    _notify();
  }

  Future<void> _loadAll() async {
    final friendships = await _friendsSvc.listFriendships();
    final accepted = [
      for (final f in friendships)
        if (f.status == FriendshipStatus.accepted) f.otherUserId(myId),
    ];
    final results = await Future.wait<Object>([
      _messagesSvc.listRecentMessages(),
      _pvpSvc.loadLeaderboard(accepted),
      _activitySvc.loadFeed(),
    ]);
    await _pvpWatch.reload();
    final recent = results[0] as List<ChatMessage>;
    final board = results[1] as List<PvpStats>;
    final feed = results[2] as List<FriendActivity>;

    final byOther = _groupByOther(recent);
    final ids = <String>{
      for (final f in friendships) f.otherUserId(myId),
      ...byOther.keys,
      ...feed.map((a) => a.userId),
      for (final m in _pvpWatch.openMatches) m.otherUserId(myId),
    };
    final names = await _friendsSvc.usernamesFor(ids.toList());

    this.friendships = friendships;
    this.names = names;
    threads = _summaries(byOther, names);
    leaderboard = board;
    stats = {for (final s in board) s.userId: s};
    this.feed = feed;
  }

  Map<String, List<ChatMessage>> _groupByOther(List<ChatMessage> recent) {
    final byOther = <String, List<ChatMessage>>{};
    for (final m in recent) {
      final other = m.senderId == myId ? m.recipientId : m.senderId;
      (byOther[other] ??= []).add(m);
    }
    return byOther;
  }

  Map<String, MessageThreadSummary> _summaries(
    Map<String, List<ChatMessage>> byOther,
    Map<String, String?> names,
  ) {
    final out = <String, MessageThreadSummary>{};
    for (final entry in byOther.entries) {
      final msgs = entry.value
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      out[entry.key] = MessageThreadSummary(
        otherUserId: entry.key,
        otherUsername: names[entry.key] ?? '(unknown)',
        lastMessage: msgs.first,
        unreadCount: msgs
            .where((m) => m.recipientId == myId && m.readAt == null)
            .length,
      );
    }
    return out;
  }

  void _subscribe() {
    _channel ??= _messagesSvc.subscribeToMessages((msg) {
      if (_disposed) return;
      _messageStream.add(msg);
      refreshThreads();
    });
  }

  /// Re-reads the thread summaries only — after a message arrives, or a chat
  /// marks its thread read.
  Future<void> refreshThreads() async {
    try {
      final recent = await _messagesSvc.listRecentMessages();
      threads = _summaries(_groupByOther(recent), names);
      _notify();
    } catch (_) {
      // The list simply stays as it was; the next load fixes it.
    }
  }

  /// Re-reads the PvP lists and the ratings — after answering a challenge or
  /// coming back from a lobby.
  Future<void> refreshPvp() async {
    try {
      await _pvpSvc.expireStale();
      await _pvpWatch.reload();
      final accepted = [for (final f in friends) f.userId];
      leaderboard = await _pvpSvc.loadLeaderboard(accepted);
      stats = {for (final s in leaderboard) s.userId: s};
      final missing = <String>{
        for (final m in _pvpWatch.openMatches) m.otherUserId(myId),
      }.where((id) => !names.containsKey(id)).toList();
      if (missing.isNotEmpty) {
        names = {...names, ...await _friendsSvc.usernamesFor(missing)};
      }
      _notify();
    } catch (_) {}
  }

  // ── Friends ─────────────────────────────────────────────────────────────

  Future<List<FriendSearchResult>> search(String query) =>
      _friendsSvc.searchByUsername(query);

  Future<void> sendRequest(String userId) async {
    await _friendsSvc.sendRequest(userId);
    await reloadFriends();
  }

  Future<void> accept(Friendship f) async {
    await _friendsSvc.acceptRequest(f.id);
    await reloadFriends();
  }

  Future<void> decline(Friendship f) async {
    await _friendsSvc.declineRequest(f.id);
    await reloadFriends();
  }

  Future<void> remove(Friendship f) async {
    await _friendsSvc.removeFriendship(f.id);
    await reloadFriends();
  }

  Future<void> reloadFriends() async {
    try {
      await _loadAll();
      _notify();
    } catch (_) {}
  }

  // ── PvP ─────────────────────────────────────────────────────────────────

  /// Fire-and-forget (user 2026-09-15): sends the challenge and stays put. The
  /// opponent sees it in their PvP list; once they accept, BOTH sides build a
  /// team and ready up in the lobby.
  Future<void> challenge(String opponentId) async {
    final match = await _pvpSvc.createChallenge(opponentId);
    _pvpWatch.remember(match);
    await refreshPvp();
  }

  Future<PvpMatch> acceptChallenge(PvpMatch m) => _pvpSvc.acceptChallenge(m.id);

  Future<void> declineChallenge(PvpMatch m) async {
    _pvpWatch.markMine(m.id);
    await _pvpSvc.declineChallenge(m.id);
    await refreshPvp();
  }

  /// Takes back a challenge I sent that nobody has answered yet.
  Future<void> cancelChallenge(PvpMatch m) async {
    _pvpWatch.markMine(m.id);
    await _pvpSvc.cancelChallenge(m.id);
    await refreshPvp();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _pvpWatch.removeListener(_onPvpChanged);
    _disposed = true;
    _channel?.unsubscribe();
    _messageStream.close();
    super.dispose();
  }
}

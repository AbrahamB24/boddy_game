import 'package:flutter/material.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/foe_theme.dart';
import '../settlement/widgets/parchment_sheet.dart';
import 'models/activity.dart';
import 'models/friend.dart';
import 'models/pvp_match.dart';
import 'services/activity_service.dart';
import 'services/friends_service.dart';
import 'services/pvp_service.dart';

/// Friends leaderboard (PvP rating) + activity feed, one tab — both are
/// small and both are "things your friends did", so they share a screen
/// rather than each getting a whole tab of their own.
class RankingFeedTab extends StatefulWidget {
  const RankingFeedTab({super.key});

  @override
  State<RankingFeedTab> createState() => _RankingFeedTabState();
}

class _RankingFeedTabState extends State<RankingFeedTab> {
  final _friendsSvc = FriendsService();
  final _pvpSvc = PvpService();
  final _activitySvc = ActivityService();

  String get _myId => supabase.auth.currentUser!.id;

  bool _loading = true;
  List<PvpStats> _leaderboard = [];
  List<FriendActivity> _feed = [];
  Map<String, String?> _names = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final friendships = await _friendsSvc.listFriendships();
    final friendIds = friendships
        .where((f) => f.status == FriendshipStatus.accepted)
        .map((f) => f.otherUserId(_myId))
        .toList();

    final results = await Future.wait([
      _pvpSvc.loadLeaderboard(friendIds),
      _activitySvc.loadFeed(),
    ]);
    final leaderboard = results[0] as List<PvpStats>;
    final feed = results[1] as List<FriendActivity>;

    final names = await _friendsSvc.usernamesFor({
      ...leaderboard.map((s) => s.userId),
      ...feed.map((a) => a.userId),
    }.toList());

    if (!mounted) return;
    setState(() {
      _leaderboard = leaderboard;
      _feed = feed;
      _names = names;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _section('Friends leaderboard'),
        if (_leaderboard.isEmpty)
          _hint('Add friends to see how your PvP rating compares.')
        else
          for (var i = 0; i < _leaderboard.length; i++) _rankRow(i + 1, _leaderboard[i]),
        const SizedBox(height: 20),
        _section('Activity'),
        if (_feed.isEmpty)
          _hint('Nothing yet — a win, a friend added, a new level will show up here.')
        else
          for (final a in _feed) _feedRow(a),
      ],
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: FoE.label(size: 12).copyWith(
        color: ParchmentSheet.accent,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(text, style: FoE.dim(size: 12).copyWith(color: ParchmentSheet.inkFaint)),
  );

  Widget _rankRow(int rank, PvpStats s) {
    final isMe = s.userId == _myId;
    final name = isMe ? 'You' : (_names[s.userId] ?? '(unknown)');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: isMe
          ? ParchmentSheet.card
          : ShapeDecoration(
              color: ParchmentSheet.ink.withValues(alpha: 0.03),
              shape: FoE.facet(radius: 10),
            ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('$rank', style: FoE.label(size: 12).copyWith(color: ParchmentSheet.inkFaint)),
          ),
          Expanded(
            child: Text(
              name,
              style: FoE.label(size: 13).copyWith(
                color: ParchmentSheet.ink,
                fontWeight: isMe ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text('${s.rating}', style: FoE.label(size: 13).copyWith(color: ParchmentSheet.accent)),
          const SizedBox(width: 6),
          Text('${s.wins}W ${s.losses}L', style: FoE.dim(size: 10).copyWith(color: ParchmentSheet.inkFaint)),
        ],
      ),
    );
  }

  Widget _feedRow(FriendActivity a) {
    final name = a.userId == _myId ? 'You' : (_names[a.userId] ?? '(unknown)');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconFor(a.kind), size: 16, color: ParchmentSheet.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(a.describe(name), style: FoE.label(size: 12).copyWith(color: ParchmentSheet.ink)),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(ActivityKind? kind) => switch (kind) {
    ActivityKind.friendAdded => Icons.people_alt_outlined,
    ActivityKind.battleWon => Icons.emoji_events_outlined,
    ActivityKind.buildingUpgraded => Icons.construction,
    ActivityKind.levelUp => Icons.trending_up,
    null => Icons.circle_notifications_outlined,
  };
}

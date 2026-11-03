import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import 'models/activity.dart';
import 'models/pvp_match.dart';
import 'social_controller.dart';
import 'widgets/social_kit.dart';
import '../../core/theme/voxel_icons.dart';

/// The friends leaderboard (you among them) next to the activity feed.
class RankingPane extends StatelessWidget {
  final SocialController ctrl;

  const RankingPane({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ctrl,
    builder: (context, _) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 11, child: _board()),
        Container(width: 1, color: CreamPalette.tan.withValues(alpha: 0.4)),
        Expanded(flex: 9, child: _feed()),
      ],
    ),
  );

  Widget _board() {
    final rows = ctrl.leaderboard;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      children: [
        socialSection('Friends ranking'),
        if (rows.length <= 1)
          socialHint('Add friends to see how your PvP rating compares.')
        else
          for (var i = 0; i < rows.length; i++) _rankRow(i + 1, rows[i]),
      ],
    );
  }

  Widget _rankRow(int rank, PvpStats s) {
    final isMe = s.userId == ctrl.myId;
    final name = isMe ? 'You' : ctrl.nameOf(s.userId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: socialRow(
        lit: isMe,
        height: 40,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '$rank',
                style: FoE.label(size: 12).copyWith(color: kBoxInkFaint),
              ),
            ),
            SocialAvatar(name, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.label(size: 13).copyWith(
                  color: kBoxInk,
                  fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${s.rating}',
              style: FoE.value(size: 13).copyWith(color: kBoxAccent),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 50,
              child: Text(
                '${s.wins}W ${s.losses}L',
                textAlign: TextAlign.right,
                style: FoE.dim(size: 10).copyWith(color: kBoxInkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feed() => ListView(
    padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
    children: [
      socialSection('Activity'),
      if (ctrl.feed.isEmpty)
        socialHint(
          'Nothing yet — a win, a friend added, a new level will show up here.',
        )
      else
        for (final a in ctrl.feed) _feedRow(a),
    ],
  );

  Widget _feedRow(FriendActivity a) {
    final name = a.userId == ctrl.myId ? 'You' : ctrl.nameOf(a.userId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PixelIcon(_iconFor(a.kind), size: 16, color: kBoxAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              a.describe(name),
              style: FoE.label(size: 12).copyWith(color: kBoxInk),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _ago(a.createdAt),
            style: FoE.dim(size: 10).copyWith(color: kBoxInkFaint),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(ActivityKind? kind) => switch (kind) {
    ActivityKind.friendAdded => Icons.people_alt_outlined,
    ActivityKind.battleWon => Icons.emoji_events_outlined,
    ActivityKind.buildingUpgraded => Icons.construction,
    ActivityKind.levelUp => Icons.trending_up,
    null => Icons.circle_notifications_outlined,
  };

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

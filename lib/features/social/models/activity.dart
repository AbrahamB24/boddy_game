/// One row of `friend_activity` — see
/// supabase/migrations/0049_social_activity_feed.sql. Written at the
/// moments that matter (friend added, PvP won, level-up), not via a DB
/// trigger on every table — a deliberate v1 scope cut.
enum ActivityKind { friendAdded, battleWon, buildingUpgraded, levelUp }

ActivityKind? _kindFromString(String s) => switch (s) {
  'friend_added' => ActivityKind.friendAdded,
  'battle_won' => ActivityKind.battleWon,
  'building_upgraded' => ActivityKind.buildingUpgraded,
  'level_up' => ActivityKind.levelUp,
  _ => null,
};

String activityKindToString(ActivityKind k) => switch (k) {
  ActivityKind.friendAdded => 'friend_added',
  ActivityKind.battleWon => 'battle_won',
  ActivityKind.buildingUpgraded => 'building_upgraded',
  ActivityKind.levelUp => 'level_up',
};

class FriendActivity {
  final String id;
  final String userId;
  final ActivityKind? kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const FriendActivity({
    required this.id,
    required this.userId,
    required this.kind,
    required this.payload,
    required this.createdAt,
  });

  factory FriendActivity.fromMap(Map<String, dynamic> m) => FriendActivity(
    id: m['id'] as String,
    userId: m['user_id'] as String,
    kind: _kindFromString(m['kind'] as String? ?? ''),
    payload: (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  /// A short, human line for the feed — the payload's own free-text label
  /// when present (species/building name), else a generic fallback.
  String describe(String actorName) {
    final label = payload['label'] as String?;
    return switch (kind) {
      ActivityKind.friendAdded => '$actorName made a new friend.',
      ActivityKind.battleWon =>
        label != null
            ? '$actorName won a PvP battle against $label.'
            : '$actorName won a PvP battle.',
      ActivityKind.buildingUpgraded =>
        label != null
            ? '$actorName upgraded $label.'
            : '$actorName upgraded a building.',
      ActivityKind.levelUp =>
        label != null
            ? '$actorName\'s $label reached a new level.'
            : '$actorName leveled up.',
      null => '$actorName did something.',
    };
  }
}

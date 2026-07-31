// A named, reusable battle roster ("Steinteam", "Boss team", …).
//
// WHY THIS EXISTS: battleTeam() is the ONE team-selection rule in the game —
// dungeon entry, the fight ladder, training and the tech trials all read it —
// and it used to mean "the first N creatures that aren't busy". Since the
// collection loads ordered by caught_at, that silently meant your OLDEST
// monsters. Catching something better did nothing until the veterans were
// K.O.'d, and there was nowhere in the app to say otherwise.
//
// A saved team is the player's answer to "who fights": pick once, name it,
// reuse it. Exactly one team is active at a time; with none active,
// battleTeam() keeps its old first-N behaviour so a fresh profile still works
// before the player has built any team.
/// What a roster is FOR (migration 0028). Both are the same object — a name and
/// a list of creature ids — and they are stored in the same table; the kind is
/// what keeps the Market's haulers out of the battle-team picker and vice
/// versa.
enum TeamKind {
  battle,
  caravan;

  static TeamKind fromName(String? name) =>
      TeamKind.values.firstWhere((k) => k.name == name,
          orElse: () => TeamKind.battle);
}

class SavedTeam {
  final String id;
  final String userId;
  final String name;

  /// A fighting roster or a Market caravan. Only [TeamKind.battle] rows are
  /// ever [isActive] — see the migration's note on the partial unique index.
  final TeamKind kind;

  /// Creature ids in the player's chosen order. Membership is NOT validated
  /// here: a member can be K.O., away or since released. battleTeam() filters
  /// on read instead — the roster is intent, not a live claim, so a team
  /// shouldn't quietly rewrite itself because someone got hurt.
  final List<String> memberIds;

  /// Exactly one team per user is active. Enforced by the controller (it
  /// clears the others on activate), not by a DB constraint.
  final bool isActive;

  const SavedTeam({
    required this.id,
    required this.userId,
    required this.name,
    this.kind = TeamKind.battle,
    this.memberIds = const [],
    this.isActive = false,
  });

  SavedTeam copyWith({String? name, List<String>? memberIds, bool? isActive}) =>
      SavedTeam(
        id: id,
        userId: userId,
        name: name ?? this.name,
        kind: kind,
        memberIds: memberIds ?? this.memberIds,
        isActive: isActive ?? this.isActive,
      );

  factory SavedTeam.fromRow(Map<String, dynamic> row) => SavedTeam(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    name: row['name'] as String? ?? 'Team',
    // A row written before migration 0028 has no `kind` at all — and every one
    // of those IS a battle team, which is what the fallback says.
    kind: TeamKind.fromName(row['kind'] as String?),
    memberIds: ((row['member_ids'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    isActive: row['is_active'] as bool? ?? false,
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'kind': kind.name,
    'member_ids': memberIds,
    'is_active': isActive,
  };
}

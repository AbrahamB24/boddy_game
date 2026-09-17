/// One row of `pvp_stats` — see supabase/migrations/0050_social_pvp.sql.
/// Missing row (a player who has never finished a match) reads as the same
/// defaults the table itself defaults new rows to.
class PvpStats {
  final String userId;
  final int rating;
  final int wins;
  final int losses;

  const PvpStats({
    required this.userId,
    this.rating = 1000,
    this.wins = 0,
    this.losses = 0,
  });

  factory PvpStats.fromMap(Map<String, dynamic> m) => PvpStats(
    userId: m['user_id'] as String,
    rating: (m['rating'] as num).toInt(),
    wins: (m['wins'] as num).toInt(),
    losses: (m['losses'] as num).toInt(),
  );
}

enum PvpMatchStatus { pending, accepted, active, finished, abandoned }

PvpMatchStatus _statusFromString(String s) => PvpMatchStatus.values.firstWhere(
  (v) => v.name == s,
  orElse: () => PvpMatchStatus.pending,
);

/// One row of `pvp_matches` — a challenge, and once accepted the persisted
/// checkpoint (seed + action log) a live lockstep battle relays actions
/// against. See the "Real-time 6v6 PvP" section of the plan for why this is
/// persisted rather than pure ephemeral broadcast.
class PvpMatch {
  final String id;
  final String playerA;
  final String playerB;
  final PvpMatchStatus status;
  final int? seed;

  /// Combatant snapshots (see pvp_combatant_snapshot.dart) — each side's own
  /// team as they picked it at accept time, frozen for the match. NOT
  /// creature ids: RLS on `creatures` is owner-only, so a snapshot is the
  /// only way the opponent's device ever learns your team's stats/abilities.
  final List<Map<String, dynamic>>? teamA;
  final List<Map<String, dynamic>>? teamB;

  /// Lobby ready flags (supabase/migrations/0052_pvp_lobby.sql) — each side
  /// sets its own via [PvpService.setReady] once they've confirmed a team.
  /// The match only becomes `active` (seed assigned) once both are true.
  final bool readyA;
  final bool readyB;
  final List<Map<String, dynamic>> actionLog;
  final String? winnerId;
  final DateTime createdAt;

  const PvpMatch({
    required this.id,
    required this.playerA,
    required this.playerB,
    required this.status,
    this.seed,
    this.teamA,
    this.teamB,
    this.readyA = false,
    this.readyB = false,
    this.actionLog = const [],
    this.winnerId,
    required this.createdAt,
  });

  factory PvpMatch.fromMap(Map<String, dynamic> m) => PvpMatch(
    id: m['id'] as String,
    playerA: m['player_a'] as String,
    playerB: m['player_b'] as String,
    status: _statusFromString(m['status'] as String? ?? 'pending'),
    seed: (m['seed'] as num?)?.toInt(),
    teamA: (m['team_a'] as List?)
        ?.map((e) => (e as Map).cast<String, dynamic>())
        .toList(),
    teamB: (m['team_b'] as List?)
        ?.map((e) => (e as Map).cast<String, dynamic>())
        .toList(),
    readyA: m['ready_a'] as bool? ?? false,
    readyB: m['ready_b'] as bool? ?? false,
    actionLog: ((m['action_log'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(),
    winnerId: m['winner_id'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  String otherUserId(String myUserId) => playerA == myUserId ? playerB : playerA;

  bool myReady(String myUserId) => myUserId == playerA ? readyA : readyB;
  bool opponentReady(String myUserId) => myUserId == playerA ? readyB : readyA;
}

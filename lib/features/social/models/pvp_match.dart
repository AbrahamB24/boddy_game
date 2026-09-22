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

  /// Resilience (supabase/migrations/0053_pvp_resilience.sql): heartbeat
  /// timestamps, whose decision is currently outstanding, and that
  /// decision's deadline. `waitingOn` covers both "it's their turn" AND
  /// "they disconnected and haven't come back" — one timer, see the
  /// migration's doc comment for why.
  final DateTime? lastSeenA;
  final DateTime? lastSeenB;
  final String? waitingOn;
  final DateTime? turnDeadlineAt;
  final DateTime? lobbyExpiresAt;
  final String? abandonReason;

  /// Lobby presence (supabase/migrations/0054_pvp_lobby_presence.sql): whether
  /// each side has the lobby OPEN right now (not minimised), and the heartbeat
  /// that keeps a crashed client from counting as "in the lobby" for ever.
  final bool inLobbyA;
  final bool inLobbyB;
  final DateTime? lobbySeenA;
  final DateTime? lobbySeenB;

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
    this.lastSeenA,
    this.lastSeenB,
    this.waitingOn,
    this.turnDeadlineAt,
    this.lobbyExpiresAt,
    this.abandonReason,
    this.inLobbyA = false,
    this.inLobbyB = false,
    this.lobbySeenA,
    this.lobbySeenB,
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
    lastSeenA: m['last_seen_a'] == null
        ? null
        : DateTime.parse(m['last_seen_a'] as String),
    lastSeenB: m['last_seen_b'] == null
        ? null
        : DateTime.parse(m['last_seen_b'] as String),
    waitingOn: m['waiting_on'] as String?,
    turnDeadlineAt: m['turn_deadline_at'] == null
        ? null
        : DateTime.parse(m['turn_deadline_at'] as String),
    lobbyExpiresAt: m['lobby_expires_at'] == null
        ? null
        : DateTime.parse(m['lobby_expires_at'] as String),
    abandonReason: m['abandon_reason'] as String?,
    inLobbyA: m['in_lobby_a'] as bool? ?? false,
    inLobbyB: m['in_lobby_b'] as bool? ?? false,
    lobbySeenA: m['lobby_seen_a'] == null
        ? null
        : DateTime.parse(m['lobby_seen_a'] as String),
    lobbySeenB: m['lobby_seen_b'] == null
        ? null
        : DateTime.parse(m['lobby_seen_b'] as String),
  );

  String otherUserId(String myUserId) =>
      playerA == myUserId ? playerB : playerA;

  bool myReady(String myUserId) => myUserId == playerA ? readyA : readyB;
  bool opponentReady(String myUserId) => myUserId == playerA ? readyB : readyA;

  /// My own last-seen timestamp isn't useful (that's just "now", from my own
  /// heartbeat) — this is always the OTHER side's, for the "opponent
  /// disconnected" banner.
  DateTime? opponentLastSeen(String myUserId) =>
      myUserId == playerA ? lastSeenB : lastSeenA;

  /// Whether [userId] has the lobby open — the flag AND a recent heartbeat, so
  /// a client that died without saying goodbye stops counting after a minute.
  bool inLobby(String userId, {DateTime? now}) {
    final isA = userId == playerA;
    final flag = isA ? inLobbyA : inLobbyB;
    final seen = isA ? lobbySeenA : lobbySeenB;
    if (!flag || seen == null) return false;
    return (now ?? DateTime.now()).difference(seen) < kLobbyPresenceWindow;
  }

  bool opponentInLobby(String myUserId, {DateTime? now}) =>
      inLobby(otherUserId(myUserId), now: now);

  bool get bothReady => readyA && readyB;

  /// Where the OTHER player is in this match, from [myUserId]'s side — the
  /// line every PvP list and the lobby show ("Not yet accepted", "Waiting in
  /// the lobby", "Ready").
  PvpOpponentStage opponentStage(String myUserId, {DateTime? now}) {
    switch (status) {
      case PvpMatchStatus.pending:
        return PvpOpponentStage.notAccepted;
      case PvpMatchStatus.active:
        return PvpOpponentStage.inBattle;
      case PvpMatchStatus.accepted:
        if (opponentReady(myUserId)) return PvpOpponentStage.ready;
        if (opponentInLobby(myUserId, now: now)) {
          return PvpOpponentStage.inLobby;
        }
        return PvpOpponentStage.notInLobby;
      case PvpMatchStatus.finished:
      case PvpMatchStatus.abandoned:
        return PvpOpponentStage.over;
    }
  }
}

/// How long an unanswered challenge / an accepted lobby stays open. Long on
/// purpose (user 2026-09-19): you minimise the lobby and do other things, the
/// opponent turns up later.
const Duration kLobbyLifetime = Duration(hours: 24);

/// How often the open lobby says "still here", and how old a heartbeat may be
/// before the player stops counting as in the lobby.
const Duration kLobbyHeartbeat = Duration(seconds: 15);
const Duration kLobbyPresenceWindow = Duration(seconds: 60);

/// Where the opponent stands, in the order a match moves through them.
enum PvpOpponentStage {
  /// The challenge is out; they have not answered.
  notAccepted('Not yet accepted'),

  /// Accepted, but their lobby is not open.
  notInLobby('Accepted — not in the lobby'),

  /// Their lobby is open and they are choosing a team.
  inLobby('Waiting in the lobby'),

  /// Their team is chosen.
  ready('Ready'),

  inBattle('In battle'),
  over('Over');

  final String label;
  const PvpOpponentStage(this.label);
}

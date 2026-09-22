import '../../../core/supabase/supabase_client.dart';
import '../models/pvp_match.dart';

/// PvP ratings, the friends leaderboard, and match challenge rows — see
/// supabase/migrations/0050_social_pvp.sql. The live battle's own turn-by-
/// turn sync is a separate concern (pvp_sync_service.dart); this is the CRUD
/// side: stats, leaderboard, and opening/accepting a challenge.
class PvpService {
  String get _myId => supabase.auth.currentUser!.id;

  Future<PvpStats> loadMyStats() async {
    final row = await supabase
        .from('pvp_stats')
        .select()
        .eq('user_id', _myId)
        .maybeSingle();
    return row == null ? PvpStats(userId: _myId) : PvpStats.fromMap(row);
  }

  /// Ratings for me plus [friendUserIds], sorted highest first. A friend with
  /// no row yet (never finished a match) is folded in at the default 1000.
  Future<List<PvpStats>> loadLeaderboard(List<String> friendUserIds) async {
    final ids = {_myId, ...friendUserIds}.toList();
    final rows = await supabase
        .from('pvp_stats')
        .select()
        .inFilter('user_id', ids);
    final byId = {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['user_id'] as String: PvpStats.fromMap(r),
    };
    final list = [for (final id in ids) byId[id] ?? PvpStats(userId: id)];
    list.sort((a, b) => b.rating.compareTo(a.rating));
    return list;
  }

  /// Opens a challenge — [opponentId] sees it as an incoming request (PvP
  /// tab's "Incoming" list). Fire-and-forget on purpose (user 2026-09-15):
  /// no team snapshot, no navigation — that all happens later, in the Lobby,
  /// once BOTH sides have accepted. Just the two ids; `status` defaults to
  /// `pending`.
  Future<PvpMatch> createChallenge(String opponentId) async {
    final row = await supabase
        .from('pvp_matches')
        .insert({
          'player_a': _myId,
          'player_b': opponentId,
          // An unanswered challenge expires too, so the list cannot fill up
          // with ones nobody will ever answer.
          'lobby_expires_at': DateTime.now()
              .toUtc()
              .add(kLobbyLifetime)
              .toIso8601String(),
        })
        .select()
        .single();
    return PvpMatch.fromMap(row);
  }

  /// Pending challenges waiting on MY response (I'm `player_b`).
  Future<List<PvpMatch>> loadPendingChallenges() async {
    final rows = await supabase
        .from('pvp_matches')
        .select()
        .eq('status', 'pending')
        .eq('player_b', _myId)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PvpMatch.fromMap)
        .toList();
  }

  /// Challenges I sent that are still awaiting the other side's response —
  /// purely informational (PvP tab's "Sent" list), no action on them.
  Future<List<PvpMatch>> loadSentChallenges() async {
    final rows = await supabase
        .from('pvp_matches')
        .select()
        .eq('status', 'pending')
        .eq('player_a', _myId)
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PvpMatch.fromMap)
        .toList();
  }

  /// Matches either side can still act on: `accepted` (go build a team in
  /// the Lobby) or `active` (resume — a reconnect). Not `pending`/`finished`/
  /// `abandoned`.
  Future<List<PvpMatch>> loadOpenMatches() async {
    final rows = await supabase
        .from('pvp_matches')
        .select()
        .inFilter('status', ['accepted', 'active'])
        .or('player_a.eq.$_myId,player_b.eq.$_myId')
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PvpMatch.fromMap)
        .toList();
  }

  /// Just a lightweight consent — flips `pending` → `accepted`. No team, no
  /// seed yet: both of those are set once each side readies up in the Lobby
  /// (see [setReady]). Also starts the lobby's lifetime ([kLobbyLifetime]) — swept by
  /// [expireStale] if nobody ever finishes it.
  Future<PvpMatch> acceptChallenge(String matchId) async {
    final row = await supabase
        .from('pvp_matches')
        .update({
          'status': 'accepted',
          'lobby_expires_at': DateTime.now()
              .toUtc()
              .add(kLobbyLifetime)
              .toIso8601String(),
        })
        .eq('id', matchId)
        .select()
        .single();
    return PvpMatch.fromMap(row);
  }

  Future<void> declineChallenge(String matchId) async {
    await supabase
        .from('pvp_matches')
        .update({'status': 'abandoned', 'abandon_reason': 'declined'})
        .eq('id', matchId);
  }

  /// Takes back a challenge I sent that is still unanswered — the same
  /// `abandoned` end a decline gives it, so the other side's list drops it
  /// too. Either player may write it (the update policy allows both).
  Future<void> cancelChallenge(String matchId) async {
    await supabase
        .from('pvp_matches')
        .update({'status': 'abandoned', 'abandon_reason': 'cancelled'})
        .eq('id', matchId)
        .eq('status', 'pending');
  }

  /// Leaves a match for good — the lobby of an ACCEPTED challenge, or a
  /// challenge of mine still waiting (cancel). The other side sees it end
  /// (`abandoned`, reason 'left') and is told why. Nothing is at stake before
  /// the battle starts, so there is no penalty; a battle that is already
  /// running is not left this way.
  Future<void> leaveMatch(String matchId) async {
    await supabase
        .from('pvp_matches')
        .update({
          'status': 'abandoned',
          'abandon_reason': 'left',
          'in_lobby_a': false,
          'in_lobby_b': false,
        })
        .eq('id', matchId)
        .inFilter('status', ['pending', 'accepted']);
  }

  /// Says "I have this lobby open" (or, with [present] false, "I minimised it")
  /// — the flag the opponent's notification and the PvP lists read. Also the
  /// heartbeat: the open lobby repeats it every [kLobbyHeartbeat].
  Future<void> setLobbyPresence(String matchId, bool present) async {
    await supabase.rpc(
      'pvp_lobby_presence',
      params: {'p_match_id': matchId, 'p_present': present},
    );
  }

  /// Starts the battle if it is time: BOTH ready AND BOTH in the lobby. The
  /// second condition is what lets you ready up, minimise the lobby and go
  /// away — the battle waits until you are back instead of starting with
  /// nobody there and running your turn timer out. Guarded on `accepted` so
  /// only the first client to see it does the flip (the same race-safe shape
  /// [finishMatch] uses); everyone else re-reads what that one produced.
  Future<PvpMatch> tryStart(PvpMatch m) async {
    if (m.status != PvpMatchStatus.accepted ||
        !m.bothReady ||
        !m.inLobby(m.playerA) ||
        !m.inLobby(m.playerB)) {
      return m;
    }
    final seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    final flipped = await supabase
        .from('pvp_matches')
        .update({'status': 'active', 'seed': seed})
        .eq('id', m.id)
        .eq('status', 'accepted')
        .select();
    final rows = flipped as List;
    return rows.isEmpty
        ? await loadMatch(m.id)
        : PvpMatch.fromMap((rows.first as Map).cast<String, dynamic>());
  }

  Future<PvpMatch> loadMatch(String matchId) async {
    final row = await supabase
        .from('pvp_matches')
        .select()
        .eq('id', matchId)
        .single();
    return PvpMatch.fromMap(row);
  }

  /// Confirms MY team in the Lobby and marks me ready. Writes to `team_a`/
  /// `ready_a` or `team_b`/`ready_b` depending on which side I am. If this
  /// write leaves BOTH sides ready, also flips the match to `active` with a
  /// fresh shared seed — guarded by `eq('status', 'accepted')` so only the
  /// FIRST client to observe "both ready" actually performs the flip (the
  /// same race-safe shape [finishMatch] uses); the second client's attempt
  /// matches zero rows and just re-reads the row the first one produced.
  Future<PvpMatch> setReady(
    String matchId,
    List<Map<String, dynamic>> myTeam,
  ) async {
    final before = await loadMatch(matchId);
    final amA = before.playerA == _myId;
    final row = await supabase
        .from('pvp_matches')
        .update(
          amA
              ? {'team_a': myTeam, 'ready_a': true}
              : {'team_b': myTeam, 'ready_b': true},
        )
        .eq('id', matchId)
        .select()
        .single();
    return tryStart(PvpMatch.fromMap(row));
  }

  /// Appends one relayed action to the checkpoint log — see
  /// pvp_sync_service.dart, which calls this alongside the live broadcast.
  /// Goes through the `pvp_append_action` RPC (0053_pvp_resilience.sql)
  /// rather than a raw update: it re-checks the seq is the next expected one
  /// and that `kind` is a known action, closing the "inject/replay an
  /// arbitrary action" hole a plain client-side update would leave open.
  /// Deliberately does NOT validate game-rule legality (damage, AP cost,
  /// whose turn it really was) — see the migration's comment on why.
  Future<void> appendAction(String matchId, Map<String, dynamic> action) async {
    await supabase.rpc(
      'pvp_append_action',
      params: {'p_match_id': matchId, 'p_action': action},
    );
  }

  /// Heartbeat — called periodically by [PvpSyncService] while a battle is
  /// live so the OTHER side can tell "still connected" from "gone quiet".
  /// Fire-and-forget by design: a dropped heartbeat call just means the next
  /// one (or the opponent's timeout claim) handles it.
  Future<void> touchPresence(String matchId) async {
    await supabase.rpc('pvp_touch_presence', params: {'p_match_id': matchId});
  }

  /// Records whose decision the match is currently waiting on, resetting the
  /// deadline. Called whenever [CombatEngine.isPlayerTurn]/[isEnemyTurn]
  /// flips — see battle_screen.dart's `_syncTurnStateIfNeeded`. One timer
  /// covers both "it's their turn" and "they disconnected", see
  /// 0053_pvp_resilience.sql's doc comment.
  Future<void> advanceTurn(
    String matchId, {
    required String waitingOnUserId,
    int deadlineSeconds = 60,
  }) async {
    await supabase.rpc(
      'pvp_advance_turn',
      params: {
        'p_match_id': matchId,
        'p_waiting_on': waitingOnUserId,
        'p_deadline_seconds': deadlineSeconds,
      },
    );
  }

  /// Claims a win because the opponent's deadline passed without them
  /// acting (slow OR disconnected — see the migration). Server-authoritative:
  /// throws if the deadline hasn't actually passed or it isn't the caller's
  /// place to claim it, so callers should treat a failure as "not yet,
  /// ignore" rather than surface it.
  Future<PvpMatch> claimTimeoutWin(String matchId) async {
    final row = await supabase.rpc(
      'pvp_claim_timeout_win',
      params: {'p_match_id': matchId},
    );
    return PvpMatch.fromMap((row as Map).cast<String, dynamic>());
  }

  /// Lazy cleanup instead of a cron job: called opportunistically whenever a
  /// screen loads a list of matches (PvP tab, lobby) so a match/lobby nobody
  /// is actively watching doesn't stay open forever. Fire-and-forget — a
  /// missed sweep just gets caught by the next screen that loads.
  Future<void> expireStale() async {
    await supabase.rpc('pvp_expire_stale');
  }

  /// Telemetry only (pvp_desync_reports) — logs the rare case where two
  /// clients' independently-run [CombatEngine]s disagree despite being fed
  /// the same deterministic action sequence, so it can be investigated later.
  /// Never blocks or affects the match itself.
  Future<void> reportDesync(
    String matchId, {
    required int seq,
    required String myHash,
    String? expectedHash,
  }) async {
    await supabase.from('pvp_desync_reports').insert({
      'match_id': matchId,
      'reporter_id': _myId,
      'seq': seq,
      'my_hash': myHash,
      'expected_hash': expectedHash,
    });
  }

  /// Sets the match's result — corroborated by the `status <> 'finished'` RLS
  /// guard combined with `eq('status', 'active')` here, so only the FIRST
  /// client to report a result can set it; a second, contradicting report
  /// simply matches zero rows and is ignored. Does NOT touch either player's
  /// rating directly — the RLS policy on `pvp_stats` only lets a client write
  /// their OWN row ("write own pvp stats"), so a client can never adjust its
  /// opponent's rating. Instead both clients call [syncMyRatingAfterMatch]
  /// once they observe the match reach `finished`, each updating only their
  /// own stats row.
  Future<void> finishMatch(PvpMatch match, String winnerId) async {
    await supabase
        .from('pvp_matches')
        .update({
          'status': 'finished',
          'winner_id': winnerId,
          'finished_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', match.id)
        .eq('status', 'active');
  }

  /// Applies a finished match's result to MY OWN rating — a simple
  /// fixed-step Elo-ish adjustment (+15/-15). Safe to call more than once
  /// (e.g. a reconnect re-observing the same finished match): rating drift
  /// from a double-call is an accepted v1 tradeoff for not needing a
  /// separate "have I already applied this match" ledger in a personal,
  /// friends-only game.
  Future<void> syncMyRatingAfterMatch(PvpMatch match) async {
    if (match.status != PvpMatchStatus.finished || match.winnerId == null) {
      return;
    }
    final won = match.winnerId == _myId;
    final row = await supabase
        .from('pvp_stats')
        .select()
        .eq('user_id', _myId)
        .maybeSingle();
    final stats = row == null ? PvpStats(userId: _myId) : PvpStats.fromMap(row);
    await supabase.from('pvp_stats').upsert({
      'user_id': _myId,
      'rating': stats.rating + (won ? 15 : -15),
      'wins': stats.wins + (won ? 1 : 0),
      'losses': stats.losses + (won ? 0 : 1),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

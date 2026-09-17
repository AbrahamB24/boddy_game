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
    final rows = await supabase.from('pvp_stats').select().inFilter('user_id', ids);
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
        .insert({'player_a': _myId, 'player_b': opponentId})
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
    return (rows as List).cast<Map<String, dynamic>>().map(PvpMatch.fromMap).toList();
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
    return (rows as List).cast<Map<String, dynamic>>().map(PvpMatch.fromMap).toList();
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
    return (rows as List).cast<Map<String, dynamic>>().map(PvpMatch.fromMap).toList();
  }

  /// Just a lightweight consent — flips `pending` → `accepted`. No team, no
  /// seed yet: both of those are set once each side readies up in the Lobby
  /// (see [setReady]).
  Future<PvpMatch> acceptChallenge(String matchId) async {
    final row = await supabase
        .from('pvp_matches')
        .update({'status': 'accepted'})
        .eq('id', matchId)
        .select()
        .single();
    return PvpMatch.fromMap(row);
  }

  Future<void> declineChallenge(String matchId) async {
    await supabase.from('pvp_matches').update({'status': 'abandoned'}).eq('id', matchId);
  }

  Future<PvpMatch> loadMatch(String matchId) async {
    final row = await supabase.from('pvp_matches').select().eq('id', matchId).single();
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
    var updated = PvpMatch.fromMap(row);
    if (updated.readyA && updated.readyB && updated.status == PvpMatchStatus.accepted) {
      final seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
      final flipped = await supabase
          .from('pvp_matches')
          .update({'status': 'active', 'seed': seed})
          .eq('id', matchId)
          .eq('status', 'accepted')
          .select();
      final rows = flipped as List;
      updated = rows.isEmpty ? await loadMatch(matchId) : PvpMatch.fromMap(rows.first);
    }
    return updated;
  }

  /// Appends one relayed action to the checkpoint log — see
  /// pvp_sync_service.dart, which calls this alongside the live broadcast.
  Future<void> appendAction(String matchId, Map<String, dynamic> action) async {
    final match = await loadMatch(matchId);
    await supabase
        .from('pvp_matches')
        .update({
          'action_log': [...match.actionLog, action],
        })
        .eq('id', matchId);
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
    if (match.status != PvpMatchStatus.finished || match.winnerId == null) return;
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

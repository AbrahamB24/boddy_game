import '../../../core/supabase/supabase_client.dart';
import '../models/friend.dart';

/// Friends: search by username, send/accept/decline requests, list. Plain
/// service class calling `supabase.from(...)` directly, same shape as
/// SettlementService — no repository layer in this codebase.
class FriendsService {
  String get _myId => supabase.auth.currentUser!.id;

  Future<String?> loadMyUsername() async {
    final row = await supabase
        .from('profiles')
        .select('username')
        .eq('id', _myId)
        .maybeSingle();
    return row?['username'] as String?;
  }

  /// Throws a PostgrestException (code 23505) if the name is already taken —
  /// the partial unique index on lower(username) is the source of truth, not
  /// a pre-check here (avoids a check-then-write race).
  Future<void> setUsername(String username) async {
    await supabase.from('profiles').upsert({
      'id': _myId,
      'username': username.trim(),
    });
  }

  /// Case-insensitive substring search, excluding myself and unnamed
  /// profiles (a BoddyQuest-only row never has a username to find).
  Future<List<FriendSearchResult>> searchByUsername(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    final rows = await supabase
        .from('profiles')
        .select('id, username')
        .ilike('username', '%$q%')
        .neq('id', _myId)
        .limit(20);
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return [];

    final otherIds = list.map((r) => r['id'] as String).toList();
    final existing = await _friendshipsWith(otherIds);

    return list
        .map(
          (r) => FriendSearchResult(
            userId: r['id'] as String,
            username: r['username'] as String,
            friendship: existing[r['id'] as String],
          ),
        )
        .toList();
  }

  /// Every friendship row (any status) touching me, keyed by the OTHER
  /// user's id, filtered down to just [otherIds] when given.
  Future<Map<String, Friendship>> _friendshipsWith(
    List<String> otherIds,
  ) async {
    final rows = await supabase
        .from('friendships')
        .select()
        .or('requester_id.eq.$_myId,addressee_id.eq.$_myId');
    final map = <String, Friendship>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final f = Friendship.fromMap(r);
      final other = f.otherUserId(_myId);
      if (otherIds.contains(other)) map[other] = f;
    }
    return map;
  }

  /// All my friendships, newest first — accepted friends AND pending
  /// requests either direction; the screen sorts these into sections.
  Future<List<Friendship>> listFriendships() async {
    final rows = await supabase
        .from('friendships')
        .select()
        .or('requester_id.eq.$_myId,addressee_id.eq.$_myId')
        .order('created_at', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Friendship.fromMap)
        .toList();
  }

  /// Usernames for a batch of user ids (e.g. to label friend rows) — a
  /// missing entry means that profile has none set.
  Future<Map<String, String?>> usernamesFor(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final rows = await supabase
        .from('profiles')
        .select('id, username')
        .inFilter('id', userIds);
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['id'] as String: r['username'] as String?,
    };
  }

  Future<void> sendRequest(String toUserId) async {
    await supabase.from('friendships').insert({
      'requester_id': _myId,
      'addressee_id': toUserId,
    });
  }

  Future<void> acceptRequest(String friendshipId) async {
    await supabase
        .from('friendships')
        .update({
          'status': 'accepted',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', friendshipId);
  }

  Future<void> declineRequest(String friendshipId) async {
    await supabase
        .from('friendships')
        .update({
          'status': 'declined',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', friendshipId);
  }

  /// Removes a friendship row outright — used both to withdraw an own
  /// pending request and to unfriend an accepted one.
  Future<void> removeFriendship(String friendshipId) async {
    await supabase.from('friendships').delete().eq('id', friendshipId);
  }
}

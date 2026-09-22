enum FriendshipStatus { pending, accepted, declined, blocked }

FriendshipStatus friendshipStatusFromString(String s) => FriendshipStatus.values
    .firstWhere((v) => v.name == s, orElse: () => FriendshipStatus.pending);

/// One row of `friendships` — see supabase/migrations/0047_social_friends.sql.
/// Directional (who requested), but a pair only ever has one row either way.
class Friendship {
  final String id;
  final String requesterId;
  final String addresseeId;
  final FriendshipStatus status;
  final DateTime createdAt;

  const Friendship({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    required this.createdAt,
  });

  factory Friendship.fromMap(Map<String, dynamic> m) => Friendship(
    id: m['id'] as String,
    requesterId: m['requester_id'] as String,
    addresseeId: m['addressee_id'] as String,
    status: friendshipStatusFromString(m['status'] as String? ?? 'pending'),
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  /// The other user in this friendship, given "my" id.
  String otherUserId(String myUserId) =>
      requesterId == myUserId ? addresseeId : requesterId;

  /// True if [myUserId] is the one who must accept/decline — a pending
  /// request I RECEIVED rather than one I sent out.
  bool awaitingMyResponse(String myUserId) =>
      status == FriendshipStatus.pending && addresseeId == myUserId;

  bool sentByMe(String myUserId) =>
      status == FriendshipStatus.pending && requesterId == myUserId;
}

/// One row of a username search — the other user, plus any existing
/// friendship between them and the searching player (null = strangers).
class FriendSearchResult {
  final String userId;
  final String username;
  final Friendship? friendship;

  const FriendSearchResult({
    required this.userId,
    required this.username,
    this.friendship,
  });
}

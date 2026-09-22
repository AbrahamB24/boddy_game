import '../../../core/supabase/supabase_client.dart';
import '../models/activity.dart';

/// Friend activity feed — see supabase/migrations/0049_social_activity_feed.sql.
class ActivityService {
  String get _myId => supabase.auth.currentUser!.id;

  /// Writes one feed entry for MYSELF (the RLS insert policy only allows
  /// `auth.uid() = user_id`). [label] is a short free-text name for the
  /// event's subject (a species, a building) — see [FriendActivity.describe].
  Future<void> post(ActivityKind kind, {String? label}) async {
    try {
      await supabase.from('friend_activity').insert({
        'user_id': _myId,
        'kind': activityKindToString(kind),
        if (label != null) 'payload': {'label': label},
      });
    } catch (_) {
      // Best-effort: a missed feed post must never block the real action
      // (accepting a friend, winning a battle, upgrading a building) it's
      // reporting on.
    }
  }

  /// My own activity plus my accepted friends' — the feed itself.
  Future<List<FriendActivity>> loadFeed({int limit = 50}) async {
    final rows = await supabase
        .from('friend_activity')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(FriendActivity.fromMap)
        .toList();
  }
}

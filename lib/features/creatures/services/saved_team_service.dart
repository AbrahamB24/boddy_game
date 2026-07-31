import '../../../core/supabase/supabase_client.dart';
import '../models/saved_team.dart';

// CRUD for the player's saved battle rosters (`saved_teams`, RLS-scoped).
// Plain service, same style as CreatureService.
class SavedTeamService {
  static const _table = 'saved_teams';

  Future<List<SavedTeam>> loadOwn(String userId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('user_id', userId)
        .order('created_at');
    return (rows as List)
        .map((r) => SavedTeam.fromRow((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Inserts and returns the team with its DB-generated id.
  Future<SavedTeam> insert(SavedTeam team) async {
    final row = team.toRow()..remove('id'); // let the DB mint it
    return SavedTeam.fromRow(
      await supabase.from(_table).insert(row).select().single(),
    );
  }

  Future<void> update(SavedTeam team) async =>
      supabase.from(_table).update(team.toRow()).eq('id', team.id);

  Future<void> delete(String id) async =>
      supabase.from(_table).delete().eq('id', id);

  /// Clears the active flag on every team of [userId].
  ///
  /// Must run BEFORE activating another one: `saved_teams_one_active_per_user`
  /// is a partial unique index, so two active rows is a constraint violation,
  /// not a last-write-wins race.
  Future<void> clearActive(String userId) async => supabase
      .from(_table)
      .update({'is_active': false})
      .eq('user_id', userId)
      .eq('is_active', true);
}

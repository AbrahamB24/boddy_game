import '../../../core/supabase/supabase_client.dart';
import '../models/creature_instance.dart';

// CRUD for the player's own creatures (`creatures` table, RLS-scoped to the
// user). Plain service, same style as SettlementService.
class CreatureService {
  static const _table = 'creatures';

  Future<List<CreatureInstance>> loadOwn(String userId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('user_id', userId)
        .order('caught_at');
    return (rows as List)
        .map((r) => CreatureInstance.fromRow((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Inserts a new creature (catch, starter or hatched egg) and returns it
  /// with its DB-generated id.
  Future<CreatureInstance> insert(CreatureInstance creature) async {
    final row = await supabase
        .from(_table)
        .insert(creature.toRow())
        .select()
        .single();
    return CreatureInstance.fromRow(row);
  }

  /// Persists mutable fields (level/xp/stage/pools/nickname).
  Future<void> update(CreatureInstance creature) async {
    await supabase.from(_table).update(creature.toRow()).eq('id', creature.id);
  }

  /// Releases a creature permanently.
  Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }
}

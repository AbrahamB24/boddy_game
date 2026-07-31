import '../../../core/supabase/supabase_client.dart';
import '../models/expedition.dart';
import '../models/spot_state.dart';

// CRUD for the expedition system (RLS-scoped to the owner). Plain services,
// same style as CreatureService / BreedingService. Requires the
// supabase/migrations/0001_expeditions.sql migration to be applied; callers
// wrap loads in try/catch so a missing table degrades gracefully rather than
// crashing the rest of the game.
class ExpeditionService {
  static const _table = 'expeditions';

  Future<List<Expedition>> loadActive(String userId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('user_id', userId)
        .eq('state', ExpeditionState.active.name)
        .order('started_at');
    return (rows as List)
        .map((r) => Expedition.fromRow((r as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Expedition> insert(Expedition e) async {
    final row = await supabase.from(_table).insert(e.toRow()).select().single();
    return Expedition.fromRow(row);
  }

  /// Persists mutable fields — used to checkpoint capture-encounter progress
  /// (payload.done) so replaying/duplicating a find is impossible.
  Future<void> update(Expedition e) async {
    await supabase
        .from(_table)
        .update({'state': e.state.name, 'payload': e.payload})
        .eq('id', e.id);
  }

  /// Resolving or cancelling an expedition just removes its row — rewards are
  /// granted separately (like breeding hatch).
  Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }

  /// Dev-mode shortcut: make a timed expedition finish immediately.
  Future<void> finishNow(String id) async {
    await supabase
        .from(_table)
        .update({
          'started_at': DateTime.now()
              .subtract(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
          'duration_seconds': 0,
        })
        .eq('id', id);
  }
}

class SpotStateService {
  static const _table = 'resource_spot_states';

  Future<Map<String, SpotState>> loadOwn(String userId) async {
    final rows = await supabase.from(_table).select().eq('user_id', userId);
    final map = <String, SpotState>{};
    for (final r in rows as List) {
      final s = SpotState.fromRow((r as Map).cast<String, dynamic>());
      map[s.spotId] = s;
    }
    return map;
  }

  Future<void> upsert(String userId, SpotState state) async {
    await supabase.from(_table).upsert(state.toRow(userId));
  }
}

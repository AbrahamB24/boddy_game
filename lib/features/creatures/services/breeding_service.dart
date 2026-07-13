import '../../../core/supabase/supabase_client.dart';
import '../models/breeding_job.dart';

// CRUD for breeding_jobs (RLS-scoped to the owner). Plain service, same
// style as CreatureService.
class BreedingService {
  static const _table = 'breeding_jobs';

  Future<List<BreedingJob>> loadOwn(String userId) async {
    final rows = await supabase
        .from(_table)
        .select()
        .eq('user_id', userId)
        .order('ready_at');
    return (rows as List)
        .map((r) => BreedingJob.fromRow((r as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<BreedingJob> insert({
    required String userId,
    required String parentAId,
    required String parentBId,
    required String speciesId,
    required DateTime readyAt,
  }) async {
    final row = await supabase
        .from(_table)
        .insert({
          'user_id': userId,
          'parent_a': parentAId,
          'parent_b': parentBId,
          'species_id': speciesId,
          'ready_at': readyAt.toUtc().toIso8601String(),
        })
        .select()
        .single();
    return BreedingJob.fromRow(row);
  }

  /// Hatch and cancel both just remove the row (hatching inserts the child
  /// through CreatureService separately).
  Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }

  /// Dev-mode shortcut: finish a job immediately.
  Future<void> finishNow(String id) async {
    await supabase
        .from(_table)
        .update({'ready_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }
}

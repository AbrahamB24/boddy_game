import '../../../core/supabase/supabase_client.dart';
import '../models/breeding_job.dart';

String _statusName(BreedingStatus s) => switch (s) {
  BreedingStatus.breeding => 'breeding',
  BreedingStatus.egg => 'egg',
  BreedingStatus.hatching => 'hatching',
};

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

  /// Advances a job through its lifecycle (breeding → egg → hatching). Writes
  /// the new [status] and, for a timed stage, the recomputed [readyAt].
  ///
  /// [childBase]/[childSlope] are written when the egg is LAID — the moment the
  /// child stops depending on its parents (migration 0027). If those columns
  /// are not there yet the write is retried WITHOUT them: Postgrest rejects the
  /// whole row over one unknown column, and losing the status change would
  /// strand the job mid-lifecycle. The egg then hatches the old way, from the
  /// parents.
  Future<void> updateStatus(
    String id,
    BreedingStatus status, {
    DateTime? readyAt,
    Map<String, double>? childBase,
    Map<String, double>? childSlope,
  }) async {
    final patch = <String, dynamic>{'status': _statusName(status)};
    if (readyAt != null) patch['ready_at'] = readyAt.toUtc().toIso8601String();
    if (childBase != null) patch['child_base'] = childBase;
    if (childSlope != null) patch['child_slope'] = childSlope;
    try {
      await supabase.from(_table).update(patch).eq('id', id);
    } catch (_) {
      if (childBase == null && childSlope == null) rethrow;
      patch
        ..remove('child_base')
        ..remove('child_slope');
      await supabase.from(_table).update(patch).eq('id', id);
    }
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

import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/creature_instance.dart';

// CRUD for the player's own creatures (`creatures` table, RLS-scoped to the
// user). Plain service, same style as SettlementService.
class CreatureService {
  static const _table = 'creatures';

  /// Columns added by a migration that may not have run yet.
  ///
  /// Postgrest rejects the WHOLE write when it sees an unknown column
  /// ("Could not find the 'healing_until' column … PGRST204"), so shipping a
  /// new field without this makes every creature write fail — renaming,
  /// assigning, XP, healing, catching, all of it. The rest of the app already
  /// tolerates pre-migration columns this way (SettlementService.saveResources,
  /// saveDungeonMaxStage, loadIsDev …); creatures didn't, and it cost a
  /// playtest.
  static const _optionalColumns = ['healing_until', 'heal_queued_at'];

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
    final row = await _writeTolerantly(
      creature.toRow(),
      (r) => supabase.from(_table).insert(r).select().single(),
    );
    return CreatureInstance.fromRow(row);
  }

  /// Persists mutable fields (level/xp/stage/pools/nickname/healing).
  Future<void> update(CreatureInstance creature) async {
    await _writeTolerantly(
      creature.toRow(),
      (r) => supabase.from(_table).update(r).eq('id', creature.id),
    );
  }

  /// Releases a creature permanently.
  Future<void> delete(String id) async {
    await supabase.from(_table).delete().eq('id', id);
  }

  /// Runs [write], dropping ONLY the column a PGRST204 actually names and
  /// retrying — one at a time, because Postgrest reports the first unknown
  /// column and stops.
  ///
  /// IT USED TO DROP EVERY OPTIONAL COLUMN AT ONCE (fixed 2026-07-27). With a
  /// single entry in [_optionalColumns] that was the same thing; the moment a
  /// second one was added it stopped being: on a database that HAS
  /// `healing_until` but not yet `heal_queued_at`, one unknown column made
  /// every creature write throw the treatment timer away too. Nothing failed
  /// loudly — heals just quietly stopped persisting.
  Future<T> _writeTolerantly<T>(
    Map<String, dynamic> row,
    Future<T> Function(Map<String, dynamic>) write,
  ) async {
    var payload = row;
    final dropped = <String>[];
    // Bounded by the number of columns that MAY be missing: each pass removes
    // one, so it can neither loop forever nor swallow a real error.
    for (var attempt = 0; attempt <= _optionalColumns.length; attempt++) {
      try {
        return await write(payload);
      } catch (e) {
        final missing = _unknownColumn(e, payload.keys);
        if (missing == null) rethrow;
        dropped.add(missing);
        payload = Map.of(payload)..remove(missing);
        debugPrint(
          '[CreatureService] $missing is not migrated yet — saving without it. '
          'Run supabase/migrations.',
        );
      }
    }
    throw StateError('creature write failed after dropping $dropped');
  }

  /// The optional column this error names, or null when it is a real failure.
  ///
  /// Matches on the column NAME rather than the PGRST204 code alone, so a
  /// genuinely broken write still throws instead of being silently retried with
  /// fields stripped. Only considers columns still IN the payload, so a stale
  /// message can't send the loop round again on something already dropped.
  String? _unknownColumn(Object e, Iterable<String> present) {
    final msg = e.toString();
    if (!msg.contains('PGRST204')) return null;
    for (final c in _optionalColumns) {
      if (msg.contains(c) && present.contains(c)) return c;
    }
    return null;
  }
}

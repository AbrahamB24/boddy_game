import '../../../core/supabase/supabase_client.dart';
import '../models/legendary_lair.dart';

/// Supabase access for the legendary lairs (migration 0068). Every write is a
/// server function: the other player's trainers and the payout must not be
/// forgeable from this client.
class LairService {
  Future<List<LegendaryLair>> loadOwn(String userId) async {
    final rows = await supabase
        .from('legendary_lairs')
        .select()
        .eq('user_id', userId);
    final lairs = [
      for (final r in rows as List) (r as Map).cast<String, dynamic>(),
    ];
    final ids = lairs.map((r) => r['id'] as String).toList();
    final trainerRows = ids.isEmpty
        ? const []
        : await supabase.from('lair_trainers').select().inFilter('lair_id', ids);
    final byLair = <String, List<LairTrainer>>{};
    for (final t in trainerRows) {
      final m = (t as Map).cast<String, dynamic>();
      byLair
          .putIfAbsent(m['lair_id'] as String, () => [])
          .add(LairTrainer.fromRow(m));
    }
    return [
      for (final r in lairs)
        LegendaryLair.fromRow(
          r,
          trainers: (byLair[r['id']] ?? [])
            ..sort((a, b) => a.slot.compareTo(b.slot)),
        ),
    ];
  }

  /// Creature ids of mine that are currently somebody's trainer.
  Future<Set<String>> myTrainerCreatureIds(String userId) async {
    final rows = await supabase
        .from('lair_trainers')
        .select('trainer_creature_id')
        .eq('trainer_user_id', userId);
    return {
      for (final r in rows as List) (r as Map)['trainer_creature_id'] as String,
    };
  }

  Future<void> ensure(String creatureId, String speciesId, int level) =>
      supabase.rpc(
        'lair_ensure',
        params: {
          'p_creature': creatureId,
          'p_species': speciesId,
          'p_level': level,
        },
      );

  Future<void> startUpgrade({
    required String lairId,
    required double workSeconds,
    required String? good,
    required double amount,
    required double gold,
    required List<double> shares,
  }) => supabase.rpc(
    'lair_start_upgrade',
    params: {
      'p_lair': lairId,
      'p_work_seconds': workSeconds,
      'p_good': good,
      'p_amount': amount,
      'p_gold': gold,
      'p_shares': shares,
    },
  );

  Future<void> join(String lairId, String creatureId, double effect) =>
      supabase.rpc(
        'lair_join',
        params: {
          'p_lair': lairId,
          'p_creature': creatureId,
          'p_effect': effect,
        },
      );

  Future<void> refresh(String lairId) =>
      supabase.rpc('lair_refresh', params: {'p_lair': lairId});

  /// What the server owes this player; each row is paid exactly once.
  Future<List<({String? good, double amount, double gold})>>
  claimRewards() async {
    final rows = await supabase.rpc('lair_claim_rewards');
    return [
      for (final r in (rows as List? ?? const []))
        (
          good: (r as Map)['good'] as String?,
          amount: (r['amount'] as num?)?.toDouble() ?? 0,
          gold: (r['gold'] as num?)?.toDouble() ?? 0,
        ),
    ];
  }

  Future<List<OpenLairSlot>> openSlots() async {
    final rows = await supabase.rpc('lair_open_slots');
    return [
      for (final r in (rows as List? ?? const []))
        OpenLairSlot.fromRow((r as Map).cast<String, dynamic>()),
    ];
  }
}

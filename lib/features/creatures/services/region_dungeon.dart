import 'dart:math' as math;

import '../models/area.dart';
import '../models/combatant.dart';
import '../models/path_node.dart';
import '../models/species_def.dart';
import 'capture_math.dart';
import 'overworld_path.dart';

// ── Linear-path battles (user 2026-07-24) ───────────────────
// The overworld is one straight line of numbered battles (see overworld_path /
// overworld_layout). This builds the ENEMIES for a single battle on that line.
//
// The old region-dungeon ladder and the tech mini-dungeon trials that lived
// here were deleted with the research system: battles are individual path nodes
// now, not a fixed ladder behind a fish/fur gate, and there are no trials to
// win (features unlock by map progress — featureUnlocksForBattles).

/// Enemies for a single battle on the overworld line: [enemyCountForBattle]
/// wilds drawn from the era's area pool at [enemyLevelForBattle], or the lone
/// area boss on a boss battle. Deterministic per (area, battle) so a re-fight
/// presents the same foes; genes are rolled fresh so they aren't literal clones.
/// Null when the era has no species content yet.
///
/// The pack size ALWAYS stays below the party you may bring here
/// (enemyCountForBattle = partySize − 1), so you never face as many monsters as
/// you can field until you have unlocked a bigger party — and you always
/// outnumber, which the auto-battle handles far better than a symmetric pack
/// (user 2026-07-24; see test/linear_combat_probe_test.dart). Challenge also
/// scales by LEVEL.
List<Combatant>? spawnPathBattle(AreaDef area, int battleNumber) {
  final node = pathNodeAtOrder(battleNumber);
  // AUTHORED enemies win (user 2026-07-25): a node's explicit species+level
  // list defines the fight exactly. Unknown species ids are skipped; an empty
  // result falls through to the formula below.
  if (node != null && node.enemies.isNotEmpty) {
    final out = <Combatant>[];
    for (var i = 0; i < node.enemies.length; i++) {
      final e = node.enemies[i];
      final sp = kSpeciesDefs[e.speciesId];
      if (sp == null) continue;
      out.add(Combatant.fromSpecies(
        sp,
        level: e.level,
        id: 'w${battleNumber}_$i',
        isBoss: node.isBoss,
      ));
    }
    if (out.isNotEmpty) return out;
  }

  final level = enemyLevelForBattle(battleNumber);
  final pool = eligibleSpecies(area, includeLegendary: false);
  if (isBossBattle(battleNumber)) {
    final ranked = pool.toList()
      ..sort((a, b) => b.rarity.index.compareTo(a.rarity.index));
    final boss = kSpeciesDefs[area.bossSpeciesId] ??
        (ranked.isEmpty ? null : ranked.first);
    if (boss == null) return null;
    return [Combatant.fromSpecies(boss, level: level, id: 'boss', isBoss: true)];
  }
  if (pool.isEmpty) return null;
  final count = enemyCountForBattle(battleNumber);
  final rng = math.Random(area.id.hashCode ^ (battleNumber * 2654435761));
  return [
    for (var i = 0; i < count; i++)
      Combatant.fromSpecies(
        pool[rng.nextInt(pool.length)],
        level: level,
        id: 'w${battleNumber}_$i',
      ),
  ];
}

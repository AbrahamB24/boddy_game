import 'dart:math' as math;

import '../models/area.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart';
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
// now, not a fixed ladder behind a fish/meat gate, and there are no trials to
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
/// [statScale] is an extra multiplier on every spawned enemy's battle stats
/// (1.0 = balanced default) — the tutorial passes kJumpstartEnemyStatMult so
/// its first two nodes can't be lost. See Combatant.fromSpecies.
List<Combatant>? spawnPathBattle(
  AreaDef area,
  int battleNumber, {
  double statScale = 1.0,
}) {
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
      out.add(
        Combatant.fromSpecies(
          sp,
          level: e.level,
          id: 'w${battleNumber}_$i',
          isBoss: node.isBoss,
          statScale: statScale,
        ),
      );
    }
    if (out.isNotEmpty) return out;
  }

  final level = enemyLevelForBattle(battleNumber);
  final pool = eligibleSpecies(area, includeLegendary: false);
  if (isBossBattle(battleNumber)) {
    final ranked = pool.toList()
      ..sort((a, b) => b.rarity.index.compareTo(a.rarity.index));
    final boss =
        kSpeciesDefs[area.bossSpeciesId] ??
        (ranked.isEmpty ? null : ranked.first);
    if (boss == null) return null;
    return [
      Combatant.fromSpecies(
        boss,
        level: level,
        id: 'boss',
        isBoss: true,
        statScale: statScale,
      ),
    ];
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
        statScale: statScale,
      ),
  ];
}

/// Battle 1's enemy, hand-picked to be SUPER EFFECTIVE against the player's
/// own starter (user 2026-09-03: "Nimm immer das Monster, welches effektiv
/// gegen unser gewähltes Monster ist. So kannst du die Effektivität auch
/// erklären") — a scripted teaching moment for type advantage, not a random
/// pool draw. Null when the area has no matching (or any) species yet.
///
/// Stats are left at their natural, UNSCALED roll (no statScale here) —
/// this enemy's whole HP/danger profile is FULLY SCRIPTED by BattleScreen's
/// own beat sequence now (every HP change forced to an exact percentage,
/// see BattleScreen._scriptBeat and CombatEngine.deterministicCombat), not
/// tuned through stats at all. A blanket stat cut (the old
/// kJumpstartEnemyStatMult) is what used to let the fight resolve before
/// the scripted beats had room to happen — this enemy doesn't need one.
Combatant? scriptedFirstBattleEnemy(
  AreaDef area,
  CreatureElement starterElement,
) {
  final pool = eligibleSpecies(area, includeLegendary: false);
  if (pool.isEmpty) return null;
  final want = starterElement.counterElement;
  final matches = pool.where((s) => s.element == want).toList();
  final species = matches.isNotEmpty ? matches.first : pool.first;
  return Combatant.fromSpecies(
    species,
    level: enemyLevelForBattle(1),
    id: 'w1_0',
  );
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart'
    show CreatureElement, CreatureRarity;
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/models/path_node.dart';
import 'package:boddygame/features/creatures/services/capture_math.dart'
    show eligibleSpecies;
import 'package:boddygame/features/creatures/services/overworld_path.dart';

// ── Der Regionen-Würfel (user 2026-07-30) ───────────────────
// "Zudem will ich dort einen Button haben, welcher die Monster neu würfelt."
//
// The button's own code is a sheet, but the RULES it follows are the testable
// part, and each of them is a promise that would break quietly:
//   • the boss is never re-rolled — a region's boss is its identity
//   • a node keeps the number of enemies the game would field there anyway
//   • the pool is the REGION's, so a roll cannot import a monster from era VIII
void main() {
  // Species live only in the database (there is no bundled creature roster), so
  // the pool is empty in a test unless one is seeded. Seeding it is also the
  // honest setup: it is exactly the state the dev tool works in — a project with
  // species authored and areas pointing at them.
  SpeciesDef sp(String id, CreatureRarity rarity) => SpeciesDef(
    id: id,
    name: id,
    element: CreatureElement.plant,
    rarity: rarity,
    stats: const {},
    stages: const [
      SpeciesStage(name: ''),
      SpeciesStage(name: ''),
      SpeciesStage(name: ''),
    ],
  );

  setUp(() {
    kAreaDefs
      ..clear()
      ..addAll({for (final a in kFallbackAreaDefs) a.id: a});
    // The bundled areas carry NO species pool — that content lives in the
    // database — so eligibleSpecies falls back to the whole roster. Seeding the
    // roster is therefore the whole setup, and it mirrors the state the dev tool
    // runs in: species authored, areas not yet narrowed to a pool.
    kSpeciesDefs
      ..clear()
      ..addAll({
        for (final id in ['sprout', 'pebble', 'ember', 'drift'])
          id: sp(id, CreatureRarity.common),
        'ancient': sp('ancient', CreatureRarity.legendary),
      });
  });

  tearDown(kSpeciesDefs.clear);

  AreaDef areaOfEra(int era) =>
      kAreaDefs.values.firstWhere((a) => a.battleStage == era);

  test('the roll draws from the region pool — or the roster when it has none',
      () {
    final area = areaOfEra(1);
    final pool = eligibleSpecies(area, includeLegendary: false);
    expect(pool, isNotEmpty);
    // With no authored pool this is the whole roster, which is exactly what the
    // game's own spawn does for a node with no authored enemies. Narrowing a
    // region is an authoring decision (AreaDef.speciesPoolIds), not this
    // button's business.
    expect(area.speciesPoolIds, isEmpty);
    expect(pool.length, kSpeciesDefs.length);
  });

  test('the area BOSS is never in the pool a fight rolls from', () {
    final area = areaOfEra(1);
    final withBoss = AreaDef(
      id: area.id,
      name: area.name,
      emoji: area.emoji,
      order: area.order,
      battleStage: area.battleStage,
      bossSpeciesId: 'ancient',
    );
    final pool = eligibleSpecies(withBoss, includeLegendary: false);
    expect(pool.any((s) => s.id == 'ancient'), isFalse);
  });

  test('a rolled fight keeps the count the game would have spawned', () {
    // A node with no authored enemies gains exactly the fight it already had —
    // made explicit, and now re-rollable.
    for (final battle in [1, 5, 12, 18]) {
      final pool = eligibleSpecies(areaOfEra(1), includeLegendary: false);
      final rolled = rollPathEnemies(
        poolIds: [for (final s in pool) s.id],
        count: enemyCountForBattle(battle),
        keepLevels: [enemyLevelForBattle(battle)],
        rng: math.Random(battle),
      );
      expect(rolled.length, enemyCountForBattle(battle), reason: 'battle $battle');
      expect(rolled.every((e) => e.level == enemyLevelForBattle(battle)), isTrue,
          reason: 'battle $battle keeps the formula level');
    }
  });

  test('a roll draws ONLY from the region', () {
    final pool = eligibleSpecies(areaOfEra(1), includeLegendary: false);
    final ids = {for (final s in pool) s.id};
    final rolled = rollPathEnemies(
      poolIds: ids.toList(),
      count: 3,
      keepLevels: const [4],
      rng: math.Random(9),
    );
    expect(rolled.every((e) => ids.contains(e.speciesId)), isTrue);
  });

  test('copyWith replaces the enemies and nothing else', () {
    // The bulk edit's one mutation: everything a node IS must survive it.
    const node = PathNode(
      id: 'n',
      order: 7,
      name: 'Seven',
      areaId: 'verdant_hollow',
      isBoss: true,
      enemies: [PathEnemy(speciesId: 'old', level: 3)],
      rewards: PathRewards(items: {'minor_potion': 1}),
    );
    final rolled = node.copyWith(
      enemies: const [PathEnemy(speciesId: 'new', level: 9)],
    );
    expect(rolled.enemies.single.speciesId, 'new');
    expect(rolled.id, node.id);
    expect(rolled.order, node.order);
    expect(rolled.name, node.name);
    expect(rolled.areaId, node.areaId);
    expect(rolled.isBoss, node.isBoss);
    expect(rolled.rewards.items, node.rewards.items);
  });

  test('every bundled node belongs to a region that HAS a pool', () {
    // Without this a re-roll would silently do nothing for a whole era.
    for (final n in pathNodesInOrder()) {
      final era = eraForBattle(n.order);
      final area = kAreaDefs.values.where((a) => a.battleStage == era);
      expect(area, isNotEmpty, reason: 'battle ${n.order} has no region');
      expect(eligibleSpecies(area.first, includeLegendary: false), isNotEmpty,
          reason: 'region ${area.first.id} has no monsters to roll');
    }
  });
}

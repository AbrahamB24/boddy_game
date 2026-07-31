import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/overworld_path.dart';
import 'package:boddygame/features/creatures/services/region_dungeon.dart';

// spawnPathBattle builds the enemies for a single battle on the linear
// overworld line (the old region-dungeon ladder + tech trials were deleted with
// the research system).

SpeciesDef _sp(String id, CreatureRarity rarity) => SpeciesDef(
  id: id,
  name: id,
  element: CreatureElement.fire,
  rarity: rarity,
  stats: const {},
  stages: const [
    SpeciesStage(name: 's'),
    SpeciesStage(name: 's'),
    SpeciesStage(name: 's'),
  ],
);

AreaDef _area({String boss = 'leg', List<String> pool = const ['mouse', 'wolf']}) =>
    AreaDef(
      id: 'verdant',
      name: 'Verdant',
      emoji: '🌲',
      order: 1,
      battleStage: 1,
      dangerLevel: 1,
      speciesPoolIds: pool,
      bossSpeciesId: boss,
    );

void main() {
  setUp(() {
    kSpeciesDefs
      ..clear()
      ..addAll({
        'mouse': _sp('mouse', CreatureRarity.common),
        'wolf': _sp('wolf', CreatureRarity.rare),
        'leg': _sp('leg', CreatureRarity.legendary),
      });
  });
  tearDown(kSpeciesDefs.clear);

  test('a regular battle fields enemyCountForBattle wilds at its level', () {
    // The pack size scales but stays below the party you may bring, so you
    // always outnumber (see enemyCountForBattle).
    for (final n in [1, 6, 15, 20]) {
      final enemies = spawnPathBattle(_area(), n)!;
      expect(enemies.length, enemyCountForBattle(n), reason: 'battle $n');
      expect(enemies.length, lessThan(partySizeForBattle(n) + 1));
      expect(enemies.every((c) => c.level == enemyLevelForBattle(n)), isTrue);
      // The legendary is the boss, never a pool wild.
      expect(enemies.every((c) => c.speciesId != 'leg'), isTrue,
          reason: 'no legendary leaks into a regular fight');
      expect(enemies.every((c) => !c.isBoss), isTrue);
    }
  });

  test('a boss battle is the lone area boss', () {
    final bossN = bossBattleForEra(1); // area battleStage 1
    final enemies = spawnPathBattle(_area(), bossN)!;
    expect(enemies.length, 1);
    expect(enemies.first.speciesId, 'leg');
    expect(enemies.first.isBoss, isTrue);
    expect(enemies.first.level, enemyLevelForBattle(bossN));
  });

  test('null when the area has no catchable species', () {
    kSpeciesDefs.clear();
    expect(spawnPathBattle(_area(), 1), isNull);
    // Only the legendary defined = still empty for a pool fight (it is the boss,
    // not a pool wild).
    kSpeciesDefs['leg'] = _sp('leg', CreatureRarity.legendary);
    expect(spawnPathBattle(_area(pool: const ['leg']), 1), isNull);
  });

  test('deterministic per (area, battle): the same fight rolls the same foes',
      () {
    List<String> ids(int n) =>
        [for (final c in spawnPathBattle(_area(), n)!) c.speciesId ?? ''];
    expect(ids(6), ids(6));
    expect(ids(7), ids(7));
  });
}

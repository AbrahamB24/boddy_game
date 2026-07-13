import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/services/catch_logic.dart';

Combatant wild(CreatureRarity rarity, {int hp = 50, int? currentHp}) {
  final c = Combatant(
    id: 'w',
    speciesId: 'test_species', // not in kSpeciesDefs -> speciesRate 1.0
    name: 'Wild',
    element: CreatureElement.plant,
    rarity: rarity,
    isPlayerSide: false,
    level: 10,
    stats: {CreatureStat.hp: hp},
    abilities: const [],
  );
  if (currentHp != null) c.hp = currentHp;
  return c;
}

Combatant catcher(int catchRate, {bool ko = false}) {
  final c = Combatant(
    id: 'c$catchRate',
    name: 'Catcher',
    element: CreatureElement.fire,
    rarity: CreatureRarity.common,
    isPlayerSide: true,
    level: 10,
    stats: {CreatureStat.hp: 50, CreatureStat.catchRate: catchRate},
    abilities: const [],
  );
  if (ko) c.hp = 0;
  return c;
}

void main() {
  test('rarer targets are strictly harder to catch', () {
    final team = [catcher(10)];
    final chances = [
      for (final r in CreatureRarity.values)
        catchChance(target: wild(r), team: team),
    ];
    for (var i = 1; i < chances.length; i++) {
      expect(chances[i], lessThan(chances[i - 1]));
    }
  });

  test('higher Fangwert raises the chance; K.O. catchers do not count', () {
    final low = catchChance(
      target: wild(CreatureRarity.rare),
      team: [catcher(5)],
    );
    final high = catchChance(
      target: wild(CreatureRarity.rare),
      team: [catcher(200)],
    );
    expect(high, greaterThan(low));

    // The best catcher being K.O. means its Fangwert is ignored.
    final withKo = catchChance(
      target: wild(CreatureRarity.rare),
      team: [catcher(5), catcher(200, ko: true)],
    );
    expect(withKo, low);
  });

  test('lower target HP raises the chance (HP_Term)', () {
    final full = catchChance(
      target: wild(CreatureRarity.common, hp: 100, currentHp: 100),
      team: [catcher(20)],
    );
    final nearDead = catchChance(
      target: wild(CreatureRarity.common, hp: 100, currentHp: 1),
      team: [catcher(20)],
    );
    expect(nearDead, greaterThan(full));
  });

  test('chance is always within [0.02, 1.0]', () {
    final impossible = catchChance(
      target: wild(CreatureRarity.legendary, hp: 100, currentHp: 100),
      team: [catcher(0)],
    );
    final easiest = catchChance(
      target: wild(CreatureRarity.common, hp: 100, currentHp: 1),
      team: [catcher(9999)],
    );
    expect(impossible, greaterThanOrEqualTo(0.02));
    expect(impossible, lessThanOrEqualTo(1.0));
    expect(easiest, lessThanOrEqualTo(1.0));
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/path_node.dart';
import 'package:boddygame/features/creatures/services/battle_rewards.dart';
import 'package:boddygame/features/creatures/services/overworld_path.dart';

// battleRewardsFor lists what CLEARING a battle unlocks — previewed before the
// fight and celebrated after it.
void main() {
  test('the first battle unlocks the Healing Hut, no party line', () {
    final r = battleRewardsFor(1);
    expect(r.any((l) => l.text.contains('Healing')), isTrue);
    // Party doesn't grow at battle 1 (it's the opener).
    expect(r.any((l) => l.emoji == '👥'), isFalse);
  });

  test('battle 6 grants the second party slot', () {
    final r = battleRewardsFor(6);
    expect(r.any((l) => l.emoji == '👥' && l.text.contains('2')), isTrue,
        reason: 'partySizeForBattle 5→6 goes 1→2');
  });

  test('a plain battle lists its loot and NOTHING else', () {
    // Battle 17 has no building, no party step and no legendary. It used to
    // have no lines at all — every node pays a resource package since
    // 2026-07-30 (user: "die Belohnung einmal für alle Knoten verteilen"), so
    // what the test guards now is that a plain fight does not invent MILESTONE
    // lines it has not earned.
    final r = battleRewardsFor(17);
    expect(r, isNotEmpty, reason: 'every node pays something now');
    for (final line in r) {
      expect(line.emoji, isNot('🏛️'), reason: 'no building here');
      expect(line.emoji, isNot('👥'), reason: 'party size is unchanged');
      expect(line.emoji, isNot('👑'), reason: 'not a boss');
    }
  });

  test('an era boss lists the legendary + next region', () {
    final r = battleRewardsFor(bossBattleForEra(1));
    expect(r.any((l) => l.emoji == '👑'), isTrue);
  });

  test('battle 11 unlocks the Trade Center', () {
    expect(battleRewardsFor(11).any((l) => l.text.contains('Trade Center')),
        isTrue);
  });

  test('authored item loot is previewed with the item name and count', () {
    kPathNodes['node_2'] = const PathNode(
      id: 'node_2',
      order: 2,
      name: 'Battle 2',
      rewards: PathRewards(items: {'minor_potion': 2}),
    );
    addTearDown(() => kPathNodes['node_2'] = kFallbackPathNodes['node_2']!);
    final r = battleRewardsFor(2);
    expect(r.any((l) => l.text == 'Minor Potion ×2'), isTrue);
  });
}

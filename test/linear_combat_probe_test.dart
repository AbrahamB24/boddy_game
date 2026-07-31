import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/services/combat_monte_carlo.dart';
import 'package:boddygame/features/creatures/services/overworld_path.dart';

// Informational probe (like the combat_monte_carlo anchor print): simulates the
// LINEAR-PATH battles so the enemyLevelForBattle curve can be eyeballed before a
// device playtest. Structural asserts only — never fails on tuning.
//
// KEY FINDING (2026-07-24): the CTB auto-battle is BIMODAL — one enemy is
// reliably winnable (~100%), and even a symmetric pack collapses (2v2 ~60%,
// 3v3 0%). So the pack size is GATED below the party (enemyCountForBattle =
// partySize − 1): the player always OUTNUMBERS, which the auto-battle handles
// far better, AND is never confronted with as many foes as they can field
// before unlocking a bigger party. These numbers assume the player fights near
// the enemy level (they level as they climb) with the epic starter leading.
void main() {
  test('linear battle curve — win% / actions / HP loss (informational)', () {
    // ignore: avoid_print
    print('\n── Linear path battles (foes gated below party, team ≈ level) ──');
    for (final n in [1, 3, 5, 6, 10, 15, 18, 19, 20, 26]) {
      final lvl = enemyLevelForBattle(n);
      final size = partySizeForBattle(n);
      final foes = isBossBattle(n) ? 1 : enemyCountForBattle(n);
      final boss = isBossBattle(n);
      for (final enemyRarity in [CreatureRarity.common, CreatureRarity.epic]) {
        final r = simulateStandardMatchup(
          teamLevel: lvl,
          wildLevel: lvl,
          teamSize: size,
          enemyCount: foes,
          boss: boss,
          teamRarity: CreatureRarity.epic, // the epic starter leads
          enemyRarity: enemyRarity,
        );
        // ignore: avoid_print
        print('battle ${n.toString().padLeft(2)} '
            '${boss ? 'BOSS' : '${size}v$foes'} Lv$lvl '
            'vs ${enemyRarity.name.padRight(6)} → '
            '${(r.winRate * 100).round()}% wins · '
            '${r.medianPlayerActions.toStringAsFixed(0)} actions · '
            '${(r.avgTeamHpLossPct * 100).round()}% HP');
      }
    }

    // The opening must be beatable by the level-1 starter against a plain wild.
    final b1 = simulateStandardMatchup(
      teamLevel: 1,
      wildLevel: enemyLevelForBattle(1),
      teamSize: 1,
      enemyCount: 1,
      teamRarity: CreatureRarity.epic,
      enemyRarity: CreatureRarity.common,
    );
    expect(b1.winRate, greaterThan(0.5),
        reason: 'battle 1 vs a common wild must be winnable by the starter');
  });
}

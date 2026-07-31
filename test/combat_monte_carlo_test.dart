import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/services/combat_monte_carlo.dart';
import 'package:boddygame/features/creatures/services/stat_budget.dart';

void main() {
  group('standardCombatant', () {
    test('every archetype spends the same combat budget', () {
      // Weights are RELATIVE (distribution normalises on the sum), so the
      // invariant is that every archetype's sum is EQUAL — not a specific
      // constant. catchRate's flat 20 raised each row 180 → 200 (2026-07-22).
      final sums = [
        for (final e in kCombatArchetypeWeights.entries)
          e.value.values.reduce((a, b) => a + b),
      ];
      for (final sum in sums) {
        expect(sum, closeTo(sums.first, 1e-9),
            reason: 'every archetype must spend the same relative budget');
      }
      // And every archetype now carries the flat catch weight.
      for (final e in kCombatArchetypeWeights.entries) {
        expect(e.value[CreatureStat.catchRate], 20, reason: '${e.key}');
      }
    });

    test('stats grow linearly with level and scale with budgetMult', () {
      final l1 = standardCombatant(level: 1);
      final l31 = standardCombatant(level: 31); // +100% at 1/30 per level
      expect(
        l31.stat(CreatureStat.hp),
        closeTo(l1.stat(CreatureStat.hp) * 2, 1),
      );
      final boss = standardCombatant(level: 1, budgetMult: 1.2);
      expect(
        boss.stat(CreatureStat.attack),
        closeTo(l1.stat(CreatureStat.attack) * 1.2, 1),
      );
    });
  });

  group('simulateMatchup', () {
    test('deterministic for a fixed seed', () {
      MatchupResult run() => simulateStandardMatchup(
        teamLevel: 10,
        wildLevel: 10,
        runs: 40,
        seed: 7,
      );
      final a = run();
      final b = run();
      expect(a.winRate, b.winRate);
      expect(a.medianPlayerActions, b.medianPlayerActions);
      expect(a.avgTeamHpLossPct, b.avgTeamHpLossPct);
    });

    test('higher-level team wins more and loses less HP', () {
      final weaker = simulateStandardMatchup(
        teamLevel: 5,
        wildLevel: 13,
        runs: 80,
      );
      final stronger = simulateStandardMatchup(
        teamLevel: 13,
        wildLevel: 13,
        runs: 80,
      );
      expect(stronger.winRate, greaterThanOrEqualTo(weaker.winRate));
      expect(
        stronger.avgTeamHpLossPct,
        lessThanOrEqualTo(weaker.avgTeamHpLossPct),
      );
      expect(stronger.winRate, greaterThan(0.5)); // 3v1 at equal level
    });

    test('probe: anchor matrix (informational print, structural asserts)', () {
      // Prints the current balance state against the docs/balancing.md
      // anchors — the numbers are REPORTED, not asserted, so tuning the
      // budgets never breaks CI. Combat is 1v1 (one active per side), so only
      // the single-wild (3v1 capture) matchup is probed — the old symmetric
      // 3v3 pack anchor was deleted (user 2026-07-17).
      for (final offset in [0, -8]) {
        for (final stage in [1, 5, 9]) {
          final wild = 5 + (stage - 1) * 8;
          final r = simulateStandardMatchup(
            teamLevel: (wild + offset).clamp(1, 75),
            wildLevel: wild,
            enemyCount: 1,
            runs: 120,
          );
          // ignore: avoid_print
          print(
            '3v1 S$stage Lv$wild offset $offset → '
            '${(r.winRate * 100).toStringAsFixed(0)}% wins · '
            '${r.medianPlayerActions.toStringAsFixed(1)} actions · '
            '${(r.avgTeamHpLossPct * 100).toStringAsFixed(0)}% HP loss',
          );
          expect(r.winRate, inInclusiveRange(0, 1));
          expect(r.medianPlayerActions, greaterThan(0));
        }
      }
    });
  });
}

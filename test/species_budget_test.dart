import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_balance.dart';
import 'package:boddygame/features/creatures/services/stat_budget.dart';

// Global species-BUDGET config (user 2026-07-24): per rarity, per category
// (combat/civil) — base + growth budgets, base + growth LIMITS, and catch rate.
void main() {
  tearDown(() => kSpeciesBalance = defaultSpeciesBalance());

  test('the default reproduces the historical per-rarity totals + split', () {
    expect(budgetBaseTotal(rarity: CreatureRarity.common), closeTo(270, 1e-9));
    expect(
      budgetBaseTotal(rarity: CreatureRarity.legendary),
      closeTo(290, 1e-9),
    );
    final b = defaultBudget(rarity: CreatureRarity.rare);
    expect(b.combatBase + b.workBase, closeTo(280, 1e-9));
    expect(b.combatBase / (b.combatBase + b.workBase), closeTo(180 / 370, 1e-9));
    expect(b.combatGrowth, closeTo(b.combatBase / 30, 1e-9));
    expect(b.workGrowth, closeTo(b.workBase / 30, 1e-9));
  });

  test('catch rate comes from the config, per rarity', () {
    expect(catchRateForRarity(CreatureRarity.common), 1.2);
    expect(catchRateForRarity(CreatureRarity.legendary), 0.6);
  });

  test('config round-trips and drives budget, growth and catch', () {
    final custom = SpeciesBalance(
      byRarity: {
        for (final r in CreatureRarity.values)
          r: const RarityConfig(
            combatBase: 100,
            workBase: 200,
            combatGrowth: 5,
            workGrowth: 6,
            combatMaxBase: 40,
            workMaxBase: 50,
            catchRate: 0.8,
          ),
      },
    );
    final restored = SpeciesBalance.fromJson(custom.toJson());
    expect(restored.of(CreatureRarity.common).combatBase, 100);
    expect(restored.of(CreatureRarity.common).workBase, 200);
    expect(restored.of(CreatureRarity.common).catchRate, 0.8);

    kSpeciesBalance = restored;
    expect(budgetBaseTotal(rarity: CreatureRarity.common), 300);
    expect(budgetGrowthTotal(rarity: CreatureRarity.common), 11);
    final b = defaultBudget(rarity: CreatureRarity.common);
    expect(b.combatBase, 100);
    expect(b.workBase, 200);
    expect(b.combatGrowth, 5);
    expect(b.workGrowth, 6);
    expect(catchRateForRarity(CreatureRarity.common), 0.8);
  });

  test('per-category caps clamp base and growth (combat vs civil)', () {
    kSpeciesBalance = SpeciesBalance(
      byRarity: {
        for (final r in CreatureRarity.values)
          r: const RarityConfig(
            combatBase: 180,
            workBase: 190,
            combatGrowth: 6,
            workGrowth: 6,
            combatMaxBase: 40,
            workMaxBase: 30,
            combatMaxGrowth: 2,
            workMaxGrowth: 1.5,
            catchRate: 1,
          ),
      },
    );
    const rare = CreatureRarity.rare;
    // hp is a combat stat, crafting is a civil (work) stat.
    expect(kSpeciesBalance.clampBase(CreatureStat.hp, rare, 100), 40);
    expect(kSpeciesBalance.clampBase(CreatureStat.crafting, rare, 100), 30);
    expect(kSpeciesBalance.clampGrowth(CreatureStat.hp, rare, 9), 2);
    expect(kSpeciesBalance.clampGrowth(CreatureStat.crafting, rare, 9), 1.5);
    expect(statBaseMax(CreatureStat.hp, rare), 40);
    expect(statBaseMax(CreatureStat.crafting, rare), 30);
  });

  test('an unset cap leaves values untouched', () {
    // The DEFAULT config carries real caps since 2026-07-29, so "unset" has
    // to be built explicitly — 0 still means "no cap", and that is the
    // behaviour this pins.
    const c = CreatureRarity.common;
    kSpeciesBalance = kSpeciesBalance.copyWith({
      c: kSpeciesBalance.of(c).copyWith(
        combatMaxBase: 0,
        workMaxBase: 0,
        combatMaxGrowth: 0,
        workMaxGrowth: 0,
      ),
    });
    expect(kSpeciesBalance.of(c).maxBaseFor(CreatureStat.hp), isNull);
    expect(kSpeciesBalance.clampBase(CreatureStat.hp, c, 100), 100);
    expect(kSpeciesBalance.clampGrowth(CreatureStat.hp, c, 9), 9);
  });
}

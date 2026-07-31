import 'dart:math' as math;

import '../models/combatant.dart';
import '../models/creature_enums.dart';
import 'combat_engine.dart';
import 'stat_budget.dart';

// Combat Monte-Carlo (balancing tool 2) — drives the REAL CombatEngine
// headless, N seeded auto-battles per matchup, and reports the metrics the
// docs/balancing.md combat anchors are stated in: win rate, median player
// actions, average team HP loss. Standard combatants are built straight from
// the §3 stat-budget framework so the budgets get validated against the
// anchors (equal level: ≥95% wins in ~4–6 actions; +8 levels ≈ next stage:
// ~50%).

/// Sum of a combat archetype's weights (they're RELATIVE — scaled onto the real
/// per-rarity combat base). All archetypes sum to the same value, so the
/// species editor's validator asserts against this.
const double kStandardCombatBudget = kCombatBudgetTarget;

/// Budget growth per level (linear, like StatCurve.growth) — a flat 1/30 across
/// rarities now (see stat_budget.dart).
const double kBudgetGrowthPerLevel = kGrowthPerLevelTarget;

/// A budget-standard combatant: the archetype's combat spread scaled onto the
/// real [rarity] combat base (defaultBudget), × the boss/wild [budgetMult],
/// grown linearly to [level] the same way a species' stat curve does. No
/// abilities — auto-battles run on basic attacks, the baseline the anchors are
/// defined against. Neutral element (fire vs fire = 1.0 in the matrix).
Combatant standardCombatant({
  required int level,
  CombatArchetype archetype = CombatArchetype.allrounder,
  CreatureRarity rarity = CreatureRarity.common,
  double budgetMult = 1.0,
  bool isPlayerSide = true,
  bool isBoss = false,
  String id = 'std',
}) {
  final weights = kCombatArchetypeWeights[archetype]!;
  final weightSum = weights.values.reduce((a, b) => a + b);
  // The rarity's real combat base — the weights only decide how it's split.
  final combatBase = defaultBudget(rarity: rarity).combatBase;
  final growth = 1 + kBudgetGrowthPerLevel * (level - 1);
  return Combatant(
    id: id,
    name: archetype.name,
    element: CreatureElement.fire,
    rarity: rarity,
    isPlayerSide: isPlayerSide,
    level: level,
    isBoss: isBoss,
    stats: {
      for (final e in weights.entries)
        e.key: math.max(
          1,
          (e.value / weightSum * combatBase * budgetMult * growth).round(),
        ),
    },
    abilities: const [],
  );
}

class MatchupResult {
  final int runs;
  final double winRate;
  final double medianPlayerActions;

  /// Average fraction of the TEAM's total max HP lost per run (all runs,
  /// wins and losses alike).
  final double avgTeamHpLossPct;

  const MatchupResult({
    required this.runs,
    required this.winRate,
    required this.medianPlayerActions,
    required this.avgTeamHpLossPct,
  });
}

/// Runs [runs] seeded auto-battles. Factories build FRESH combatants per run
/// (the engine mutates them). Deterministic for a given seed.
MatchupResult simulateMatchup({
  required List<Combatant> Function(int run) teamFactory,
  required List<Combatant> Function(int run) enemyFactory,
  int runs = 200,
  int seed = 42,
  int actionGuard = 500,
}) {
  var wins = 0;
  final actionCounts = <int>[];
  var hpLossSum = 0.0;

  for (var run = 0; run < runs; run++) {
    final engine = CombatEngine(
      players: teamFactory(run),
      enemies: enemyFactory(run),
      rng: math.Random(seed + run),
    );
    var playerActions = 0;
    var guard = 0;
    while (engine.outcome == null && guard < actionGuard) {
      // Send the next reserve in when a slot opens (user 2026-07-27 — up to
      // three fight a side, so a party can lose one and fight on). Nobody is
      // here to be asked, and performAutoAction refuses to act while the pick
      // is owed: without this the loop span to its guard and scored a fight
      // that was still perfectly winnable as a loss.
      if (engine.needsPlayerSwitch && engine.autoSwitchIn()) continue;
      if (engine.isPlayerTurn) playerActions++;
      engine.performAutoAction();
      guard++;
    }
    if (engine.outcome == CombatOutcome.victory) wins++;
    actionCounts.add(playerActions);
    final maxHp = engine.players.fold<int>(0, (s, c) => s + c.maxHp);
    final hpLeft = engine.players.fold<int>(0, (s, c) => s + c.hp);
    hpLossSum += maxHp > 0 ? 1 - hpLeft / maxHp : 0;
    engine.dispose();
  }

  actionCounts.sort();
  final median = actionCounts.isEmpty
      ? 0.0
      : actionCounts.length.isOdd
      ? actionCounts[actionCounts.length ~/ 2].toDouble()
      : (actionCounts[actionCounts.length ~/ 2 - 1] +
                actionCounts[actionCounts.length ~/ 2]) /
            2.0;

  return MatchupResult(
    runs: runs,
    winRate: runs > 0 ? wins / runs : 0,
    medianPlayerActions: median,
    avgTeamHpLossPct: runs > 0 ? hpLossSum / runs : 0,
  );
}

/// The anchor matchup: a standard team of [teamSize] allrounders at
/// [teamLevel] vs [enemyCount] wild allrounders at [wildLevel] (boss: +20%
/// budget, the same elite bump Combatant.fromSpecies applies). Reference
/// encounter sizes: capture battles are 3v1, dungeon battle nodes spawn 2–3
/// wilds (the overworld's battle nodes).
MatchupResult simulateStandardMatchup({
  required int teamLevel,
  required int wildLevel,
  int teamSize = 3,
  int enemyCount = 1,
  bool boss = false,
  CreatureRarity teamRarity = CreatureRarity.common,
  CreatureRarity enemyRarity = CreatureRarity.common,
  int runs = 200,
  int seed = 42,
}) => simulateMatchup(
  teamFactory: (_) => [
    for (var i = 0; i < teamSize; i++)
      standardCombatant(level: teamLevel, rarity: teamRarity, id: 'p$i'),
  ],
  enemyFactory: (_) => [
    for (var i = 0; i < enemyCount; i++)
      standardCombatant(
        level: wildLevel,
        rarity: enemyRarity,
        isPlayerSide: false,
        isBoss: boss && i == 0, // boss packs: one boss, plain minions
        // Mirrors Combatant.fromSpecies: boss +20%, plain wild ×0.85.
        budgetMult: boss && i == 0 ? 1.2 : kWildStatMult,
        id: 'wild$i',
      ),
  ],
  runs: runs,
  seed: seed,
);
